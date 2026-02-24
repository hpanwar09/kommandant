# frozen_string_literal: true

require 'json'
require 'fileutils'

module Kommandant
  # Tracks session statistics, rank progression, and focus streaks.
  # Persists state to ~/.kommandant_stats.json so progress survives restarts.
  class Tracker
    STATS_PATH = File.expand_path('~/.kommandant_stats.json').freeze

    RANKS = [
      { name: 'Rekrut',        emoji: '🔰',      min_focus: 0 }.freeze,
      { name: 'Gefreiter',     emoji: '🪖',      min_focus: 30 }.freeze,
      { name: 'Unteroffizier', emoji: '⭐', min_focus: 60 }.freeze,
      { name: 'Feldwebel',     emoji: '⭐⭐', min_focus: 120 }.freeze,
      { name: 'Leutnant',      emoji: '🎖️', min_focus: 240 }.freeze,
      { name: 'Hauptmann',     emoji: '🎖️🎖️', min_focus: 480 }.freeze,
      { name: 'Generaloberst', emoji: '👑', min_focus: 960 }.freeze
    ].freeze

    SAVE_INTERVAL = 10 # ticks between auto-saves

    attr_reader :data

    def initialize
      @data = load_stats
      check_date_rollover!
      @tick_count = 0
      @current_slack_app = nil
      @current_slack_start = nil
    end

    # Record a working tick (called every poll interval)
    def record_working!
      @data['focus_seconds_today'] += poll_seconds
      @data['total_focus_seconds'] += poll_seconds
      @data['streak_seconds'] += poll_seconds

      # Update best streak
      if @data['streak_seconds'] > @data['best_streak_seconds_today']
        @data['best_streak_seconds_today'] = @data['streak_seconds']
      end

      # Close any open slack session
      close_slack_session!

      tick!
    end

    # Record a slacking tick
    # @param app [String] the offending application
    # @param url [String, nil] the offending URL
    def record_slacking!(app:, url: nil)
      @data['slack_seconds_today'] += poll_seconds
      @data['total_slack_seconds'] += poll_seconds
      @data['streak_seconds'] = 0

      track_slack_session(app, url)
      record_violation(app, url)
      tick!
    end

    # Record idle (not slacking, just away)
    def record_idle!
      close_slack_session!
      # Idle doesn't count as focus or slack — streak pauses but doesn't reset
      tick!
    end

    # Current military rank string
    def rank
      @data['rank'] || RANKS[0][:name]
    end

    # Rank emoji
    def rank_emoji
      rank_data = RANKS.find { |r| r[:name] == rank }
      rank_data ? rank_data[:emoji] : RANKS[0][:emoji]
    end

    # Current rank index (0-based)
    def rank_index
      idx = RANKS.index { |r| r[:name] == rank }
      idx || 0
    end

    # Current focus streak in minutes
    def streak_minutes
      (@data['streak_seconds'] || 0) / 60
    end

    # Total focus time today in minutes
    def focus_minutes_today
      (@data['focus_seconds_today'] || 0) / 60
    end

    # Total slack time today in minutes
    def slack_minutes_today
      (@data['slack_seconds_today'] || 0) / 60
    end

    # Array of violations today: [{ app:, url:, duration_seconds: }]
    def violations_today
      (@data['violations_today'] || []).map do |v|
        {
          app: v['app'],
          url: v['url'],
          duration_seconds: v['duration_seconds'] || 0
        }
      end
    end

    # Longest single slack session today
    def worst_offense_today
      return nil if @data['violations_today'].empty?

      worst = @data['violations_today'].max_by { |v| v['duration_seconds'] || 0 }
      return nil unless worst

      {
        app: worst['app'],
        url: worst['url'],
        duration_seconds: worst['duration_seconds'] || 0
      }
    end

    # Promote to next rank
    def promote!
      idx = rank_index
      return if idx >= RANKS.length - 1

      @data['rank'] = RANKS[idx + 1][:name]
      save!
    end

    # Demote to previous rank
    def demote!
      idx = rank_index
      return if idx <= 0

      @data['rank'] = RANKS[idx - 1][:name]
      save!
    end

    # Check if promotion is warranted based on accumulated focus
    # @return [Boolean] true if promoted
    def check_promotion!
      next_idx = rank_index + 1
      return false if next_idx >= RANKS.length

      next_rank = RANKS[next_idx]
      if focus_minutes_today >= next_rank[:min_focus]
        promote!
        true
      else
        false
      end
    end

    # Hash for Display.report consumption
    def daily_stats
      {
        focus_minutes: focus_minutes_today,
        slack_minutes: slack_minutes_today,
        rank: "#{rank_emoji} #{rank}",
        violations: violations_today,
        worst_offense: worst_offense_today
      }
    end

    # Reset daily counters (called at midnight or manually)
    def reset_daily!
      @data['focus_seconds_today'] = 0
      @data['slack_seconds_today'] = 0
      @data['streak_seconds'] = 0
      @data['best_streak_seconds_today'] = 0
      @data['violations_today'] = []
      @data['date'] = today_str
      save!
    end

    # Persist to JSON file
    def save!
      @data['updated_at'] = Time.now.iso8601
      File.write(STATS_PATH, JSON.pretty_generate(@data))
    rescue Errno::EACCES => e
      warn "[Kommandant::Tracker] Could not write #{STATS_PATH}: #{e.message}"
    end

    def track_slack_session(app, url)
      if @current_slack_app == app
        @current_slack_duration = (@current_slack_duration || 0) + poll_seconds
      else
        close_slack_session!
        @current_slack_app = app
        @current_slack_url = url
        @current_slack_start = Time.now
        @current_slack_duration = poll_seconds
      end
    end

    def record_violation(app, url)
      existing = @data['violations_today'].find { |v| v['app'] == app }
      if existing
        existing['count'] += 1
        existing['duration_seconds'] += poll_seconds
      else
        @data['violations_today'] << {
          'app' => app, 'url' => url,
          'count' => 1, 'duration_seconds' => poll_seconds
        }
      end
    end

    private

    # Poll interval in seconds — default 10, pulled from config if available
    def poll_seconds
      @poll_seconds ||= begin
        interval = Config.get('detection.poll_interval')
        interval.is_a?(Numeric) && interval.positive? ? interval : 10
      rescue StandardError
        10
      end
    end

    # Load stats from disk or initialize fresh
    def load_stats
      return fresh_stats unless File.exist?(STATS_PATH)

      raw = File.read(STATS_PATH)
      parsed = JSON.parse(raw)
      merge_defaults(parsed)
    rescue JSON::ParserError, Errno::ENOENT, Errno::EACCES => e
      warn "[Kommandant::Tracker] Could not load #{STATS_PATH}: #{e.message}"
      fresh_stats
    end

    # Default stats structure
    def fresh_stats
      {
        'rank' => RANKS[0][:name],
        'date' => today_str,
        'focus_seconds_today' => 0,
        'slack_seconds_today' => 0,
        'total_focus_seconds' => 0,
        'total_slack_seconds' => 0,
        'streak_seconds' => 0,
        'best_streak_seconds_today' => 0,
        'violations_today' => [],
        'created_at' => Time.now.iso8601,
        'updated_at' => Time.now.iso8601
      }
    end

    # Ensure all keys exist (for backward compatibility with older stat files)
    def merge_defaults(parsed)
      defaults = fresh_stats
      defaults.merge(parsed)
    end

    # Check if the stored date is today — if not, reset daily counters
    def check_date_rollover!
      return if @data['date'] == today_str

      # Preserve lifetime stats and rank, reset daily
      @data['focus_seconds_today'] = 0
      @data['slack_seconds_today'] = 0
      @data['streak_seconds'] = 0
      @data['best_streak_seconds_today'] = 0
      @data['violations_today'] = []
      @data['date'] = today_str
    end

    def today_str
      Time.now.strftime('%Y-%m-%d')
    end

    # Close any open slack session, update worst offense tracking
    def close_slack_session!
      @current_slack_app = nil
      @current_slack_url = nil
      @current_slack_start = nil
      @current_slack_duration = nil
    end

    # Tick bookkeeping — auto-save every N ticks
    def tick!
      @tick_count += 1
      save! if (@tick_count % SAVE_INTERVAL).zero?
    end
  end
end

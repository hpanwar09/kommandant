# frozen_string_literal: true

module Kommandant
  # Classifies a detector snapshot into work/slack/neutral status
  # and computes a slack score. Tracks accumulated slack time for tier escalation.
  class Classifier
    attr_reader :accumulated_slack_seconds

    # @param config [Hash] the loaded config hash (Kommandant::Config.to_h)
    def initialize(config)
      @config = config
      @accumulated_slack_seconds = 0
      @slack_started_at = nil
      @last_status = :neutral
    end

    # Classify a detector snapshot into a result hash.
    #
    # @param snapshot [Hash] from Detector#snapshot — keys: :idle_seconds, :app, :url, :title, :locked, :meeting
    # @return [Hash] { status:, slack_score:, reason:, app:, url: }
    def classify(snapshot)
      app = snapshot[:app] || 'unknown'
      url = snapshot[:url]
      idle = snapshot[:idle_seconds] || 0
      locked = snapshot[:locked] || false
      meeting = snapshot[:meeting] || false
      domain = extract_domain(url)

      result = evaluate(app, domain, url, idle, locked, meeting)

      update_accumulation(result[:status])

      result.merge(app: app, url: domain)
    end

    # Returns the current tier (0-4) based on accumulated slack time vs tier thresholds.
    # 0 means no tier triggered yet.
    def current_tier
      tiers = @config.fetch('tiers', {})

      active_tier = 0
      [4, 3, 2, 1].each do |tier_num|
        tier_config = tiers[tier_num] || tiers[tier_num.to_s] || {}
        next unless tier_config['enabled']

        threshold = tier_config['after'].to_i
        if @accumulated_slack_seconds >= threshold
          active_tier = tier_num
          break
        end
      end

      active_tier
    end

    # Reset accumulated slack time (called when user gets back to work).
    def reset!
      @accumulated_slack_seconds = 0
      @slack_started_at = nil
      @last_status = :neutral
    end

    private

    # Core evaluation logic. Returns { status:, slack_score:, reason: }.
    def evaluate(app, domain, _url, idle, locked, meeting)
      idle_threshold = dig_config('detection', 'idle_threshold') || 60

      check_locked(locked) ||
        check_meeting(meeting, app) ||
        check_blocked_url(domain, idle, idle_threshold) ||
        check_allowed_url(domain) ||
        check_work_app(app) ||
        check_blocked_app(app, idle, idle_threshold) ||
        check_idle(idle, idle_threshold) ||
        { status: :neutral, slack_score: 0, reason: 'No violation detected' }
    end

    def check_locked(locked)
      return unless locked

      { status: :away, slack_score: 0, reason: 'Screen is locked' }
    end

    def check_meeting(meeting, app)
      return unless meeting

      { status: :meeting, slack_score: 0, reason: "In a meeting (#{app})" }
    end

    def check_blocked_url(domain, idle, idle_threshold)
      return unless domain && url_blocked?(domain)

      score = idle > idle_threshold ? 4 : 3
      { status: :slacking, slack_score: score, reason: format_reason("On #{domain}", @accumulated_slack_seconds) }
    end

    def check_allowed_url(domain)
      return unless domain && url_allowed?(domain)

      { status: :working, slack_score: 0, reason: "On #{domain}" }
    end

    def check_work_app(app)
      return unless work_app?(app)

      { status: :working, slack_score: 0, reason: "Using #{app}" }
    end

    def check_blocked_app(app, idle, idle_threshold)
      return unless blocked_app?(app)

      score = idle > idle_threshold ? 4 : 2
      { status: :slacking, slack_score: score, reason: format_reason("Using #{app}", @accumulated_slack_seconds) }
    end

    def check_idle(idle, idle_threshold)
      return unless idle > idle_threshold

      { status: :away, slack_score: 0, reason: "Idle for #{format_duration(idle)}" }
    end

    # Update accumulated slack tracking based on current status.
    def update_accumulation(status)
      case status
      when :slacking then accumulate_slack
      when :working then reset_if_slacking
      end
      # :away, :meeting, :neutral don't reset — keep count if they were slacking before
      @last_status = status
    end

    def accumulate_slack
      now = Time.now
      if @last_status == :slacking && @slack_started_at
        @accumulated_slack_seconds = (now - @slack_started_at).to_i
      else
        @slack_started_at = now
        @accumulated_slack_seconds = 0
      end
    end

    def reset_if_slacking
      return unless @last_status == :slacking

      @accumulated_slack_seconds = 0
      @slack_started_at = nil
    end

    # Check if app name matches any work app (case-insensitive).
    def work_app?(app)
      work_apps = @config.fetch('work_apps', [])
      work_apps.any? { |wa| app.downcase.include?(wa.downcase) || wa.downcase.include?(app.downcase) }
    end

    # Check if app name matches any blocked app (case-insensitive).
    def blocked_app?(app)
      blocked_apps = @config.fetch('blocked_apps', [])
      blocked_apps.any? { |ba| app.downcase == ba.downcase }
    end

    # Check if domain matches any blocked URL.
    def url_blocked?(domain)
      blocked_urls = @config.fetch('blocked_urls', [])
      blocked_urls.any? { |blocked| domain.downcase.include?(blocked.downcase) }
    end

    # Check if domain matches any allowed URL.
    def url_allowed?(domain)
      allowed_urls = @config.fetch('allowed_urls', [])
      allowed_urls.any? { |allowed| domain.downcase.include?(allowed.downcase) }
    end

    # Extract domain from a URL string. Returns nil if unparseable.
    def extract_domain(url)
      return nil if url.nil? || url.empty?

      # Strip protocol
      domain = url.sub(%r{\Ahttps?://}, '')
      # Strip path, query, fragment
      domain = domain.split('/').first
      # Strip port
      domain = domain.split(':').first
      # Strip www.
      domain = domain.sub(/\Awww\./, '')
      domain.empty? ? nil : domain.downcase
    rescue StandardError
      nil
    end

    # Dig into config hash with string keys.
    def dig_config(*keys)
      keys.reduce(@config) do |current, key|
        return nil unless current.is_a?(Hash)

        current[key] || current[key.to_s]
      end
    end

    # Format a duration in seconds as a human-readable string.
    def format_duration(seconds)
      return '0s' if seconds <= 0

      mins = seconds / 60
      secs = seconds % 60

      if mins.positive?
        "#{mins}m #{secs}s"
      else
        "#{secs}s"
      end
    end

    # Format a reason string with accumulated time if > 0.
    def format_reason(base, accumulated)
      if accumulated.positive?
        "#{base} for #{format_duration(accumulated)}"
      else
        base
      end
    end
  end
end

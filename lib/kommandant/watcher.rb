# frozen_string_literal: true

require 'fileutils'

module Kommandant
  # The main daemon loop that ties detection, classification, notification,
  # tracking, and notification together. Runs in the foreground as a patrol loop.
  class Watcher
    PID_PATH = File.expand_path('~/.kommandant.pid').freeze

    attr_reader :tracker

    def initialize
      @running = false
      @tracker = nil
      @last_notified_tier = 0
      @was_slacking = false
      @tick_count = 0
      @accumulated_slack_seconds = 0
    end

    # Start the patrol loop (blocking, runs in foreground)
    def start!
      check_existing_instance!
      write_pid!

      setup_signal_handlers!
      initialize_components!

      puts pastel.red("\n[Kommandant] Herr Kommandant is watching. Jawohl!\n")
      @running = true

      puts "[Kommandant] Patrol started. Poll interval: #{poll_interval}s"
      puts "[Kommandant] Active hours: #{Config.get('schedule.active_hours')}"
      puts

      run_loop
    ensure
      cleanup!
    end

    # Stop gracefully
    def stop!
      @running = false
      if @tracker
        @tracker.save!
        puts
      end
      puts pastel.yellow('Herr Kommandant dismissed. At ease, soldier.')
    end

    # Boolean — is the watcher currently running?
    def running?
      @running
    end

    private

    def initialize_components!
      Config.load
      @tracker = Tracker.new
      @detector = Detector.new
      @classifier = Classifier.new
      @notifier = Notifier.new
      @last_midnight_check = Time.now
    end

    def run_loop
      while @running
        loop_start = Time.now

        if outside_active_hours?
          sleep_until_active!
          next
        end

        process_tick!

        # Timing: account for processing time so ticks don't drift
        elapsed = Time.now - loop_start
        sleep_time = [poll_interval - elapsed, 0].max
        sleep(sleep_time) if @running
      end
    end

    def process_tick!
      @tick_count += 1
      snapshot = @detector.snapshot
      classification = @classifier.classify(snapshot)

      dispatch_status(classification, snapshot)
      check_midnight_rollover!
    rescue StandardError => e
      warn "[Kommandant] Tick error: #{e.message}"
    end

    def dispatch_status(classification, snapshot)
      case classification[:status]
      when :meeting, :away
        @tracker.record_idle!
        reset_slack_accumulator!
      when :working then handle_working!(classification)
      when :slacking then handle_slacking!(classification, snapshot)
      when :neutral then @tracker.record_idle!
      end
    end

    def handle_working!(_classification)
      @tracker.record_working!

      # Check for promotion
      puts pastel.green("PROMOTED to #{@tracker.rank}! Herr Kommandant approves!") if @tracker.check_promotion!

      # If was slacking, praise return to work
      return unless @was_slacking

      puts pastel.green('Good. Back to work. Herr Kommandant is watching.')
      @was_slacking = false
      reset_slack_accumulator!
    end

    def handle_slacking!(classification, snapshot)
      app = classification[:app] || snapshot[:active_app] || 'unknown'
      url = classification[:url] || snapshot[:active_url]

      @tracker.record_slacking!(app: app, url: url)
      @accumulated_slack_seconds += poll_interval
      @was_slacking = true

      escalate_if_needed(app, url)
    end

    def escalate_if_needed(app, url)
      current_tier = Tier.for_seconds(@accumulated_slack_seconds, Config)
      return unless current_tier > @last_notified_tier

      trigger_tier_notification(current_tier, app, url)
      @last_notified_tier = current_tier
    end

    def trigger_tier_notification(tier, app, url)
      reason = build_reason(app, url)
      @notifier.notify(tier: tier, reason: reason, rank: @tracker.rank, streak: @tracker.streak_minutes)

      return unless tier >= 3

      @tracker.demote!
      puts pastel.red("DEMOTED to #{@tracker.rank}!")
    end

    def build_reason(app, url)
      if url && !url.empty?
        "Caught on #{url} (#{app})"
      else
        "Caught using #{app}"
      end
    end

    def reset_slack_accumulator!
      @accumulated_slack_seconds = 0
      @last_notified_tier = 0
    end

    # Schedule checking

    def outside_active_hours?
      schedule = Config.get('schedule')
      return false unless schedule

      hours_str = schedule['active_hours']
      days_str = schedule['active_days']

      return false unless hours_str && days_str
      return true unless active_day?(days_str)
      return true unless active_hour?(hours_str)

      false
    end

    def active_day?(days_str)
      day_map = { 'mon' => 1, 'tue' => 2, 'wed' => 3, 'thu' => 4, 'fri' => 5, 'sat' => 6, 'sun' => 0 }

      parts = days_str.downcase.split('-')
      return true if parts.length != 2

      start_day = day_map[parts[0]] || 0
      end_day = day_map[parts[1]] || 6
      today = Time.now.wday

      if start_day <= end_day
        today.between?(start_day, end_day)
      else
        today >= start_day || today <= end_day
      end
    end

    def active_hour?(hours_str)
      parts = hours_str.split('-')
      return true if parts.length != 2

      start_h, start_m = parts[0].split(':').map(&:to_i)
      end_h, end_m = parts[1].split(':').map(&:to_i)

      now = Time.now
      now_minutes = (now.hour * 60) + now.min
      start_minutes = (start_h * 60) + (start_m || 0)
      end_minutes = (end_h * 60) + (end_m || 0)

      now_minutes >= start_minutes && now_minutes < end_minutes
    end

    def sleep_until_active!
      puts pastel.dim('[Kommandant] Outside active hours. Sleeping...') if @tick_count <= 1
      sleep(60) # Check every minute
    end

    # Midnight rollover

    def check_midnight_rollover!
      now = Time.now
      return unless now.strftime('%Y-%m-%d') != @last_midnight_check.strftime('%Y-%m-%d')

      puts pastel.cyan('[Kommandant] Midnight! Generating daily report...')
      puts pastel.cyan("[Kommandant] Daily stats: #{@tracker.daily_stats.inspect}")
      @tracker.reset_daily!
      reset_slack_accumulator!
      @last_midnight_check = now
    end

    # PID management

    def check_existing_instance!
      return unless File.exist?(PID_PATH)

      existing_pid = File.read(PID_PATH).strip.to_i
      if existing_pid.positive? && process_alive?(existing_pid)
        warn "[Kommandant] Another instance is already running (PID: #{existing_pid})."
        warn "[Kommandant] Kill it with: kill #{existing_pid}"
        warn "[Kommandant] Or remove #{PID_PATH} if it's stale."
        exit(1)
      else
        # Stale PID file — clean it up
        File.delete(PID_PATH)
      end
    rescue Errno::ENOENT
      # File disappeared between check and read — that's fine
    end

    def process_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH, Errno::EPERM
      false
    end

    def write_pid!
      File.write(PID_PATH, Process.pid.to_s)
    rescue Errno::EACCES => e
      warn "[Kommandant] Could not write PID file: #{e.message}"
    end

    def delete_pid!
      FileUtils.rm_f(PID_PATH)
    rescue Errno::ENOENT, Errno::EACCES
      # Ignore
    end

    # Signal handling

    def setup_signal_handlers!
      %w[INT TERM].each do |signal|
        Signal.trap(signal) do
          puts "\n[Kommandant] Signal #{signal} received. Shutting down..."
          stop!
        end
      end
    end

    # Cleanup on exit

    def cleanup!
      @tracker&.save!
      delete_pid!
    end

    # Helpers

    def poll_interval
      @poll_interval ||= begin
        interval = Config.get('detection.poll_interval')
        interval.is_a?(Numeric) && interval.positive? ? interval : 10
      rescue StandardError
        10
      end
    end

    def pastel
      @pastel ||= Pastel.new
    end
  end
end

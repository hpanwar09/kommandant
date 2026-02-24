# frozen_string_literal: true

require 'thor'

module Kommandant
  class CLI < Thor
    desc 'start', "Start Herr Kommandant's patrol"
    option :strict, type: :boolean, desc: 'Enable all tiers, no mercy'
    option :chill, type: :boolean, desc: 'Only tier 1-2, no voice, no video'
    option :silent, type: :boolean, desc: 'Monitor + report only, no interruptions'
    def start
      apply_mode_overrides!(options)
      watcher = Watcher.new
      watcher.start!
    end

    desc 'stop', 'Dismiss Herr Kommandant'
    def stop
      pid_file = File.expand_path('~/.kommandant.pid')
      unless File.exist?(pid_file)
        puts 'Herr Kommandant is not on patrol.'
        return
      end

      pid = File.read(pid_file).strip.to_i
      begin
        Process.kill('TERM', pid)
        puts 'Herr Kommandant dismissed. At ease, soldier.'
      rescue Errno::ESRCH
        puts 'Herr Kommandant was already gone. Cleaning up.'
        File.delete(pid_file)
      end
    end

    desc 'status', 'Show current rank, streak, and patrol status'
    def status
      Config.load
      tracker = Tracker.new
      pid_file = File.expand_path('~/.kommandant.pid')
      patrol_active = File.exist?(pid_file) && process_alive?(File.read(pid_file).strip.to_i)

      puts "Rank: #{tracker.rank} #{tracker.rank_emoji}"
      puts "Streak: #{tracker.streak_minutes} min"
      puts "Patrol: #{patrol_active ? 'ACTIVE' : 'INACTIVE'}"
      puts "Focus today: #{tracker.focus_minutes_today} min"
      puts "Slack today: #{tracker.slack_minutes_today} min"
    end

    desc 'report', "Show today's Tagesbericht"
    def report
      Config.load
      tracker = Tracker.new
      puts YAML.dump(tracker.daily_stats)
    end

    desc 'config SUBCOMMAND', 'Manage configuration'
    option :key, type: :string, desc: "Config key (dot notation, e.g. 'voice.enabled')"
    option :value, type: :string, desc: 'Value to set'
    def config(subcommand = 'list')
      Config.load

      case subcommand
      when 'list'   then display_config
      when 'set'    then config_set
      when 'add'    then config_add
      when 'remove' then config_remove
      when 'reset'  then config_reset
      when 'path'   then puts Config::CONFIG_PATH
      else config_unknown(subcommand)
      end
    end

    desc 'suppress DURATION', "Suppress patrol for a duration (e.g. '30m', '1h', 'until 14:00')"
    def suppress(duration = '30m')
      seconds = parse_duration(duration)
      suppress_until = Time.now + seconds
      File.write(File.expand_path('~/.kommandant_suppress'), suppress_until.iso8601)
      minutes = (seconds / 60.0).ceil
      puts "Patrol suppressed for #{minutes} minutes. " \
           "Herr Kommandant grants you leave until #{suppress_until.strftime('%H:%M')}."
    end

    desc 'version', 'Show version'
    def version
      puts "Kommandant v#{VERSION}"
    end

    map %w[--version -v] => :version

    private

    def apply_mode_overrides!(opts)
      Config.load
      if opts[:strict]
        (1..4).each { |t| Config.set("tiers.#{t}.enabled", true) }
      elsif opts[:chill]
        Config.set('tiers.1.enabled', true)
        Config.set('tiers.2.enabled', true)
        Config.set('tiers.3.enabled', false)
        Config.set('tiers.4.enabled', false)
        Config.set('voice.enabled', false)
      elsif opts[:silent]
        (1..4).each { |t| Config.set("tiers.#{t}.enabled", false) }
      else
        Config.load
      end
    end

    def display_config
      require 'yaml'
      puts YAML.dump(Config.to_h)
    end

    def config_set
      key, value = require_key_value!('set')
      Config.set(key, coerce_value(value))
      puts "Set #{key} = #{value}"
    end

    def config_add
      key, value = require_key_value!('add')
      Config.add(key, value)
      puts "Added '#{value}' to #{key}"
    end

    def config_remove
      key, value = require_key_value!('remove')
      Config.remove(key, value)
      puts "Removed '#{value}' from #{key}"
    end

    def config_reset
      Config.reset!
      puts 'Configuration reset to defaults.'
    end

    def config_unknown(subcommand)
      puts "Unknown subcommand: #{subcommand}"
      puts 'Available: list, set, add, remove, reset, path'
    end

    def require_key_value!(action)
      key = options[:key] || shift_args(1)
      value = options[:value] || shift_args(2)
      abort "Usage: kommandant config #{action} --key KEY --value VALUE" unless key && value
      [key, value]
    end

    def coerce_value(val)
      case val.downcase
      when 'true' then true
      when 'false' then false
      when /\A\d+\z/ then val.to_i
      when /\A\d+\.\d+\z/ then val.to_f
      else val
      end
    end

    def parse_duration(input)
      case input
      when /\A(\d+)m\z/ then ::Regexp.last_match(1).to_i * 60
      when /\A(\d+)h\z/ then ::Regexp.last_match(1).to_i * 3600
      when /\Auntil\s+(\d{1,2}):(\d{2})\z/
        target = Time.new(Time.now.year, Time.now.month, Time.now.day,
                          ::Regexp.last_match(1).to_i, ::Regexp.last_match(2).to_i)
        target += 86_400 if target < Time.now
        (target - Time.now).to_i
      else
        1800 # default 30 min
      end
    end

    def shift_args(index)
      ARGV[index + 1]
    end

    def process_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH, Errno::EPERM
      false
    end
  end
end

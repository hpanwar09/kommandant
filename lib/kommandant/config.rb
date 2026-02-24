# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module Kommandant
  # Manages reading/writing of ~/.kommandant.yml configuration.
  # All access is through class methods for global singleton behavior.
  module Config
    CONFIG_PATH = File.expand_path('~/.kommandant.yml').freeze

    DEFAULTS = {
      'detection' => {
        'idle' => true,
        'idle_threshold' => 60,
        'apps' => true,
        'browser_tabs' => true,
        'poll_interval' => 10
      },
      'voice' => {
        'enabled' => true,
        'language' => 'de',
        'accent' => 'de',
        'tts_voice' => 'Anna',
        'speed' => 185
      },
      'blocked_apps' => %w[
        Messages
        Discord
        Photos
        TV
        Music
        News
        TikTok
      ],
      'work_apps' => [
        'rubymine',
        'RubyMine',
        'ghostty',
        'Ghostty',
        'Terminal',
        'iTerm2',
        'VS Code',
        'Code',
        'Xcode',
        'Cursor',
        'Emacs',
        'Vim'
      ],
      'blocked_urls' => %w[
        youtube.com
        reddit.com
        twitter.com
        x.com
        instagram.com
        tiktok.com
        netflix.com
        twitch.tv
        facebook.com
      ],
      'allowed_urls' => %w[
        github.com
        stackoverflow.com
        docs.ruby-lang.org
        atlassian.net
        jira.com
        coralogix.com
        newrelic.com
        one.newrelic.com
        salesforce.com
        lightning.force.com
        confluence.com
        bitbucket.org
        gitlab.com
        linear.app
        notion.so
        figma.com
        vercel.com
        heroku.com
        aws.amazon.com
        console.cloud.google.com
        portal.azure.com
        datadog.com
        sentry.io
        grafana.com
        pagerduty.com
        circleci.com
        travis-ci.com
        rubygems.org
        bundler.io
        localhost
      ],
      'tiers' => {
        1 => {
          'enabled' => true,
          'after' => 60,
          'sound' => 'soft',
          'voice' => false
        },
        2 => {
          'enabled' => true,
          'after' => 180,
          'sound' => 'hard',
          'voice' => true
        },
        3 => {
          'enabled' => false,
          'after' => 300,
          'video' => true,
          'volume' => 80
        },
        4 => {
          'enabled' => false,
          'after' => 900
        }
      },
      'schedule' => {
        'active_hours' => '09:00-18:00',
        'active_days' => 'mon-fri'
      }
    }.freeze

    class << self
      # Load config from disk. Creates default file if missing.
      # Returns the loaded config hash.
      def load
        write_defaults! unless File.exist?(CONFIG_PATH)

        raw = File.read(CONFIG_PATH)
        @config = if raw.strip.empty?
                    deep_dup(DEFAULTS)
                  else
                    parsed = YAML.safe_load(raw, permitted_classes: [Symbol]) || {}
                    deep_merge(deep_dup(DEFAULTS), parsed)
                  end
      rescue Errno::ENOENT, Errno::EACCES => e
        warn "[Kommandant::Config] Could not read #{CONFIG_PATH}: #{e.message}"
        @config = deep_dup(DEFAULTS)
      end

      # Get a value using dot-notation keys.
      # Example: Config.get("tiers.1.enabled") → true
      def get(key)
        ensure_loaded
        keys = parse_key(key)
        dig_value(@config, keys)
      end

      # Set a value using dot-notation keys and persist to disk.
      # Example: Config.set("tiers.3.enabled", true)
      def set(key, value)
        ensure_loaded
        keys = parse_key(key)
        set_nested(@config, keys, value)
        persist!
        value
      end

      # Append a value to an array at the given key.
      # Example: Config.add("blocked_urls", "youtube.com")
      def add(key, value)
        ensure_loaded
        keys = parse_key(key)
        current = dig_value(@config, keys)

        if current.is_a?(Array)
          unless current.include?(value)
            current << value
            persist!
          end
        else
          # If not an array, create one
          set_nested(@config, keys, [value])
          persist!
        end
        dig_value(@config, keys)
      end

      # Remove a value from an array at the given key.
      # Example: Config.remove("blocked_urls", "youtube.com")
      def remove(key, value)
        ensure_loaded
        keys = parse_key(key)
        current = dig_value(@config, keys)

        return unless current.is_a?(Array)

        removed = current.delete(value)
        persist! if removed
        removed
      end

      # Reset config to defaults and persist.
      def reset!
        @config = deep_dup(DEFAULTS)
        persist!
        @config
      end

      # Return the full config hash.
      def to_h
        ensure_loaded
        @config.dup
      end

      private

      def ensure_loaded
        self.load unless @config
      end

      def write_defaults!
        dir = File.dirname(CONFIG_PATH)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
        File.write(CONFIG_PATH, serialize(@config || DEFAULTS))
      rescue Errno::EACCES => e
        warn "[Kommandant::Config] Could not write #{CONFIG_PATH}: #{e.message}"
      end

      def persist!
        File.write(CONFIG_PATH, serialize(@config))
      rescue Errno::EACCES => e
        warn "[Kommandant::Config] Could not write #{CONFIG_PATH}: #{e.message}"
      end

      # Serialize config hash to YAML string.
      # Convert integer keys to integers in YAML output for tiers.
      def serialize(hash)
        YAML.dump(stringify_keys(hash))
      end

      # Parse dot-notation key into array of keys, coercing numeric segments to integers.
      def parse_key(key)
        key.to_s.split('.').map do |segment|
          if segment.match?(/\A\d+\z/)
            segment.to_i
          else
            segment
          end
        end
      end

      # Dig into a nested hash/array with an array of keys.
      def dig_value(hash, keys)
        keys.reduce(hash) do |current, key|
          case current
          when Hash
            current[key]
          when Array
            key.is_a?(Integer) ? current[key] : nil
          end
        end
      end

      # Set a value deep in a nested hash, creating intermediate hashes as needed.
      def set_nested(hash, keys, value)
        *path, final = keys
        target = path.reduce(hash) do |current, key|
          case current
          when Hash
            current[key] ||= {}
            current[key]
          else
            break nil
          end
        end

        target[final] = value if target.is_a?(Hash)
      end

      # Deep merge two hashes. Values in `override` take precedence.
      def deep_merge(base, override)
        base.merge(override) do |_key, old_val, new_val|
          if old_val.is_a?(Hash) && new_val.is_a?(Hash)
            deep_merge(old_val, new_val)
          else
            new_val
          end
        end
      end

      # Deep duplicate a hash/array structure.
      def deep_dup(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), h| h[k] = deep_dup(v) }
        when Array
          obj.map { |v| deep_dup(v) }
        else
          obj
        end
      end

      # Convert all keys to a YAML-friendly format.
      # Integer keys (tiers) stay as integers for YAML compatibility.
      def stringify_keys(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(k, v), h|
            h[k] = stringify_keys(v)
          end
        when Array
          obj.map { |v| stringify_keys(v) }
        else
          obj
        end
      end
    end
  end
end

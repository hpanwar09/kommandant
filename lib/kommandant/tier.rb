# frozen_string_literal: true

module Kommandant
  # Simple tier definitions and threshold logic.
  # Tiers escalate from silent monitoring (0) through nuclear (4).
  # Threshold seconds come from config; enabled/disabled flags are respected.
  module Tier
    TIERS = {
      0 => { name: "Reconnaissance",    description: "Silent monitoring",         color: :white }.freeze,
      1 => { name: "Gentle Nudge",      description: "Notification + soft sound", color: :yellow }.freeze,
      2 => { name: "Stern Warning",     description: "German voice + loud sound", color: :bright_yellow }.freeze,
      3 => { name: "Full Intervention", description: "Video + volume override",   color: :red }.freeze,
      4 => { name: "Nuclear",           description: "Full chaos mode",           color: :bright_red }.freeze
    }.freeze

    # Default thresholds (seconds) used when config is unavailable
    DEFAULT_THRESHOLDS = { 1 => 60, 2 => 300, 3 => 600, 4 => 1500 }.freeze

    class << self
      # Determine the appropriate tier based on accumulated slack seconds.
      # Returns the highest tier that is both reached AND enabled in config.
      # If a higher tier is disabled, it falls back to the highest enabled tier
      # below it — never skips up past a disabled tier.
      #
      # @param accumulated_seconds [Integer] seconds of continuous slacking
      # @param config [Module] Kommandant::Config (or anything responding to .get)
      # @return [Integer] tier number 0–4
      def for_seconds(accumulated_seconds, config)
        return 0 if accumulated_seconds <= 0

        highest_reached = 0

        (1..4).each do |tier_num|
          threshold = threshold_for(tier_num, config)
          next unless threshold
          next unless accumulated_seconds >= threshold

          highest_reached = tier_num if enabled?(tier_num, config)
        end

        highest_reached
      end

      # Get info hash for a given tier number.
      # @param tier_number [Integer] 0–4
      # @return [Hash] { name:, description:, color: }
      def info(tier_number)
        TIERS.fetch(tier_number, TIERS[0]).dup
      end

      # Check if a tier is enabled in config.
      # Tier 0 is always enabled (it's just monitoring).
      # @param tier_number [Integer] 0–4
      # @param config [Module] Kommandant::Config
      # @return [Boolean]
      def enabled?(tier_number, config)
        return true if tier_number.zero?

        value = fetch_tier_field(tier_number, "enabled", config)

        # Treat nil as enabled by default for tiers 1–2, disabled for 3–4
        if value.nil?
          tier_number <= 3
        else
          !!value
        end
      end

      # Convenience: tier name string
      # @param tier_number [Integer]
      # @return [String]
      def name(tier_number)
        info(tier_number)[:name]
      end

      # Convenience: tier color symbol
      # @param tier_number [Integer]
      # @return [Symbol]
      def color(tier_number)
        info(tier_number)[:color]
      end

      # Return all tier info as a formatted array for display.
      # @param config [Module, nil] Kommandant::Config
      # @return [Array<Hash>] all tiers with number, info, and enabled status
      def all_tiers(config = nil)
        TIERS.map do |num, tier_info|
          entry = tier_info.dup
          entry[:number] = num
          entry[:enabled] = config ? enabled?(num, config) : true
          if config && num.positive?
            entry[:after_seconds] = threshold_for(num, config)
          end
          entry
        end
      end

      private

      # Get the threshold in seconds for a specific tier from config.
      # Config stores thresholds in the "after" key (in seconds).
      # @param tier_num [Integer]
      # @param config [Module]
      # @return [Integer, nil]
      def threshold_for(tier_num, config)
        value = fetch_tier_field(tier_num, "after", config)
        return DEFAULT_THRESHOLDS[tier_num] if value.nil?
        return nil unless value.is_a?(Numeric) && value.positive?

        value.to_i
      end

      # Fetch a field from the tier config, supporting both
      # Config.get (dot-notation module) and raw hash access.
      # @param tier_num [Integer]
      # @param field [String]
      # @param config [Module, Hash]
      # @return [Object, nil]
      def fetch_tier_field(tier_num, field, config)
        if config.respond_to?(:get)
          config.get("tiers.#{tier_num}.#{field}")
        elsif config.is_a?(Hash)
          tier_data = config.dig("tiers", tier_num) || config.dig("tiers", tier_num.to_s)
          tier_data && (tier_data[field] || tier_data[field.to_sym])
        end
      rescue StandardError
        nil
      end
    end
  end
end

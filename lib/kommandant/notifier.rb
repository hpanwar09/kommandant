# frozen_string_literal: true

module Kommandant
  # Delivers macOS notifications, sounds, and TTS based on tier level.
  # Respects config for voice.enabled, tier.enabled, and voice settings.
  # All system calls are wrapped in begin/rescue — never crashes.
  class Notifier
    GERMAN_TIER2_LINES = [
      'Achtung! Was machen Sie da?',
      'Zurück an die Arbeit, sofort!',
      'Das ist unakzeptabel!',
      'Herr Kommandant ist nicht erfreut!',
      'Sie sind eine Enttäuschung!',
      'Disziplin! Haben Sie das vergessen?',
      'Ich beobachte Sie! Arbeiten Sie!',
      'Schluss mit dem Unsinn!'
    ].freeze

    GERMAN_TIER3_LINES = [
      'Das ist Ihre letzte Warnung! Herr Kommandant verliert die Geduld!',
      'Sie haben es so gewollt! Die Konsequenzen sind unvermeidlich!',
      'Drei Mal habe ich Sie gewarnt! Jetzt reicht es!',
      'Sie testen meine Geduld, und meine Geduld hat ein Ende!',
      'Herr Kommandant greift jetzt zu drastischen Maßnahmen!'
    ].freeze

    GERMAN_TIER4_LINES = [
      'ALARM! ALARM! TOTALER ARBEITSVERWEIGERUNG FESTGESTELLT!',
      'ACHTUNG! SOFORTIGE RÜCKKEHR ZUR ARBEIT ODER ES FOLGEN KONSEQUENZEN!',
      'HERR KOMMANDANT HAT GENUG! DAS IST DER LETZTE BEFEHL!'
    ].freeze

    PRAISE_LINES = [
      'Gut gemacht, Soldat!',
      'Sehr gut! So ist es richtig!',
      'Ausgezeichnet! Weiter so!',
      'Herr Kommandant ist zufrieden!',
      'Disziplin zahlt sich aus!'
    ].freeze

    INTERVENTION_VIDEO = 'https://www.youtube.com/watch?v=OO14VSx74MU'

    # Sounds available on macOS
    SOUNDS = {
      tink: '/System/Library/Sounds/Tink.aiff',
      basso: '/System/Library/Sounds/Basso.aiff',
      sosumi: '/System/Library/Sounds/Sosumi.aiff',
      hero: '/System/Library/Sounds/Hero.aiff',
      funk: '/System/Library/Sounds/Funk.aiff',
      blow: '/System/Library/Sounds/Blow.aiff',
      submarine: '/System/Library/Sounds/Submarine.aiff',
      glass: '/System/Library/Sounds/Glass.aiff'
    }.freeze

    # @param config [Hash] the loaded config hash (Kommandant::Config.to_h)
    def initialize(config)
      @config = config
    end

    # Deliver a notification for the given tier.
    #
    # @param tier [Integer] 1-4
    # @param reason [String] why they're being notified
    # @param rank [String] optional rank display
    # @param streak [Integer] optional streak count
    def notify(tier:, reason:, rank: nil, streak: nil) # rubocop:disable Lint/UnusedMethodArgument
      return unless tier_enabled?(tier)

      case tier
      when 1 then notify_tier1(reason, rank)
      when 2 then notify_tier2(reason, rank)
      when 3 then notify_tier3(reason, rank)
      when 4 then notify_tier4(reason, rank)
      end
    end

    # Positive reinforcement when user gets back to work.
    #
    # @param rank [String] optional rank display
    # @param streak_minutes [Integer] how many minutes of focused work
    def praise(rank: nil, streak_minutes: 0) # rubocop:disable Lint/UnusedMethodArgument
      line = PRAISE_LINES.sample
      message = if streak_minutes > 0
                  "#{line} #{streak_minutes} minutes focused."
                else
                  line
                end

      display_notification(
        message: message,
        title: '🎖️ Herr Kommandant',
        subtitle: 'Impressive, Soldat!',
        sound: 'Hero'
      )
      play_sound(:hero)

      return unless voice_enabled?

      speak(line)
    end

    private

    # --- Tier Implementations ---

    def notify_tier1(reason, _rank)
      display_notification(
        message: reason,
        title: '🎖️ Herr Kommandant',
        subtitle: 'Gentle Reminder',
        sound: 'Tink'
      )
      play_sound(:tink)
    end

    def notify_tier2(reason, _rank)
      display_notification(
        message: reason,
        title: '🎖️ Herr Kommandant',
        subtitle: 'Stern Warning',
        sound: 'Basso'
      )
      play_sound(:basso)

      return unless voice_enabled?

      line = GERMAN_TIER2_LINES.sample
      speak(line)
    end

    def notify_tier3(reason, _rank)
      # Set volume
      volume = tier_config(3)['volume'] || 80
      set_volume(volume)

      display_notification(
        message: reason,
        title: '⚠️ HERR KOMMANDANT',
        subtitle: 'FINAL WARNING',
        sound: 'Sosumi'
      )
      play_sound(:sosumi)

      # Open intervention video
      open_url(INTERVENTION_VIDEO) if tier_config(3)['video']

      return unless voice_enabled?

      line = GERMAN_TIER3_LINES.sample
      speak(line)
    end

    def notify_tier4(reason, _rank)
      # Volume to max
      set_volume(100)

      display_notification(
        message: reason,
        title: '🚨 HERR KOMMANDANT 🚨',
        subtitle: 'NUCLEAR OPTION ACTIVATED',
        sound: 'Sosumi'
      )

      # Multiple system sounds
      play_sound(:basso)
      play_sound(:funk)
      play_sound(:submarine)

      # Open video 3 times with different timestamps
      open_url("#{INTERVENTION_VIDEO}&t=0")
      open_url("#{INTERVENTION_VIDEO}&t=30")
      open_url("#{INTERVENTION_VIDEO}&t=60")

      # Two TTS phrases simultaneously (backgrounded)
      return unless voice_enabled?

      lines = GERMAN_TIER4_LINES.sample(2)
      speak_background(lines[0]) if lines[0]
      speak_background(lines[1]) if lines[1]
    end

    # --- macOS Integration Helpers ---

    # Display a macOS notification via osascript.
    def display_notification(message:, title:, subtitle:, sound:)
      escaped_msg = escape_applescript(message)
      escaped_title = escape_applescript(title)
      escaped_subtitle = escape_applescript(subtitle)
      escaped_sound = escape_applescript(sound)

      script = "display notification \"#{escaped_msg}\" " \
               "with title \"#{escaped_title}\" " \
               "subtitle \"#{escaped_subtitle}\" " \
               "sound name \"#{escaped_sound}\""

      safe_system("osascript -e '#{escape_shell(script)}'")
    end

    # Play a system sound file.
    def play_sound(sound_key)
      path = SOUNDS[sound_key]
      return unless path && File.exist?(path)

      safe_system("afplay '#{path}' &")
    end

    # Speak text using macOS `say` command with configured voice and speed.
    def speak(text)
      voice = tts_voice
      speed = tts_speed
      escaped = escape_shell(text)
      safe_system("say -v '#{voice}' -r #{speed} '#{escaped}'")
    end

    # Speak text in the background (non-blocking).
    def speak_background(text)
      voice = tts_voice
      speed = tts_speed
      escaped = escape_shell(text)
      safe_system("say -v '#{voice}' -r #{speed} '#{escaped}' &")
    end

    # Set macOS output volume (0-100).
    def set_volume(level)
      level = [[level.to_i, 0].max, 100].min
      safe_system("osascript -e 'set volume output volume #{level}'")
    end

    # Open a URL in the default browser.
    def open_url(url)
      safe_system("open '#{escape_shell(url)}'")
    end

    # --- Config Helpers ---

    # Check if a tier is enabled in config.
    def tier_enabled?(tier_num)
      tc = tier_config(tier_num)
      tc.fetch('enabled', false)
    end

    # Get the config hash for a specific tier.
    def tier_config(tier_num)
      tiers = @config.fetch('tiers', {})
      tiers[tier_num] || tiers[tier_num.to_s] || {}
    end

    # Check if voice is enabled globally.
    def voice_enabled?
      voice_config = @config.fetch('voice', {})
      voice_config.fetch('enabled', false)
    end

    # Get the configured TTS voice name.
    def tts_voice
      voice_config = @config.fetch('voice', {})
      voice_config.fetch('tts_voice', 'Anna')
    end

    # Get the configured TTS speed.
    def tts_speed
      voice_config = @config.fetch('voice', {})
      voice_config.fetch('speed', 185).to_i
    end

    # --- Safety Helpers ---

    # Execute a system command safely. Never raises.
    def safe_system(cmd)
      system(cmd)
    rescue StandardError => e
      warn "[Kommandant::Notifier] Command failed: #{e.message}"
      nil
    end

    # Escape a string for use inside single-quoted shell arguments.
    def escape_shell(str)
      str.to_s.gsub("'", "'\\\\''")
    end

    # Escape a string for use inside double-quoted AppleScript strings.
    def escape_applescript(str)
      str.to_s.gsub('\\', '\\\\\\\\').gsub('"', '\\"')
    end
  end
end

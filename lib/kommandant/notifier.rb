# frozen_string_literal: true

module Kommandant
  # Delivers macOS notifications, sounds, and TTS based on tier level.
  # Pattern: Tink sound → German lines (Anna) → English translation (Daniel/Samantha)
  # Exception: Tier 3 = silent, just opens video fullscreen.
  # All system calls are wrapped in begin/rescue — never crashes.
  class Notifier
    # German lines paired with English translations.
    # Each tier picks N pairs (scaling up with severity).
    LINES = [
      { de: 'Achtung! Was machen Sie da?', en: 'Attention... What are you doing.' },
      { de: 'Zurück an die Arbeit, sofort!', en: 'Back to work. Immediately.' },
      { de: 'Das ist unakzeptabel!', en: 'This is... unacceptable.' },
      { de: 'Herr Kommandant ist nicht erfreut!', en: 'Herr Kommandant... is not pleased.' },
      { de: 'Sie sind eine Enttäuschung!', en: 'You are... a disappointment.' },
      { de: 'Disziplin! Haben Sie das vergessen?', en: 'Discipline. Have you forgotten that.' },
      { de: 'Ich beobachte Sie! Arbeiten Sie!', en: 'I am watching you. Get to work.' },
      { de: 'Schluss mit dem Unsinn!', en: 'Enough... with the nonsense.' },
      { de: 'Das ist Ihre letzte Warnung!', en: 'This is... your final warning.' },
      { de: 'Herr Kommandant verliert die Geduld!', en: 'Herr Kommandant... is losing patience.' },
      { de: 'Sie haben es so gewollt!', en: 'You... asked for this.' },
      { de: 'Die Konsequenzen sind unvermeidlich!', en: 'The consequences... are inevitable.' },
      { de: 'Drei Mal habe ich Sie gewarnt!', en: 'Three times... I have warned you.' },
      { de: 'Jetzt reicht es!', en: 'That... is enough.' },
      { de: 'ALARM! ALARM! TOTALER ARBEITSVERWEIGERUNG FESTGESTELLT!',
        en: 'ALARM. ALARM. Total work refusal... detected.' },
      { de: 'ACHTUNG! SOFORTIGE RÜCKKEHR ZUR ARBEIT!', en: 'ATTENTION. Immediate return... to work.' },
      { de: 'HERR KOMMANDANT HAT GENUG!', en: 'Herr Kommandant... has had enough.' },
      { de: 'DAS IST DER LETZTE BEFEHL!', en: 'This is... the final order.' }
    ].freeze

    # How many German+English line pairs per tier
    LINES_PER_TIER = { 1 => 1, 2 => 2, 3 => 0, 4 => 3 }.freeze

    PRAISE_LINES = [
      { de: 'Gut gemacht, Soldat!', en: 'Well done, soldier!' },
      { de: 'Sehr gut! So ist es richtig!', en: 'Very good! That is how it should be!' },
      { de: 'Ausgezeichnet! Weiter so!', en: 'Excellent! Keep it up!' },
      { de: 'Herr Kommandant ist zufrieden!', en: 'Herr Kommandant is satisfied!' },
      { de: 'Disziplin zahlt sich aus!', en: 'Discipline pays off!' }
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
      when 1 then notify_tier1(reason)
      when 2 then notify_tier2(reason)
      when 3 then notify_tier3
      when 4 then notify_tier4(reason)
      end
    end

    # Positive reinforcement when user gets back to work.
    #
    # @param rank [String] optional rank display
    # @param streak_minutes [Integer] how many minutes of focused work
    def praise(rank: nil, streak_minutes: 0) # rubocop:disable Lint/UnusedMethodArgument
      pair = PRAISE_LINES.sample
      message = praise_message(pair, streak_minutes)

      display_praise_notification(message)
      play_sound(:hero)
      speak_pair(pair) if voice_enabled?
    end

    private

    # --- Tier Implementations ---

    # Tier 1 (1 min): Tink → 1 German line → English translation
    def notify_tier1(reason)
      display_notification(
        message: reason,
        title: '🎖️ Herr Kommandant',
        subtitle: 'Gentle Reminder',
        sound: 'Tink'
      )
      play_sound(:submarine)

      return unless voice_enabled?

      pairs = LINES.sample(LINES_PER_TIER[1])
      speak_pairs(pairs)
    end

    # Tier 2 (5 min): Tink → 2 German lines → English translations
    def notify_tier2(reason)
      display_notification(
        message: reason,
        title: '🎖️ Herr Kommandant',
        subtitle: 'Stern Warning',
        sound: 'Tink'
      )
      play_sound(:submarine)

      return unless voice_enabled?

      pairs = LINES.sample(LINES_PER_TIER[2])
      speak_pairs(pairs)
    end

    # Tier 3 (10 min): NO sound, NO voice — just open video fullscreen
    def notify_tier3
      open_video_fullscreen(INTERVENTION_VIDEO)
    end

    # Tier 4 (25 min): Tink → 3 German lines → English translations → YouTube full volume in 4 quadrant windows
    def notify_tier4(reason)
      display_notification(
        message: reason,
        title: '🚨 HERR KOMMANDANT 🚨',
        subtitle: 'NUCLEAR OPTION ACTIVATED',
        sound: 'Tink'
      )
      play_sound(:submarine)
      change_volume(100)

      if voice_enabled?
        pairs = LINES.sample(LINES_PER_TIER[4])
        speak_pairs(pairs)
      end

      open_video_quadrants(INTERVENTION_VIDEO)
    end

    # --- Voice Helpers ---

    # Speak German+English pairs sequentially: German first (Anna), then English (Daniel/Samantha)
    def speak_pairs(pairs)
      pairs.each do |pair|
        speak_german(pair[:de])
        speak_english(pair[:en])
      end
    end

    def speak_pair(pair)
      speak_german(pair[:de])
      speak_english(pair[:en])
    end

    # Speak text with German voice (Anna by default)
    def speak_german(text)
      voice = tts_voice_german
      speed = tts_speed_german
      escaped = escape_shell(text)
      safe_system("say -v '#{voice}' -r #{speed} '#{escaped}'")
    end

    # Speak text with English voice (Daniel by default — British accent)
    def speak_english(text)
      voice = tts_voice_english
      speed = tts_speed_english
      escaped = escape_shell(text)
      safe_system("say -v '#{voice}' -r #{speed} '#{escaped}'")
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

    # Set macOS output volume (0-100).
    def change_volume(level)
      level = level.to_i.clamp(0, 100)
      safe_system("osascript -e 'set volume output volume #{level}'")
    end

    # Open a URL in the default browser.
    def open_url(url)
      safe_system("open '#{escape_shell(url)}'")
    end

    # Open a video URL in fullscreen using AppleScript to enter fullscreen mode.
    def open_video_fullscreen(url)
      open_url(url)
      # Give browser a moment to open the tab, then send Cmd+Shift+F for YouTube fullscreen
      sleep 2
      safe_system('osascript -e \'tell application "System Events" to keystroke "f"\'')
    end

    # Open video in 4 browser windows, one in each screen quadrant.
    # Uses AppleScript to position Chrome/Safari windows.
    def open_video_quadrants(url)
      script = build_quadrant_script(url)
      safe_system("osascript -e '#{escape_shell(script)}'")
    end

    def build_quadrant_script(url)
      escaped_url = escape_applescript(url)
      <<~APPLESCRIPT
        tell application "Finder"
          set screenBounds to bounds of window of desktop
          set screenWidth to item 3 of screenBounds
          set screenHeight to item 4 of screenBounds
        end tell

        set halfW to screenWidth div 2
        set halfH to screenHeight div 2

        tell application "Google Chrome"
          activate
          #{quadrant_window_script(escaped_url)}
        end tell
      APPLESCRIPT
    end

    def quadrant_window_script(url)
      positions = [
        '{0, 0, halfW, halfH}',
        '{halfW, 0, screenWidth, halfH}',
        '{0, halfH, halfW, screenHeight}',
        '{halfW, halfH, screenWidth, screenHeight}'
      ]
      positions.map.with_index(1) do |bounds, i|
        [
          "set win#{i} to make new window",
          "set URL of active tab of win#{i} to \"#{url}\"",
          "set bounds of win#{i} to #{bounds}"
        ].join("\n          ")
      end.join("\n          ")
    end

    def praise_message(pair, streak_minutes)
      streak_minutes.positive? ? "#{pair[:de]} (#{streak_minutes} min focused)" : pair[:de]
    end

    def display_praise_notification(message)
      display_notification(
        message: message,
        title: '🎖️ Herr Kommandant',
        subtitle: 'Impressive, Soldat!',
        sound: 'Hero'
      )
    end

    # --- Config Helpers ---

    # Check if a tier is enabled in config.
    def tier_enabled?(tier_num)
      tc = tier_config(tier_num)
      tc.fetch('enabled', tier_num <= 3)
    end

    # Get the config hash for a specific tier.
    def tier_config(tier_num)
      tiers = @config.fetch('tiers', {})
      tiers[tier_num] || tiers[tier_num.to_s] || {}
    end

    # Check if voice is enabled globally.
    def voice_enabled?
      voice_config = @config.fetch('voice', {})
      voice_config.fetch('enabled', true)
    end

    # German TTS voice (default: Anna)
    def tts_voice_german
      voice_config = @config.fetch('voice', {})
      voice_config.fetch('tts_voice', 'Anna')
    end

    # English TTS voice (default: Daniel — British accent)
    def tts_voice_english
      voice_config = @config.fetch('voice', {})
      voice_config.fetch('tts_voice_english', 'Daniel')
    end

    # Get the configured TTS speed for German voice.
    def tts_speed_german
      voice_config = @config.fetch('voice', {})
      voice_config.fetch('speed', 175).to_i
    end

    # Get the configured TTS speed for English voice (slower = more natural).
    def tts_speed_english
      voice_config = @config.fetch('voice', {})
      voice_config.fetch('speed_english', 140).to_i
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

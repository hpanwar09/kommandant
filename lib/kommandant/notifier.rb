# frozen_string_literal: true

module Kommandant
  # Delivers macOS notifications, sounds, and TTS based on tier level.
  # Escalation arc: passive-aggressive → formally disappointed → theatrical → meltdown.
  # All system calls are wrapped in begin/rescue — never crashes.
  class Notifier
    # --- Tier 1: Notification-only lines (passive-aggressive, dry) ---
    HINT_SUBTITLES = %w[Hmm. Notiert. Interesting. ...].freeze

    HINT_MESSAGES = [
      'I see you have chosen... leisure.',
      'This is not what we discussed in the briefing.',
      'I am choosing to believe this is research.',
      'Herr Kommandant sees all. Even this.',
      'Your productivity report will reflect this moment.'
    ].freeze

    # --- Tier 2: Formally disappointed (1 TTS pair) ---
    ADMONITION_LINES = [
      { de: 'Ich bin nicht wütend. Nur enttäuscht.', en: 'I am not angry. Just... disappointed.' },
      { de: 'Das Vaterland braucht Sie an der Tastatur.', en: 'The fatherland needs you... at the keyboard.' },
      { de: 'Haben Sie vergessen, wofür Sie bezahlt werden?',
        en: 'Have you forgotten... what you are paid for?' },
      { de: 'Ich habe alles gesehen. Alles.', en: 'I have seen everything. Everything.' },
      { de: 'Das steht jetzt in Ihrer Akte.', en: 'This is now... in your permanent file.' },
      { de: 'Fünf Minuten. Fünf lange Minuten.', en: 'Five minutes. Five... long... minutes.' }
    ].freeze

    # --- Tier 3: Theatrical dramatic (2 TTS pairs) ---
    REPRIMAND_LINES = [
      { de: 'Mein Gott, haben Sie keinen Stolz?!', en: 'My God... have you no pride?!' },
      { de: 'Ich schreibe das in Ihre Akte! Mit roter Tinte!',
        en: 'I am writing this in your file. In red ink.' },
      { de: 'Drei Generäle sind für weniger degradiert worden!',
        en: 'Three generals have been demoted... for less.' },
      { de: 'In dreißig Jahren Dienst habe ich so etwas nie gesehen.',
        en: 'In thirty years of service... I have never seen anything like this.' },
      { de: 'Sie testen meine Geduld. Und meine Geduld verliert.',
        en: 'You are testing my patience. And my patience... is losing.' },
      { de: 'Soll ich Ihren Bildschirm an die Geschäftsleitung weiterleiten?',
        en: 'Shall I forward your screen... to senior management?' },
      { de: 'Das ist eine Schande für die gesamte Abteilung!',
        en: 'This is a disgrace... to the entire department!' }
    ].freeze

    # --- Tier 4: Full meltdown (3 TTS pairs) ---
    INTERVENTION_LINES = [
      { de: 'ACHTUNG! Dies ist keine Übung!', en: 'ATTENTION. This... is not a drill.' },
      { de: 'Sie zwingen mich zu drastischen Maßnahmen!',
        en: 'You are forcing me... to take drastic measures.' },
      { de: 'Herr Kommandant hat alles versucht. ALLES!',
        en: 'Herr Kommandant has tried everything. EVERYTHING.' },
      { de: 'Rufen Sie meine Mutter an. Sagen Sie ihr, ich habe versagt.',
        en: 'Call my mother. Tell her... I have failed.' },
      { de: 'Zwanzig Minuten! Das ist ein Kriegsverbrechen!',
        en: 'Twenty minutes! This is... a war crime.' },
      { de: 'Ich kündige! Nein, warten Sie. SIE kündigen!',
        en: 'I quit! No wait. YOU quit!' },
      { de: 'Das ist der dunkelste Tag meiner Karriere!',
        en: 'This is the darkest day... of my career.' },
      { de: 'Ich werde das dem Tribunal melden!',
        en: 'I will be reporting this... to the tribunal.' }
    ].freeze

    # --- Praise lines (notification only, no TTS) ---
    PRAISE_LINES = [
      'Endlich! I had given up hope.',
      'Good. Very good. You may continue to live.',
      'Herr Kommandant is... cautiously optimistic.',
      'A miracle! Write down the date!',
      'Acceptable. Barely... acceptable.',
      'Welcome back, soldier. I was... concerned.'
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

    # How many German+English TTS pairs per tier
    LINES_PER_TIER = { 1 => 0, 2 => 1, 3 => 2, 4 => 3 }.freeze

    # Volume bump for tier 4 (firm, not obnoxious)
    INTERVENTION_VOLUME = 75

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
      when 3 then notify_tier3(reason)
      when 4 then notify_tier4(reason)
      end
    end

    # Positive reinforcement when user gets back to work.
    # Notification only — no sound, no voice.
    #
    # @param rank [String] optional rank display
    # @param streak_minutes [Integer] how many minutes of focused work
    def praise(rank: nil, streak_minutes: 0) # rubocop:disable Lint/UnusedMethodArgument
      message = PRAISE_LINES.sample
      message = "#{message} (#{streak_minutes} min focused)" if streak_minutes.positive?

      display_notification(
        message: message,
        title: '🎖️ Herr Kommandant',
        subtitle: 'Gut.',
        sound: 'default'
      )
    end

    private

    # --- Tier Implementations ---

    # Tier 1 (2 min): Notification only — no sound, no voice.
    # Passive-aggressive nudge. Easily dismissed.
    def notify_tier1(reason)
      subtitle = HINT_SUBTITLES.sample
      hint = HINT_MESSAGES.sample

      display_notification(
        message: "#{hint} (#{reason})",
        title: '🎖️ Herr Kommandant',
        subtitle: subtitle,
        sound: 'default'
      )
    end

    # Tier 2 (5 min): Tink sound + 1 German/English TTS pair.
    # Formally disappointed — a stern headmaster.
    def notify_tier2(reason)
      display_notification(
        message: reason,
        title: '🎖️ Herr Kommandant',
        subtitle: 'Formelle Ermahnung',
        sound: 'Tink'
      )
      play_sound(:tink)

      return unless voice_enabled?

      pairs = ADMONITION_LINES.sample(LINES_PER_TIER[2])
      speak_pairs(pairs)
    end

    # Tier 3 (12 min): Submarine sound + 2 German/English TTS pairs.
    # Theatrically dramatic — performing outrage.
    def notify_tier3(reason)
      display_notification(
        message: reason,
        title: '🎖️ Herr Kommandant',
        subtitle: 'UNAKZEPTABEL',
        sound: 'Submarine'
      )
      play_sound(:submarine)

      return unless voice_enabled?

      pairs = REPRIMAND_LINES.sample(LINES_PER_TIER[3])
      speak_pairs(pairs)
    end

    # Tier 4 (20 min): Basso + volume bump + 3 TTS pairs + motivational video.
    # Full theatrical meltdown — devastated, betrayed.
    def notify_tier4(reason)
      display_notification(
        message: reason,
        title: '🚨 HERR KOMMANDANT 🚨',
        subtitle: 'DEFCON EINS',
        sound: 'Basso'
      )
      play_sound(:basso)
      change_volume(INTERVENTION_VOLUME)

      if voice_enabled?
        pairs = INTERVENTION_LINES.sample(LINES_PER_TIER[4])
        speak_pairs(pairs)
      end

      open_video(INTERVENTION_VIDEO)
    end

    # --- Voice Helpers ---

    # Speak German+English pairs sequentially: German first (Anna), then English (Daniel)
    def speak_pairs(pairs)
      pairs.each do |pair|
        speak_german(pair[:de])
        sleep(2)
        speak_english(pair[:en])
      end
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

    # Open a video URL in the default browser from the beginning.
    def open_video(url)
      fullscreen_url = ensure_video_params(url)
      safe_system("open '#{escape_shell(fullscreen_url)}'")
    end

    # Ensure YouTube URL has autoplay=1 and start=0 params.
    def ensure_video_params(url)
      separator = url.include?('?') ? '&' : '?'
      "#{url}#{separator}autoplay=1&start=0"
    end

    # --- Config Helpers ---

    # Check if a tier is enabled in config.
    def tier_enabled?(tier_num)
      tc = tier_config(tier_num)
      tc.fetch('enabled', true)
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

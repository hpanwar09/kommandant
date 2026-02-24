# frozen_string_literal: true

require 'pastel'
require 'tty-box'
require 'tty-cursor'
require 'artii'

module Kommandant
  # Terminal display module with ASCII art and colored output.
  # Used by CLI and watcher to render banners, tier messages,
  # daily reports, and status summaries.
  module Display
    FACE_DISAPPROVAL = 'ಠ_ಠ'
    FACE_ANGRY       = '(ಠ益ಠ)'
    FACE_RAGE        = 'ლ(ಠ益ಠლ)'
    FACE_FLIP        = '(╯°□°）╯︵ ┻━┻'
    FACE_SALUTE      = 'o7'
    FACE_SKULL       = '☠'

    SKULL_ART = <<~ART
         ______
       /      \\
      |  X  X  |
      |   <>   |
       \\ ---- /
        ------
    ART

    DIVIDER = '═' * 42

    class << self
      # Print startup banner — KOMMANDANT in figlet + tagline
      def banner
        art = artii_font.asciify('KOMMANDANT')
        puts pastel.red(art)
        puts pastel.yellow('  Herr Kommandant is watching. Jawohl!')
        puts
      end

      # Print tier-appropriate terminal message
      # @param tier [Integer] 0–4
      # @param reason [String] why the alert triggered
      # @param rank [String] current military rank
      # @param streak [Integer] current focus streak in minutes
      def tier_message(tier:, reason:, rank:, streak:)
        case tier
        when 0
          # Tier 0: silent — no output
          nil
        when 1
          tier_1_message(reason: reason, rank: rank, streak: streak)
        when 2
          tier_2_message(reason: reason, rank: rank, streak: streak)
        when 3
          tier_3_message(reason: reason, rank: rank)
        when 4
          tier_4_message(reason: reason, rank: rank, streak: streak)
        end
      end

      # Print daily Tagesbericht
      # @param stats [Hash] { focus_minutes:, slack_minutes:, rank:, violations:, worst_offense: }
      def report(stats)
        total = (stats[:focus_minutes] || 0) + (stats[:slack_minutes] || 0)
        focus_pct = total.positive? ? ((stats[:focus_minutes].to_f / total) * 100).round : 0
        slack_pct = 100 - focus_pct

        focus_bar = progress_bar(focus_pct)
        slack_bar = progress_bar(slack_pct)

        focus_str = format_duration(stats[:focus_minutes] || 0)
        slack_str = format_duration(stats[:slack_minutes] || 0)

        violations_str = format_violations(stats[:violations] || [])
        worst_str = format_worst_offense(stats[:worst_offense])
        verdict = compute_verdict(focus_pct)
        date_str = Time.now.strftime('%b %d, %Y')

        output = <<~REPORT
          #{DIVIDER}
            📋 TAGESBERICHT — #{date_str}
            Herr Kommandant's Daily Assessment
          #{DIVIDER}
            Focus Time:    #{focus_str.ljust(8)} #{focus_bar} #{focus_pct}%
            Slack Time:    #{slack_str.ljust(8)} #{slack_bar} #{slack_pct}%
            Rank:          #{stats[:rank] || 'Rekrut'}
            Violations:    #{violations_str}
            Worst Offense: #{worst_str}

            Verdict: #{verdict}
          #{DIVIDER}
        REPORT

        puts pastel.green(output)
      end

      # Print current status (rank, streak, patrol status)
      # @param data [Hash] { rank:, streak_minutes:, patrol_active:, tier:, total_focus:, total_slack: }
      def status(data)
        patrol = data[:patrol_active] ? pastel.green('ACTIVE') : pastel.red('INACTIVE')
        tier_color = tier_color_for(data[:tier] || 0)
        tier_name = Tier.info(data[:tier] || 0)[:name]

        lines = [
          "#{FACE_SALUTE} Kommandant Status",
          '─' * 30,
          "  Rank:          #{data[:rank] || 'Rekrut'}",
          "  Focus Streak:  #{data[:streak_minutes] || 0} min",
          "  Patrol:        #{patrol}",
          "  Current Tier:  #{pastel.decorate(tier_name, tier_color)}",
          "  Focus Today:   #{format_duration(data[:total_focus] || 0)}",
          "  Slack Today:   #{format_duration(data[:total_slack] || 0)}",
          '─' * 30
        ]

        puts lines.join("\n")
      end

      private

      def pastel
        @pastel ||= Pastel.new
      end

      def artii_font
        @artii_font ||= Artii::Base.new(font: 'slant')
      end

      def tier_1_message(reason:, rank:, streak:)
        content = [
          "  #{FACE_DISAPPROVAL}  Herr Kommandant is disappointed.",
          '',
          "  Reason: #{reason}",
          "  Rank:   #{rank}",
          "  Streak: #{streak} min (broken!)",
          '',
          '  Get back to work, soldier.'
        ].join("\n")

        box = TTY::Box.frame(
          width: 50,
          border: :light,
          padding: [1, 2],
          title: { top_left: ' Tier 1: Gentle Nudge ' }
        ) { content }

        puts pastel.yellow(box)
      end

      def tier_2_message(reason:, rank:, streak:)
        content = [
          "  #{FACE_ANGRY}  Herr Kommandant is ANGRY!",
          '',
          "  Reason: #{reason}",
          "  Rank:   #{rank}",
          "  Streak: #{streak} min (DESTROYED!)",
          '',
          '  ⚠️  DEMOTION WARNING  ⚠️',
          '  One more strike and you lose rank!'
        ].join("\n")

        box = TTY::Box.frame(
          width: 50,
          border: :thick,
          padding: [1, 2],
          title: { top_left: ' Tier 2: Stern Warning ' }
        ) { content }

        puts pastel.red(box)
      end

      def tier_3_message(reason:, rank:)
        achtung = artii_font.asciify('ACHTUNG!')

        content = [
          "  #{FACE_RAGE}  #{FACE_SKULL}  FULL INTERVENTION  #{FACE_SKULL}",
          '',
          "  Reason: #{reason}",
          "  Rank:   #{rank} → DEMOTED!",
          '',
          '  RANK DEMOTED. You have shamed yourself.',
          '  Herr Kommandant is furious!'
        ].join("\n")

        box = TTY::Box.frame(
          width: 55,
          border: :thick,
          padding: [1, 2],
          title: { top_left: ' Tier 3: FULL INTERVENTION ' }
        ) { content }

        puts pastel.red(achtung)
        puts pastel.red(box)
      end

      def tier_4_message(reason:, rank:, streak:)
        cursor = TTY::Cursor
        print cursor.clear_screen
        print cursor.move_to(0, 0)

        deserter = artii_font.asciify('DESERTER')

        lines = [
          pastel.on_red(pastel.white(pastel.bold(deserter))),
          '',
          pastel.on_red(pastel.white("  #{FACE_SKULL}  #{FACE_SKULL}  #{FACE_SKULL}  NUCLEAR OPTION ACTIVATED  #{FACE_SKULL}  #{FACE_SKULL}  #{FACE_SKULL}")),
          '',
          pastel.on_red(pastel.white(SKULL_ART)),
          '',
          pastel.on_red(pastel.white("  Reason:     #{reason}")),
          pastel.on_red(pastel.white("  Rank:       #{rank} → STRIPPED!")),
          pastel.on_red(pastel.white("  Streak:     #{streak} min (OBLITERATED)")),
          '',
          pastel.on_red(pastel.white(pastel.bold("  #{FACE_FLIP}"))),
          pastel.on_red(pastel.white('  You have been declared a DESERTER.')),
          pastel.on_red(pastel.white('  Herr Kommandant has given up on you.')),
          ''
        ]

        puts lines.join("\n")
      end

      # Build a 10-char progress bar from a percentage
      def progress_bar(pct)
        filled = [(pct / 10.0).round, 10].min
        empty = 10 - filled
        '█' * filled + '░' * empty
      end

      # Format minutes into "Xh Ym" string
      def format_duration(minutes)
        minutes = minutes.to_i
        h = minutes / 60
        m = minutes % 60
        if h.positive?
          "#{h}h #{m.to_s.rjust(2, '0')}m"
        else
          "#{m}m"
        end
      end

      # Summarize violations array into "3x Reddit, 2x YouTube" format
      def format_violations(violations)
        return 'None — exemplary!' if violations.empty?

        counts = Hash.new(0)
        violations.each { |v| counts[v[:app] || v['app'] || 'unknown'] += 1 }
        counts.map { |app, count| "#{count}x #{app}" }.join(', ')
      end

      # Format worst offense
      def format_worst_offense(offense)
        return 'None' if offense.nil?

        app = offense[:app] || offense['app'] || 'unknown'
        dur = offense[:duration_seconds] || offense['duration_seconds'] || 0
        mins = (dur / 60.0).ceil
        "#{mins}min on #{app}"
      end

      # Compute a verdict string from focus percentage
      def compute_verdict(focus_pct)
        case focus_pct
        when 90..100
          "OUTSTANDING! Herr Kommandant salutes you. #{FACE_SALUTE}"
        when 75..89
          'ACCEPTABLE. Carry on, soldier.'
        when 50..74
          'MEDIOCRE. You can do better, soldier.'
        when 25..49
          "POOR. Herr Kommandant is displeased. #{FACE_DISAPPROVAL}"
        else
          "DISGRACEFUL. Report for punishment. #{FACE_ANGRY}"
        end
      end

      # Map tier number to a Pastel color symbol
      def tier_color_for(tier)
        case tier
        when 0 then :white
        when 1 then :yellow
        when 2 then :bright_yellow
        when 3 then :red
        when 4 then :bright_red
        else :white
        end
      end
    end
  end
end

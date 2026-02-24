# frozen_string_literal: true

module Kommandant
  # Detects user activity on macOS via shell commands.
  # All methods are safe — they never raise and always return sensible defaults.
  class Detector
    MEETING_APPS = [
      'zoom.us',
      'FaceTime',
      'Microsoft Teams',
      'Google Meet',
      'Webex',
      'Slack Huddle',
      'Around'
    ].freeze

    CHROME_URL_SCRIPT = <<~APPLESCRIPT
      tell application "Google Chrome"
        get URL of active tab of front window
      end tell
    APPLESCRIPT

    CHROME_TITLE_SCRIPT = <<~APPLESCRIPT
      tell application "Google Chrome"
        get title of active tab of front window
      end tell
    APPLESCRIPT

    SAFARI_URL_SCRIPT = <<~APPLESCRIPT
      tell application "Safari"
        get URL of front document
      end tell
    APPLESCRIPT

    SAFARI_TITLE_SCRIPT = <<~APPLESCRIPT
      tell application "Safari"
        get name of front document
      end tell
    APPLESCRIPT

    BRAVE_URL_SCRIPT = <<~APPLESCRIPT
      tell application "Brave Browser"
        get URL of active tab of front window
      end tell
    APPLESCRIPT

    BRAVE_TITLE_SCRIPT = <<~APPLESCRIPT
      tell application "Brave Browser"
        get title of active tab of front window
      end tell
    APPLESCRIPT

    ARC_URL_SCRIPT = <<~APPLESCRIPT
      tell application "Arc"
        get URL of active tab of front window
      end tell
    APPLESCRIPT

    ARC_TITLE_SCRIPT = <<~APPLESCRIPT
      tell application "Arc"
        get title of active tab of front window
      end tell
    APPLESCRIPT

    BROWSER_APPS = {
      'Google Chrome' => { url: CHROME_URL_SCRIPT, title: CHROME_TITLE_SCRIPT },
      'Safari' => { url: SAFARI_URL_SCRIPT, title: SAFARI_TITLE_SCRIPT },
      'Brave Browser' => { url: BRAVE_URL_SCRIPT, title: BRAVE_TITLE_SCRIPT },
      'Arc' => { url: ARC_URL_SCRIPT, title: ARC_TITLE_SCRIPT }
    }.freeze

    # Returns seconds since last user input (keyboard/mouse/trackpad).
    # Uses IOKit HIDIdleTime in nanoseconds, converts to seconds.
    def idle_seconds
      output = safe_exec('ioreg -c IOHIDSystem | grep HIDIdleTime')
      return 0 if output.nil? || output.empty?

      # HIDIdleTime line looks like: "HIDIdleTime" = 1234567890
      match = output.match(/HIDIdleTime.*?=\s*(\d+)/)
      return 0 unless match

      nanoseconds = match[1].to_i
      (nanoseconds / 1_000_000_000.0).to_i
    end

    # Returns the name of the frontmost application.
    # Uses lsappinfo which requires no special permissions.
    def frontmost_app
      # lsappinfo front returns the ASN of the frontmost app
      front_asn = safe_exec('lsappinfo front')
      return 'unknown' if front_asn.nil? || front_asn.empty? || front_asn.include?('not found')

      # lsappinfo info -only name <ASN> returns: "name"="AppName"
      info = safe_exec("lsappinfo info -only name #{front_asn}")
      return 'unknown' if info.nil? || info.empty?

      # Parse the name from output like: "CFBundleName"="Google Chrome"
      match = info.match(/"?(?:CFBundle)?[Nn]ame"?\s*=\s*"?([^"]+)"?/)
      return 'unknown' unless match

      match[1].strip
    end

    # Returns the URL of the active browser tab, or nil if unavailable.
    # Tries Chrome → Safari → Brave → Arc in order.
    def browser_url
      app = frontmost_app
      scripts = browser_scripts_for(app)

      if scripts
        result = run_applescript(scripts[:url])
        return result unless result.nil? || result.empty?
      end

      # If frontmost isn't a known browser, try each
      BROWSER_APPS.each do |browser_name, browser_scripts|
        next if browser_name == app # Already tried
        next unless app_running?(browser_name)

        result = run_applescript(browser_scripts[:url])
        return result unless result.nil? || result.empty?
      end

      nil
    end

    # Returns the title of the active browser tab, or nil if unavailable.
    def browser_title
      app = frontmost_app
      scripts = browser_scripts_for(app)

      if scripts
        result = run_applescript(scripts[:title])
        return result unless result.nil? || result.empty?
      end

      BROWSER_APPS.each do |browser_name, browser_scripts|
        next if browser_name == app
        next unless app_running?(browser_name)

        result = run_applescript(browser_scripts[:title])
        return result unless result.nil? || result.empty?
      end

      nil
    end

    # Returns true if the screen is locked.
    # Checks if loginwindow is frontmost or CGSession reports locked.
    def screen_locked?
      app = frontmost_app
      return true if app == 'loginwindow'

      # Check via CGSession
      session_info = safe_exec(
        'python3 -c "import Quartz; print(Quartz.CGSessionCopyCurrentDictionary())" 2>/dev/null'
      )
      if session_info
        return true if session_info.include?('CGSSessionScreenIsLocked = 1')
        return true if session_info.include?("'CGSSessionScreenIsLocked': True")
      end

      # Fallback: check if screen saver is running
      screensaver = safe_exec('pgrep -x ScreenSaverEngine')
      return true if screensaver && !screensaver.empty?

      false
    end

    # Returns true if the user appears to be in a video/voice meeting.
    def in_meeting?
      app = frontmost_app
      MEETING_APPS.any? { |meeting_app| app.downcase.include?(meeting_app.downcase) }
    end

    # Returns a snapshot hash of all detection data at once.
    def snapshot
      app = frontmost_app
      {
        idle_seconds: idle_seconds,
        app: app,
        url: browser_url,
        title: browser_title,
        locked: screen_locked?,
        meeting: in_meeting?
      }
    end

    private

    # Execute a shell command safely, returning stripped output or nil on failure.
    def safe_exec(cmd)
      output = `#{cmd} 2>/dev/null`.strip
      $CHILD_STATUS&.success? ? output : nil
    rescue StandardError
      nil
    end

    # Run an AppleScript snippet and return the result, or nil on failure.
    def run_applescript(script)
      escaped = script.gsub("'", "'\\''")
      output = safe_exec("osascript -e '#{escaped}'")
      return nil if output.nil? || output.empty? || output.include?('missing value')

      output
    end

    # Check if a given application is currently running.
    def app_running?(app_name)
      result = safe_exec("pgrep -f '#{app_name}'")
      result && !result.empty?
    end

    # Look up AppleScript templates for the given app name.
    def browser_scripts_for(app_name)
      BROWSER_APPS.each do |browser_name, scripts|
        return scripts if app_name.downcase.include?(browser_name.downcase) ||
                          browser_name.downcase.include?(app_name.downcase)
      end
      nil
    end
  end
end

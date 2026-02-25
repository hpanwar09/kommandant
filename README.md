# Kommandant

A productivity enforcement CLI for macOS. Herr Kommandant monitors your activity and delivers escalating German-accented warnings when you slack off.

## Requirements

- macOS (uses `say`, `osascript`, `afplay`)
- Ruby >= 3.2

## Install

```bash
gem install kommandant
```

Or from source:

```bash
git clone https://github.com/hpanwar09/kommandant.git
cd kommandant
bundle install
```

## Usage

```bash
kommandant start              # Start patrol
kommandant stop               # Stop patrol
kommandant status             # Show rank, streak, patrol status
kommandant suppress 30m       # Suppress for 30 min
kommandant test all           # Test all tiers
kommandant test 3             # Test a specific tier (1-4, praise)
```

### Modes

```bash
kommandant start --strict     # All tiers, no mercy
kommandant start --chill      # Tier 1-2 only, no voice
kommandant start --silent     # Monitor only, no interruptions
```

## Tiers

| Tier | Name | Triggers after | What happens |
|------|------|---------------|--------------|
| 1 | Der Hinweis | 2 min | Notification only |
| 2 | Die Ermahnung | 5 min | Sound + 1 German/English voice line |
| 3 | Der Verweis | 12 min | Sound + 2 voice lines |
| 4 | Die Intervention | 20 min | Sound + 3 voice lines + video |

Get back to work and Herr Kommandant will acknowledge your return. Keep slacking and he escalates.

## Config

Config lives at `~/.kommandant.yml`. Manage it with:

```bash
kommandant config list
kommandant config set --key voice.enabled --value false
kommandant config reset
```

Configurable: blocked/allowed apps and URLs, tier thresholds, voice settings, active hours, active days.

## License

MIT

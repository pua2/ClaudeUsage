# ClaudeUsage

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black.svg)]()

A lightweight macOS menu bar app that tracks your [Claude Code](https://docs.anthropic.com/en/docs/claude-code) usage — plan limits, session stats, token counts, and model breakdown — all in one glance.

## Features

### Menu Bar — Concentric Rings
- **Outer ring** — weekly usage, **inner ring** — current session usage
- Color-coded: green (<50%), yellow (<75%), orange (<90%), red (>=90%)
- Compact stacked time: session reset on top, weekly reset below (e.g. `2h` / `3d`)

### Plan Usage Limits
- **Session limit** — 5-hour window utilization with countdown to reset
- **Weekly limit** — 7-day utilization with reset date and time remaining
- Color-coded progress bars

### Usage Stats
- **Today** and **Last 7 Days** — responses, tool calls, sessions, output/input/cache tokens
- **Model breakdown** — expand weekly to see per-model usage (Sonnet, Opus, Haiku, etc.) with proportion bars
- **Auto-detected models** — any new Claude model family appears automatically
- **Bar chart** — responses per day for the last 7 days

### Settings
- **Auto Check for Updates** — silently checks GitHub once a day; prompts when an update is available
- **Check for Updates** — manually pull, rebuild, and restart in one click
- **Copy Debug Info** for troubleshooting
- **Refresh** on demand (also auto-refreshes every 60 seconds)

## How It Works

ClaudeUsage reads data from two sources, entirely on your machine:

1. **Local JSONL files** (`~/.claude/projects/`) — Claude Code writes conversation logs here. The app parses assistant messages to count responses, tool calls, tokens, and sessions, with automatic per-model tracking.

2. **Claude.ai usage API** — The app reads your Claude Desktop session cookie from the macOS Keychain and local cookie database, then fetches your plan utilization from `claude.ai/api/.../usage` using a WKWebView (to handle Cloudflare). No credentials are stored or transmitted anywhere else.

All data stays local. Nothing is sent to any third-party service.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools (`xcode-select --install`)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- [Claude Desktop](https://claude.ai/download) app (for plan usage limits)

## Install

```bash
git clone https://github.com/pua2/ClaudeUsage.git
cd ClaudeUsage
make install
```

This builds a release binary, signs it, packages it as `ClaudeUsage.app`, and installs it to `/Applications`.

On first launch, macOS will ask for Keychain access to read the Claude Desktop cookie — click **Always Allow** so it doesn't ask again.

**Or build and run without installing:**

```bash
make run
```

## Usage

Click the concentric rings in the menu bar to open the dashboard.

| Action | How |
|---|---|
| View dashboard | Click the rings in the menu bar |
| Refresh stats | Settings gear > Refresh |
| Copy debug info | Settings gear > Copy Debug Info |
| See model breakdown | Click the chevron next to Weekly |
| Check for updates | Settings gear > Check for Updates |
| Quit | Settings gear > Quit |

## Update

ClaudeUsage checks for updates automatically once a day (toggle in settings gear). You can also update manually:

**From the app:** Settings gear > Check for Updates > Install Now

**From the terminal:**
```bash
cd ClaudeUsage
git pull origin main
make install
```

## Architecture

```
ClaudeUsage/
├── Sources/ClaudeUsage/
│   ├── main.swift          # App entry point
│   ├── AppDelegate.swift   # Menu bar rings, popup panel, refresh timer
│   ├── StatsModel.swift    # JSONL parsing, per-model aggregation, updates
│   ├── ClaudeAuth.swift    # Keychain + cookie decryption, usage API fetch
│   └── MenuBarView.swift   # SwiftUI dashboard (limits, stats, chart)
├── Resources/
│   ├── AppIcon.icns        # App icon
│   └── Info.plist          # App bundle metadata
├── Package.swift           # Swift Package Manager config
├── Makefile                # build / install / run / clean
└── .github/workflows/ci.yml
```

## Privacy

ClaudeUsage runs entirely on your machine:

- **No network calls** except to `claude.ai` to fetch your own usage data
- **No telemetry, analytics, or tracking**
- **No credentials stored** — reads your existing Claude Desktop cookie from the macOS Keychain at runtime
- Cookie decryption uses the same Chromium-standard method (PBKDF2-SHA1 + AES-128-CBC) that any local Chromium-based app uses

## Uninstall

```bash
rm -rf /Applications/ClaudeUsage.app
```

## License

[MIT](LICENSE)

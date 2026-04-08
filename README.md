# ClaudeUsage

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black.svg)]()

A lightweight macOS menu bar app that tracks your [Claude Code](https://docs.anthropic.com/en/docs/claude-code) usage — plan limits, session stats, token counts, and model breakdown — all in one glance.

## Features

### Plan Usage Limits
- **Session limit** — current 5-hour window utilization with countdown to reset
- **Weekly limit** — 7-day utilization with reset date and time remaining
- Color-coded progress bars (green → yellow → orange → red)

### Usage Stats
- **Today** and **Last 7 Days** — responses, tool calls, sessions, output tokens
- **Model breakdown** — expand the weekly section to see Sonnet vs Opus usage (messages and tokens)
- **Bar chart** — responses per day for the last 7 days

### Menu Bar
- Live percentage in the menu bar (session % when active, weekly % otherwise)
- **Refresh** on demand or automatically every 60 seconds
- **Copy Debug Info** for troubleshooting
- **Quit** from the settings gear menu

## How It Works

ClaudeUsage reads data from two sources, entirely on your machine:

1. **Local JSONL files** (`~/.claude/projects/`) — Claude Code writes conversation logs here. The app parses assistant messages to count responses, tool calls, tokens, and sessions, with per-model tracking (Sonnet/Opus).

2. **Claude.ai usage API** — The app reads your Claude Desktop session cookie from the macOS Keychain and local cookie database, then fetches your plan utilization from `claude.ai/api/.../usage` using a WKWebView (to handle Cloudflare). No credentials are stored or transmitted anywhere else.

All data stays local. Nothing is sent to any third-party service.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+ (comes with Xcode or Xcode Command Line Tools)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- [Claude Desktop](https://claude.ai/download) app (for plan usage limits)

## Install

```bash
git clone https://github.com/pua2/ClaudeUsage.git
cd ClaudeUsage
make install
```

This builds a release binary, packages it as `ClaudeUsage.app`, and copies it to `/Applications`.

**Or build and run without installing:**

```bash
make run
```

## Usage

Launch the app — a percentage appears in your menu bar. Click it to see the full dashboard.

| Action | How |
|---|---|
| View dashboard | Click the menu bar percentage |
| Refresh stats | Settings gear → Refresh |
| Copy debug info | Settings gear → Copy Debug Info |
| See model breakdown | Click ▶ next to Weekly |
| Quit | Settings gear → Quit |

## Architecture

```
ClaudeUsage/
├── Sources/ClaudeUsage/
│   ├── main.swift          # App entry point
│   ├── AppDelegate.swift   # Menu bar icon, popup panel, refresh timer
│   ├── StatsModel.swift    # JSONL parsing, per-day/per-model aggregation
│   ├── ClaudeAuth.swift    # Keychain + cookie decryption, usage API fetch
│   └── MenuBarView.swift   # SwiftUI dashboard (limits, stats, chart)
├── Resources/
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

## Update

```bash
cd ClaudeUsage
git pull origin main
make install
```

## Uninstall

```bash
rm -rf /Applications/ClaudeUsage.app
```

## License

[MIT](LICENSE)

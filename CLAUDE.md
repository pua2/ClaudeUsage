# ClaudeUsage — Developer Guide

Inherits all global rules from `/Users/pavanamin/Documents/git/CLAUDE.md`.

## What This Is

A macOS menu bar app that tracks Claude Code usage — plan limits, session stats, token counts, and per-model breakdown. Reads two local sources: JSONL conversation logs in `~/.claude/projects/`, and the user's `claude.ai` plan-usage API (via WKWebView with the local Keychain cookie). All data stays on-device.

- **Platform:** macOS 14+ (Sonoma) | **Stack:** Swift 5.9 + AppKit + WebKit + Swift Package Manager | **Mode:** Menu bar accessory app

## Architecture

```
main.swift → AppDelegate (NSApplicationDelegate, .accessory mode)
├── NSStatusItem
│   └── MenuBarView                          ← concentric ring icon (session + weekly)
├── InsightsView (NSPopover)                 ← stats UI: rings, bars, model breakdown
├── StatsModel (singleton, ObservableObject) ← parses JSONL, fetches plan API, caches
└── ClaudeAuth                                ← reads Claude Desktop cookie from Keychain + cookie DB
                                                drives WKWebView to fetch claude.ai usage API
```

**Key rules:**
- App runs as `.accessory` (menu bar only) — never `.regular`
- All data stays local — never POST to external services
- Cookie reads must handle "Keychain access denied" gracefully — show a clear error in the UI
- WKWebView is required (not `URLSession`) because Cloudflare blocks plain requests
- Auto-refresh every 60s; on-demand refresh via menu

## File Map

| File | Responsibility |
|---|---|
| `Sources/ClaudeUsage/main.swift` | Entry point, `NSApplication` bootstrap |
| `Sources/ClaudeUsage/AppDelegate.swift` | App lifecycle, `NSStatusItem`, popover, refresh timer, updates |
| `Sources/ClaudeUsage/MenuBarView.swift` | Concentric-ring icon rendering (session + weekly utilization) |
| `Sources/ClaudeUsage/InsightsView.swift` | Popover UI — plan limits, today/week stats, model breakdown, bar chart |
| `Sources/ClaudeUsage/StatsModel.swift` | `ObservableObject` — JSONL parsing, plan fetch, per-model aggregation, cache |
| `Sources/ClaudeUsage/ClaudeAuth.swift` | Reads Claude Desktop session cookie from Keychain + cookie DB, drives WKWebView |
| **Build / install:** | |
| `Package.swift` | Swift Package Manager manifest |
| `Makefile` | `make install` → release build, sign, package as `.app`, install to `/Applications` |
| `Resources/` | App icon, Info.plist additions |

## Build

`make install` builds release, signs (Lumaru team if available), packages as `ClaudeUsage.app`, installs to `/Applications`. No CI — local builds are the only gate.

## Test Suite Structure

No test target yet. When added: prioritize `StatsModel` JSONL parsing and per-model aggregation (pure Swift, no AppKit).

## Bug Fixer Notes

- Rings show wrong percentage → `StatsModel` parsing or plan API fetch in `ClaudeAuth`
- "Keychain access denied" → `ClaudeAuth` cookie read; user must click "Always Allow" once
- Plan API returns Cloudflare challenge → WKWebView setup in `ClaudeAuth` (must use real browser context)
- Per-model breakdown wrong → aggregation logic in `StatsModel` — confirm model name detection handles new families
- Bar chart empty → JSONL parser not finding files in `~/.claude/projects/` (path or permissions)
- Refresh hangs → timer + async race in `AppDelegate` / `StatsModel`

## iOS Reviewer Focus

- All disk I/O off main thread (JSONL files can be large)
- WKWebView lifecycle — release after fetch to avoid memory growth
- Keychain access errors handled visibly, never silently swallowed
- `@Published` updates marshaled to main thread before UI reads

## Agents

Use the universal agents from root: `bug-fixer`, `ios-reviewer`, `testing` (when tests exist), `doc-updater`, `performance`.

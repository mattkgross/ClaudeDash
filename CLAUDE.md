# ClaudeDash

## Project Overview
macOS menu bar app (SwiftUI, macOS 14+) that displays Claude Code API usage. Lives in the menu bar, shows session usage percentage as the icon label, opens a popover with all three usage buckets when clicked.

## Architecture
- **ClaudeDashApp.swift** — `@main` entry point, `MenuBarExtra` scene with `.window` style
- **UsageView.swift** — Popover UI with three `UsageRow` components, footer with launch-at-login and quit
- **UsageService.swift** — `@Observable` class handling keychain token reading, API polling (60s interval), error states
- **Models.swift** — `UsageResponse` / `UsageBucket` Codable types with computed properties for percentage, color tier, gradient, and formatted reset time

## Data Source
- OAuth token read from macOS Keychain: `security find-generic-password -s "Claude Code-credentials" -w`
- Token path in JSON: `claudeAiOauth.accessToken`
- API endpoint: `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer {token}` and `anthropic-beta: oauth-2025-04-20`
- API returns utilization as a percentage (e.g., `29.0` = 29%), NOT as a 0–1 fraction

## Build
```
xcodebuild -project ClaudeDash.xcodeproj -scheme ClaudeDash -configuration Debug build
```

## Key Decisions
- `LSUIElement = true` in Info.plist hides the dock icon
- App Sandbox enabled with outgoing network client entitlement
- Keychain access via shelling out to `security` CLI (works outside sandbox for generic passwords)
- `SMAppService.mainApp` for launch-at-login toggle
- Color tiers: green (<50%), amber (50–80%), orange (80–90%), red (90%+)
- Progress bars use gradient fills matching tier color, with glow effect at 80%+

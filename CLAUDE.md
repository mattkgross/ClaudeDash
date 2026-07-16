# AgentDash

## Project Overview
macOS menu bar app (SwiftUI, macOS 14+) that displays Claude Code and Codex CLI usage. Lives in the menu bar, shows each provider's shortest-window percentage as the icon label (the 5-hour session where one is reported, otherwise the weekly cap), opens a popover with stacked sections (Claude on top, Codex below) when clicked. Each section auto-hides when its CLI isn't installed.

## Architecture
- **AgentDashApp.swift** — `@main` entry point, `MenuBarExtra` scene with `.window` style. Creates one `UsageService` (Claude) and one `CodexUsageService` (Codex), passes both to `UsageView`. Menu bar label renders `🧠 X% 🤖 Y%`, each segment shown only if that provider is signed in.
- **UsageView.swift** — Popover UI. Stacks a Claude section and a Codex section, each with its own `SectionHeader` (icon + label + per-provider refresh button). Renders `UsageRow` instances generic over `BucketDisplayable`. Footer with launch-at-login and quit.
- **UsageService.swift** — `@Observable` class for Claude. Reads keychain token, polls Anthropic API every 60s, handles in-memory token refresh.
- **CodexUsageService.swift** — `@Observable` class for Codex. Reads `~/.codex/auth.json` via `/bin/cat`, polls the ChatGPT backend every 60s. Exposes `isAvailable` so the view can hide the section if Codex isn't installed. Relies on the Codex CLI to refresh its own token; we re-read `auth.json` each poll.
- **Models.swift** — Codable types for both providers. `BucketDisplayable` protocol with default-implemented styling (tier color, gradient, glow, formatted reset time, day markers) so `UsageRow` works for either provider's bucket. Anthropic types: `UsageResponse`, `UsageBucket`, `UsageLimit`, `SpendingData`, `DayMarker`, `UsageTier`. Codex types: `CodexUsageResponse`, `CodexRateLimit`, `CodexUsageBucket`, `CodexCredits`. `ISO8601DateParser` is the shared reset-timestamp parser (tolerates the endpoint's fractional-seconds variant) used by both `UsageBucket` and `UsageLimit`.

## Data Sources

### Claude
- OAuth token read from macOS Keychain: `security find-generic-password -s "Claude Code-credentials" -w`
- Token path in JSON: `claudeAiOauth.accessToken`
- API endpoint: `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer {token}` and `anthropic-beta: oauth-2025-04-20`
- API returns utilization as a percentage (e.g., `29.0` = 29%), NOT as a 0–1 fraction
- The top-level `five_hour`/`seven_day` buckets drive the Session and Weekly rows. Per-model weekly caps live in a generic `limits` array, **not** in dedicated fields — the old `seven_day_sonnet`/`seven_day_omelette` keys still appear but now decode to null. Each `limits` entry is `{ kind, group, percent (0–100), resets_at (ISO8601 string), scope: { model: { display_name } } }`.
- **Per-model caps are identified by data, never by a hardcoded key** (same principle as Codex's `limit_window_seconds`). The Fable weekly row reads `UsageResponse.fableWeekly`, which finds the `limits` entry with `kind == "weekly_scoped"` whose model `display_name` case-insensitively contains "fable" (tolerating a version suffix like "Fable 5"); the row label comes from that `display_name`. This mirrors how Claude Code's own CLI renders scoped weekly bars, and it avoids the field-goes-null rot that removed the earlier Sonnet/Design rows.
- Token refresh: `POST https://platform.claude.com/v1/oauth/token` with `grant_type=refresh_token` (in-memory only, never written back to keychain)

### Codex
- OAuth token read from `~/.codex/auth.json` (mode 0600). Shape: `{ "tokens": { "access_token": "...", "account_id": "..." } }`
- API endpoint: `GET https://chatgpt.com/backend-api/wham/usage` with `Authorization: Bearer {access_token}`, `ChatGPT-Account-Id: {account_id}`, and a `User-Agent` header.
- Response shape: `{ rate_limit: { primary_window: { used_percent, limit_window_seconds, reset_at, ... }, secondary_window: ... }, credits: { has_credits, unlimited, balance } }`. `reset_at` is Unix epoch seconds.
- **Window identity comes from `limit_window_seconds`, never from the field name.** The field names describe position, not duration — as of Jul 2026 a Plus account returns the *weekly* window (`limit_window_seconds: 604800`) in `primary_window` with `secondary_window: null`, and no 5-hour window at all. Read windows via `CodexRateLimit.orderedWindows`, which sorts by real duration; labels/icons come from `CodexUsageBucket.windowLabel`/`windowIcon`.
- Numeric fields are decoded tolerantly (int/float/string) — see `CodexUsageBucket.init(from:)`, mirroring `SpendingData`.
- Token refresh: not implemented locally — relies on the Codex CLI to refresh `auth.json` in place.

## Build
```
xcodebuild -project AgentDash.xcodeproj -scheme AgentDash -configuration Debug build
```
Or via the `Makefile`:
```
make build      # debug build
make test       # runs the AgentDashTests suite
make install    # installs to /Applications and launches
make run        # builds and runs from the build directory
```

## Tests
`AgentDashTests` (Swift Testing) covers response decoding for both providers — the wire format is the
part of this app that changes underneath us, so that's where the tests are. `CodexUsageTests` covers
Codex window identification; `AnthropicUsageTests` covers the Claude `limits` array and Fable-cap
identification.

The target is deliberately **host-less**: it has no `TEST_HOST` and compiles `Models.swift` directly
into the bundle, so tests decode JSON without launching the menu bar app or its sandbox. Adding a
model file that tests need means adding it to the `AgentDashTests` target too.

When Codex or Anthropic changes a payload, add the real captured JSON as a fixture case rather than
adjusting an assertion to match — the existing fixtures are verbatim wire responses, dated in comments.

## Key Decisions
- `LSUIElement = true` in Info.plist hides the dock icon
- App Sandbox enabled with outgoing network client entitlement
- Keychain access via shelling out to `security` CLI (works outside sandbox for generic passwords)
- Codex auth.json read via shelling out to `/bin/cat` (mirrors the keychain shell-out pattern; avoids new entitlements)
- `SMAppService.mainApp` for launch-at-login toggle
- Color tiers: green (<50%), amber (50–80%), orange (80–90%), red (90%+)
- Progress bars use gradient fills matching tier color, with glow effect at 80%+
- Each provider section is independently visible — if a CLI isn't installed, that section (and its menu-bar segment) is hidden, not shown as an error

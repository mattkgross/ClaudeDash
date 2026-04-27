# AgentDash

A macOS menu bar app that shows your Claude Code and Codex CLI usage at a glance. Stacks each provider's session and weekly limits in a single popover, with progress bars and reset times — without needing an active CLI session open.

![Screenshot](https://img.shields.io/badge/macOS-14%2B-blue)

## Requirements

- macOS 14.0+
- Xcode 15+
- At least one of:
  - An active [Claude Code](https://docs.anthropic.com/en/docs/claude-code) session (the app reads your OAuth token from the macOS Keychain)
  - The [Codex CLI](https://developers.openai.com/codex/cli) signed in with a ChatGPT account (the app reads `~/.codex/auth.json`)

If only one is installed, only that provider's section appears in the popover.

## Setup

1. Clone the repo:
   ```
   git clone https://github.com/mattkgross/ClaudeDash.git
   ```

2. Install:
   ```
   make install
   ```

3. Find "AgentDash" in your applications folder and run it. It will show up in your menu bar.

## How It Works

- **Claude side**: reads the OAuth token from the macOS Keychain (`Claude Code-credentials`) and polls `https://api.anthropic.com/api/oauth/usage`.
- **Codex side**: reads the OAuth token from `~/.codex/auth.json` and polls `https://chatgpt.com/backend-api/wham/usage`.
- Both providers refresh every 60 seconds independently. Each section has its own refresh button.
- The menu bar label shows `🧠 X% 🤖 Y%` — your current 5-hour session percentage for each installed provider, color-coded by tier (green < 50%, amber 50–80%, orange 80–90%, red 90%+).
- Each progress bar uses the same color tiers, with a glow effect at 80%+.
- Optionally launches at login via the toggle in the popover footer.

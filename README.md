# ClaudeDash

A macOS menu bar app that shows your Claude Code usage at a glance. Displays session (5-hour), weekly (all models), and weekly (Sonnet-only) usage buckets with progress bars and reset times — without needing an active Claude Code session open.

![Screenshot](https://img.shields.io/badge/macOS-14%2B-blue)

## Requirements

- macOS 14.0+
- Xcode 15+
- An active [Claude Code](https://docs.anthropic.com/en/docs/claude-code) session (the app reads your OAuth token from the macOS Keychain)

## Setup

1. Clone the repo:
   ```
   git clone https://github.com/mattkgross/ClaudeDash.git
   ```

2. Install:
   ```
   make install
   ```

3. Find "ClaudeDash" in your applications folder and run it. It will show up in your menu bar.

## How It Works

- Reads your Claude Code OAuth token from the macOS Keychain (`Claude Code-credentials`)
- Polls `https://api.anthropic.com/api/oauth/usage` every 2 minutes
- Displays all three usage buckets in a popover with color-coded percentages (green < 50%, amber 50–80%, red > 80%)
- Optionally launches at login via the toggle in the popover

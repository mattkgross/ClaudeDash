import SwiftUI

/// AgentDash menu bar app — displays Claude Code and Codex CLI usage in a persistent menu bar widget.
@main
struct AgentDashApp: App {
  @State private var claudeService = UsageService()
  @State private var codexService = CodexUsageService()

  var body: some Scene {
    MenuBarExtra {
      UsageView(claudeService: claudeService, codexService: codexService)
    } label: {
      // `.window`-style MenuBarExtra labels drop sibling views beyond the first Image+Text pair,
      // and SF Symbols interpolated into Text don't render in this context either. The reliable
      // workaround: emit the icons as Unicode emoji inside a single concatenated Text. Each
      // segment retains its own monospacedDigit + foregroundStyle (macOS may still override
      // colors with system menu-bar styling).
      Text("🧠 \(claudeService.usage?.fiveHour.percentage ?? 0)%")
        .monospacedDigit()
        .foregroundStyle(claudeService.usage?.fiveHour.tierColor ?? Color.secondary)
      + Text("   ")
      + Text("🤖 \(codexService.usage?.rateLimit?.primaryWindow?.percentage ?? 0)%")
        .monospacedDigit()
        .foregroundStyle(codexService.usage?.rateLimit?.primaryWindow?.tierColor ?? Color.secondary)
    }
    .menuBarExtraStyle(.window)
  }
}

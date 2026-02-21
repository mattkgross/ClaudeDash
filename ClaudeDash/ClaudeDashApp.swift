import SwiftUI

/// ClaudeDash menu bar app — displays Claude Code usage in a persistent menu bar widget.
@main
struct ClaudeDashApp: App {
  @State private var service = UsageService()

  var body: some Scene {
    MenuBarExtra {
      UsageView(service: service)
    } label: {
      let percentage = service.usage?.fiveHour.percentage ?? 0
      let color = service.usage?.fiveHour.tierColor ?? .secondary
      HStack(spacing: 2) {
        Image(systemName: "brain.fill")
        Text("\(percentage)%")
          .monospacedDigit()
      }
      // MenuBarExtra labels have limited styling support; the color is best-effort.
      .foregroundStyle(color)
    }
    .menuBarExtraStyle(.window)
  }
}

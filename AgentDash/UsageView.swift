import SwiftUI
import ServiceManagement

/// Main popover content. Shows a Claude section, a Codex section (when Codex is installed), and a shared footer.
struct UsageView: View {
  var claudeService: UsageService
  var codexService: CodexUsageService

  @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

  var body: some View {
    VStack(spacing: 0) {
      claudeSection

      if codexService.isAvailable {
        Divider()
        codexSection
      }

      Divider()
      footer
    }
    .frame(width: 280)
    .background {
      RoundedRectangle(cornerRadius: 12)
        .fill(.ultraThinMaterial)
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .fill(Color.black.opacity(0.25))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }
  }

  // MARK: - Claude section.

  @ViewBuilder
  private var claudeSection: some View {
    VStack(spacing: 0) {
      SectionHeader(icon: "🧠", title: "Claude Usage") { claudeService.fetchUsage() }
      Divider()
      claudeContent
    }
  }

  @ViewBuilder
  private var claudeContent: some View {
    if let usage = claudeService.usage {
      VStack(spacing: 16) {
        UsageRow(icon: "⚡", label: "Session", bucket: usage.fiveHour)
        UsageRow(icon: "🌙", label: "Weekly (All)", bucket: usage.sevenDay, showDayMarkers: true)
        if let omelette = usage.sevenDayOmelette {
          UsageRow(icon: "🎨", label: "Claude Design", bucket: omelette, showDayMarkers: true)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)

      if let spending = usage.extraUsage, spending.isEnabled {
        Divider()
        SpendingRow(spending: spending)
          .padding(.horizontal, 16)
          .padding(.vertical, 14)
      }
    } else if let error = claudeService.error {
      ErrorPanel(message: error)
    } else {
      LoadingPanel()
    }
  }

  // MARK: - Codex section.

  @ViewBuilder
  private var codexSection: some View {
    VStack(spacing: 0) {
      SectionHeader(icon: "🤖", title: "Codex Usage") { codexService.fetchUsage() }
      Divider()
      codexContent
    }
  }

  @ViewBuilder
  private var codexContent: some View {
    if let codex = codexService.usage, let rl = codex.rateLimit {
      VStack(spacing: 16) {
        if let primary = rl.primaryWindow {
          UsageRow(icon: "⚡", label: "Session 5h", bucket: primary)
        }
        if let secondary = rl.secondaryWindow {
          UsageRow(icon: "🌙", label: "Weekly", bucket: secondary, showDayMarkers: true)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)

      if let credits = codex.credits, credits.unlimited || credits.hasCredits || credits.balance != nil {
        Divider()
        CodexCreditsRow(credits: credits)
          .padding(.horizontal, 16)
          .padding(.vertical, 14)
      }
    } else if let error = codexService.error {
      ErrorPanel(message: error)
    } else {
      LoadingPanel()
    }
  }

  // MARK: - Footer.

  @ViewBuilder
  private var footer: some View {
    HStack {
      if let updated = mostRecentUpdate {
        Text("Updated \(updated, style: .relative) ago")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      Spacer()
      Toggle("Launch at Login", isOn: $launchAtLogin)
        .toggleStyle(.checkbox)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .onChange(of: launchAtLogin) { _, newValue in
          toggleLaunchAtLogin(newValue)
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)

    HStack {
      Spacer()
      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
      .buttonStyle(.plain)
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 10)
  }

  /// Most recent successful refresh across both providers, for the footer "Updated X ago" label.
  private var mostRecentUpdate: Date? {
    [claudeService.lastUpdated, codexService.lastUpdated]
      .compactMap { $0 }
      .max()
  }

  /// Toggles the launch-at-login setting via ServiceManagement.
  private func toggleLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      launchAtLogin = SMAppService.mainApp.status == .enabled
    }
  }
}

// MARK: - Reusable section parts.

/// Per-section header: leading icon + title, trailing refresh button.
private struct SectionHeader: View {
  let icon: String
  let title: String
  let onRefresh: () -> Void

  var body: some View {
    HStack {
      Text(icon)
      Text(title)
        .font(.headline)
      Spacer()
      Button(action: onRefresh) {
        Image(systemName: "arrow.clockwise")
          .font(.system(size: 12))
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 16)
    .padding(.top, 14)
    .padding(.bottom, 10)
  }
}

private struct ErrorPanel: View {
  let message: String

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.title2)
        .foregroundStyle(.orange)
      Text(message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 16)
    .padding(.vertical, 24)
  }
}

private struct LoadingPanel: View {
  var body: some View {
    ProgressView()
      .frame(maxWidth: .infinity)
      .padding(.vertical, 24)
  }
}

/// A single usage row with icon, label, animated gradient progress bar, and reset time.
/// Renders any `BucketDisplayable` — works for both Claude `UsageBucket` and Codex `CodexUsageBucket`.
struct UsageRow: View {
  let icon: String
  let label: String
  let bucket: any BucketDisplayable
  var showDayMarkers: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("\(icon) \(label)")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.primary)
        Spacer()
        Text("\(bucket.percentage)%")
          .font(.system(size: 12, weight: .semibold, design: .monospaced))
          .foregroundStyle(bucket.tierColor)
      }

      // Gradient progress bar with optional day-of-week markers for weekly buckets.
      GeometryReader { geometry in
        VStack(spacing: 0) {
          ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
              .fill(Color.primary.opacity(0.1))
              .frame(height: 6)

            RoundedRectangle(cornerRadius: 4)
              .fill(bucket.tierGradient)
              .frame(width: max(0, geometry.size.width * bucket.fraction), height: 6)
              .shadow(
                color: bucket.shouldGlow ? bucket.tierColor.opacity(0.6) : .clear,
                radius: bucket.shouldGlow ? 4 : 0,
                y: 0
              )
          }

          if showDayMarkers {
            DayMarkerRow(markers: bucket.dayBoundaryMarkers, barWidth: geometry.size.width)
              .frame(height: 16)
          }
        }
      }
      .frame(height: showDayMarkers ? 22 : 6)

      Text(bucket.formattedResetTime)
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
  }
}

/// A spending row showing Anthropic extra usage with a progress bar and dollar amounts.
struct SpendingRow: View {
  let spending: SpendingData

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("💰 Additional Use")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.primary)
        Spacer()
        Text("\(spending.spentPercentage)%")
          .font(.system(size: 12, weight: .semibold, design: .monospaced))
          .foregroundStyle(spending.tierColor)
      }

      // Gradient progress bar.
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 4)
            .fill(Color.primary.opacity(0.1))
            .frame(height: 6)

          RoundedRectangle(cornerRadius: 4)
            .fill(spending.tierGradient)
            .frame(width: max(0, geometry.size.width * spending.spentFraction), height: 6)
            .shadow(
              color: spending.shouldGlow ? spending.tierColor.opacity(0.6) : .clear,
              radius: spending.shouldGlow ? 4 : 0,
              y: 0
            )
        }
      }
      .frame(height: 6)

      Text("\(spending.formattedSpent) of \(spending.formattedLimit) limit")
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
  }
}

/// A simple row showing Codex credits balance ("Unlimited" or a pre-formatted currency string).
struct CodexCreditsRow: View {
  let credits: CodexCredits

  var body: some View {
    HStack {
      Text("💳 Credits")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.primary)
      Spacer()
      Text(displayValue)
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .foregroundStyle(.secondary)
    }
  }

  private var displayValue: String {
    if credits.unlimited { return "Unlimited" }
    return credits.balance ?? "—"
  }
}

/// Renders day-of-week boundary markers below a 7-day progress bar.
private struct DayMarkerRow: View {
  let markers: [DayMarker]
  let barWidth: CGFloat

  var body: some View {
    ZStack {
      ForEach(Array(markers.enumerated()), id: \.offset) { _, marker in
        VStack(spacing: 1) {
          Rectangle()
            .fill(Color.primary.opacity(marker.isToday ? 0.4 : 0.2))
            .frame(width: 1, height: 4)
          Text(marker.label)
            .font(.system(size: 7, design: .monospaced))
            .fontWeight(marker.isToday ? .semibold : .regular)
            .foregroundStyle(Color.primary.opacity(marker.isToday ? 0.6 : 0.3))
        }
        .fixedSize()
        .position(x: barWidth * marker.position, y: 8)
      }
    }
  }
}

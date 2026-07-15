import SwiftUI

/// Represents a day boundary marker on the 7-day progress bar.
struct DayMarker {
  let position: Double
  let label: String
  let isToday: Bool
}

/// Shared color tier helpers for usage and spending percentage displays.
enum UsageTier {
  /// Returns the tier color for a given percentage (0–100).
  static func color(for percentage: Int) -> Color {
    switch percentage {
    case ..<50:
      return Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255)
    case 50..<80:
      return Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255)
    case 80..<90:
      return Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)
    default:
      return Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)
    }
  }

  /// Returns a left-to-right gradient for a given percentage tier.
  static func gradient(for percentage: Int) -> LinearGradient {
    switch percentage {
    case ..<50:
      return LinearGradient(
        colors: [
          Color(red: 110 / 255, green: 231 / 255, blue: 183 / 255),
          Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255)
        ],
        startPoint: .leading, endPoint: .trailing
      )
    case 50..<80:
      return LinearGradient(
        colors: [
          Color(red: 253 / 255, green: 224 / 255, blue: 71 / 255),
          Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)
        ],
        startPoint: .leading, endPoint: .trailing
      )
    case 80..<90:
      return LinearGradient(
        colors: [
          Color(red: 251 / 255, green: 146 / 255, blue: 60 / 255),
          Color(red: 234 / 255, green: 88 / 255, blue: 12 / 255)
        ],
        startPoint: .leading, endPoint: .trailing
      )
    default:
      return LinearGradient(
        colors: [
          Color(red: 248 / 255, green: 113 / 255, blue: 113 / 255),
          Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)
        ],
        startPoint: .leading, endPoint: .trailing
      )
    }
  }

  /// Whether the percentage is high enough to show a glow effect.
  static func shouldGlow(for percentage: Int) -> Bool {
    percentage >= 80
  }
}

/// A displayable usage bucket — anything that has a percentage and a reset time can be drawn as a UsageRow.
/// Conforming types provide the three source-of-truth properties; the rest come from default implementations.
protocol BucketDisplayable {
  var percentage: Int { get }
  var fraction: Double { get }
  var parsedResetDate: Date? { get }
  var tierColor: Color { get }
  var tierGradient: LinearGradient { get }
  var shouldGlow: Bool { get }
  var formattedResetTime: String { get }
  var dayBoundaryMarkers: [DayMarker] { get }
}

extension BucketDisplayable {
  /// Color tier based on usage level.
  var tierColor: Color { UsageTier.color(for: percentage) }

  /// Gradient for the progress bar, transitioning from a lighter to deeper shade of the tier color.
  var tierGradient: LinearGradient { UsageTier.gradient(for: percentage) }

  /// Whether usage is high enough to show a glow effect on the progress bar.
  var shouldGlow: Bool { UsageTier.shouldGlow(for: percentage) }

  /// Formatted reset time string for display.
  var formattedResetTime: String {
    guard let resetDate = parsedResetDate else { return "" }

    let now = Date()
    let interval = resetDate.timeIntervalSince(now)

    if interval <= 0 {
      return "Resetting..."
    }

    let hours = Int(interval) / 3600
    let minutes = (Int(interval) % 3600) / 60

    if hours < 24 {
      if hours == 0 {
        return "Resets in \(minutes)m"
      }
      return "Resets in \(hours)h \(minutes)m"
    }

    let displayFormatter = DateFormatter()
    displayFormatter.dateFormat = "MMM d 'at' ha"
    return "Resets \(displayFormatter.string(from: resetDate))"
  }

  /// Day boundary markers for the 7-day progress bar (6 interior ticks at each day boundary).
  var dayBoundaryMarkers: [DayMarker] {
    guard let resetDate = parsedResetDate else { return [] }

    let calendar = Calendar.current
    let windowStart = calendar.date(byAdding: .day, value: -7, to: resetDate)!
    let today = calendar.startOfDay(for: Date())
    let weekdayLetters = ["U", "M", "T", "W", "R", "F", "S"]

    return (1...6).map { dayOffset in
      let boundaryDate = calendar.date(byAdding: .day, value: dayOffset, to: windowStart)!
      let weekday = calendar.component(.weekday, from: boundaryDate)
      let label = weekdayLetters[weekday - 1]
      let isToday = calendar.startOfDay(for: boundaryDate) == today
      return DayMarker(position: Double(dayOffset) / 7.0, label: label, isToday: isToday)
    }
  }
}

/// API response from the Anthropic usage endpoint.
struct UsageResponse: Codable {
  let fiveHour: UsageBucket
  let sevenDay: UsageBucket
  let extraUsage: SpendingData?

  enum CodingKeys: String, CodingKey {
    case fiveHour = "five_hour"
    case sevenDay = "seven_day"
    case extraUsage = "extra_usage"
  }
}

/// A single usage bucket with utilization percentage and reset time.
struct UsageBucket: Codable, BucketDisplayable {
  let utilization: Double
  let resetsAt: String?

  enum CodingKeys: String, CodingKey {
    case utilization
    case resetsAt = "resets_at"
  }

  /// Usage as an integer percentage (0–100). API returns values already as percentages.
  var percentage: Int {
    Int(utilization.rounded())
  }

  /// Utilization as a 0–1 fraction for progress bar rendering.
  var fraction: Double {
    min(utilization / 100.0, 1.0)
  }

  /// Parses the ISO8601 reset date string into a Date object.
  var parsedResetDate: Date? {
    guard let resetsAt = resetsAt else { return nil }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    // Try with fractional seconds first, then without.
    var date = formatter.date(from: resetsAt)
    if date == nil {
      formatter.formatOptions = [.withInternetDateTime]
      date = formatter.date(from: resetsAt)
    }

    return date
  }
}

/// Extra usage (additional spend) data from the Anthropic API.
struct SpendingData: Codable {
  let isEnabled: Bool
  let monthlyLimit: Double
  let usedCredits: Double
  let utilization: Double?
  let currency: String?

  enum CodingKeys: String, CodingKey {
    case isEnabled = "is_enabled"
    case monthlyLimit = "monthly_limit"
    case usedCredits = "used_credits"
    case utilization
    case currency
  }

  /// Decodes extra usage data while tolerating undocumented response-shape changes.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
    monthlyLimit = try Self.decodeDouble(from: container, forKey: .monthlyLimit) ?? 0
    usedCredits = try Self.decodeDouble(from: container, forKey: .usedCredits) ?? 0
    utilization = try Self.decodeDouble(from: container, forKey: .utilization)
    currency = try container.decodeIfPresent(String.self, forKey: .currency)
  }

  /// Spending as an integer percentage (0–100), deriving utilization when needed.
  var spentPercentage: Int {
    Int(spendingUtilization.rounded())
  }

  /// Spending as a 0–1 fraction for progress bar rendering.
  var spentFraction: Double {
    min(spendingUtilization / 100.0, 1.0)
  }

  /// Color tier based on spending percentage.
  var tierColor: Color {
    UsageTier.color(for: spentPercentage)
  }

  /// Gradient for the spending progress bar.
  var tierGradient: LinearGradient {
    UsageTier.gradient(for: spentPercentage)
  }

  /// Whether spending is high enough to show a glow effect.
  var shouldGlow: Bool {
    UsageTier.shouldGlow(for: spentPercentage)
  }

  private static let currencyFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return f
  }()

  /// Formatted spent amount in dollars (e.g. "$5.69"). API returns cents.
  var formattedSpent: String {
    Self.currencyFormatter.string(from: NSNumber(value: usedCredits / 100.0)) ?? "$0.00"
  }

  /// Formatted monthly limit in dollars (e.g. "$100.00"). API returns cents.
  var formattedLimit: String {
    Self.currencyFormatter.string(from: NSNumber(value: monthlyLimit / 100.0)) ?? "$0.00"
  }

  /// Spending utilization as a percentage, derived when the API omits it.
  private var spendingUtilization: Double {
    if let utilization {
      return utilization
    }
    guard monthlyLimit > 0 else {
      return usedCredits > 0 ? 100 : 0
    }
    return (usedCredits / monthlyLimit) * 100.0
  }

  /// Decodes numeric API fields that may arrive as either JSON numbers or strings.
  private static func decodeDouble(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Double? {
    if let number = try? container.decodeIfPresent(Double.self, forKey: key) {
      return number
    }
    if let string = try? container.decodeIfPresent(String.self, forKey: key) {
      return Double(string)
    }
    return nil
  }
}

// MARK: - Codex (OpenAI) usage models

/// Top-level response from `https://chatgpt.com/backend-api/wham/usage`.
/// Mirrors `RateLimitStatusPayload` from the openai/codex repo (codex-rs/backend-client).
struct CodexUsageResponse: Codable {
  let planType: String?
  let rateLimit: CodexRateLimit?
  let credits: CodexCredits?

  enum CodingKeys: String, CodingKey {
    case planType = "plan_type"
    case rateLimit = "rate_limit"
    case credits
  }
}

/// The rate limit container returned by Codex.
///
/// The field names describe position, not duration: Codex has shipped a weekly window in
/// `primary_window` with `secondary_window` null. Read windows through `orderedWindows` so they are
/// identified by their actual `limit_window_seconds` rather than by which field they arrived in.
struct CodexRateLimit: Codable {
  let primaryWindow: CodexUsageBucket?
  let secondaryWindow: CodexUsageBucket?

  enum CodingKeys: String, CodingKey {
    case primaryWindow = "primary_window"
    case secondaryWindow = "secondary_window"
  }

  /// Every window the API actually returned, shortest duration first so a rolling
  /// session sorts above a weekly cap. Windows of unknown duration sort last.
  var orderedWindows: [CodexUsageBucket] {
    [primaryWindow, secondaryWindow]
      .compactMap { $0 }
      .sorted { ($0.limitWindowSeconds ?? Int.max) < ($1.limitWindowSeconds ?? Int.max) }
  }
}

/// A single Codex usage bucket. Wire format uses `used_percent` (already 0–100) and a Unix-epoch `reset_at`.
///
/// `limitWindowSeconds` is the source of truth for what the window means — never infer duration
/// from the field the bucket arrived in.
struct CodexUsageBucket: Codable, BucketDisplayable {
  let usedPercent: Double
  let limitWindowSeconds: Int?
  let resetAt: Int?

  enum CodingKeys: String, CodingKey {
    case usedPercent = "used_percent"
    case limitWindowSeconds = "limit_window_seconds"
    case resetAt = "reset_at"
  }

  /// Decodes while tolerating numeric fields arriving as ints, floats, or strings, so a widened
  /// `used_percent` can't take down the whole Codex section.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    usedPercent = try Self.decodeNumber(from: container, forKey: .usedPercent) ?? 0
    limitWindowSeconds = try Self.decodeNumber(from: container, forKey: .limitWindowSeconds).map { Int($0) }
    resetAt = try Self.decodeNumber(from: container, forKey: .resetAt).map { Int($0) }
  }

  /// Human-readable name for this window, derived from how long the window actually is.
  var windowLabel: String {
    guard let seconds = limitWindowSeconds else { return "Usage" }

    switch seconds {
    case 604800:
      return "Weekly"
    case 86400:
      return "Daily"
    case 86401...:
      return "\(seconds / 86400)-Day"
    default:
      return "Session \(max(seconds / 3600, 1))h"
    }
  }

  /// Moon for multi-day caps, lightning for short rolling sessions — matches the Claude section.
  var windowIcon: String {
    guard let seconds = limitWindowSeconds else { return "⚡" }
    return seconds >= 86400 ? "🌙" : "⚡"
  }

  /// Day ticks only make sense on a true 7-day bar, since `dayBoundaryMarkers` derives the window
  /// start by subtracting exactly 7 days from the reset date.
  var showsDayMarkers: Bool {
    limitWindowSeconds == 604800
  }

  /// Usage as an integer percentage (0–100), clamped for display.
  var percentage: Int {
    min(max(Int(usedPercent.rounded()), 0), 100)
  }

  /// Fraction (0–1) for progress bar rendering. Over-100% clamps visually at a full bar.
  var fraction: Double {
    min(max(usedPercent / 100.0, 0), 1.0)
  }

  /// Codex sends `reset_at` as Unix epoch seconds; convert to `Date` for the shared formatter.
  var parsedResetDate: Date? {
    resetAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
  }

  /// Decodes numeric API fields that may arrive as either JSON numbers or strings.
  private static func decodeNumber(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Double? {
    if let number = try? container.decodeIfPresent(Double.self, forKey: key) {
      return number
    }
    if let string = try? container.decodeIfPresent(String.self, forKey: key) {
      return Double(string)
    }
    return nil
  }
}

/// Credits balance reported alongside the rate limits.
struct CodexCredits: Codable {
  let hasCredits: Bool
  let unlimited: Bool
  /// Codex returns this as a pre-formatted currency string when set (e.g. "$5.69"), or null if unset.
  let balance: String?

  enum CodingKeys: String, CodingKey {
    case hasCredits = "has_credits"
    case unlimited
    case balance
  }
}

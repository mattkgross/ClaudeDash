import SwiftUI

/// Represents a day boundary marker on the 7-day progress bar.
struct DayMarker {
  let position: Double
  let label: String
  let isToday: Bool
}

/// API response from the Anthropic usage endpoint.
struct UsageResponse: Codable {
  let fiveHour: UsageBucket
  let sevenDay: UsageBucket
  let sevenDaySonnet: UsageBucket

  enum CodingKeys: String, CodingKey {
    case fiveHour = "five_hour"
    case sevenDay = "seven_day"
    case sevenDaySonnet = "seven_day_sonnet"
  }
}

/// A single usage bucket with utilization percentage and reset time.
struct UsageBucket: Codable {
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

  /// Color tier based on usage level.
  var tierColor: Color {
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

  /// Gradient for the progress bar, transitioning from a lighter to deeper shade of the tier color.
  var tierGradient: LinearGradient {
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

  /// Whether usage is high enough to show a glow effect on the progress bar.
  var shouldGlow: Bool {
    percentage >= 80
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
}

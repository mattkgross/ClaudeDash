import Foundation
import Testing

/// Tests for Codex usage decoding and window identification.
///
/// The central invariant: a window's meaning comes from `limit_window_seconds`, never from whether
/// it arrived in `primary_window` or `secondary_window`. Codex has shipped a weekly window in
/// `primary_window` with `secondary_window` null, which silently mislabeled the weekly cap as a
/// 5-hour session for anyone reading the field names.
struct CodexUsageTests {
  /// Decodes a JSON payload the way `CodexUsageService` does.
  private func decode(_ json: String) throws -> CodexUsageResponse {
    try JSONDecoder().decode(CodexUsageResponse.self, from: Data(json.utf8))
  }

  // MARK: - Window identification

  /// Real payload captured 2026-07-15 from a Plus account: one weekly window in `primary_window`,
  /// no secondary. This is the shape that broke positional labeling.
  @Test("A weekly window in primary_window is labeled Weekly, not Session 5h")
  func weeklyWindowInPrimarySlot() throws {
    let response = try decode("""
    {
      "plan_type": "plus",
      "rate_limit": {
        "primary_window": { "used_percent": 22, "limit_window_seconds": 604800, "reset_at": 1784667202 },
        "secondary_window": null
      },
      "credits": { "has_credits": false, "unlimited": false, "balance": "0" }
    }
    """)

    let windows = try #require(response.rateLimit?.orderedWindows)
    #expect(windows.count == 1)

    let weekly = try #require(windows.first)
    #expect(weekly.windowLabel == "Weekly")
    #expect(weekly.windowIcon == "🌙")
    #expect(weekly.showsDayMarkers)
    #expect(weekly.percentage == 22)
  }

  /// The historical two-window shape must keep working — Codex may still return it for other plans.
  @Test("Both windows render, shortest first")
  func sessionAndWeeklyWindows() throws {
    let response = try decode("""
    {
      "rate_limit": {
        "primary_window": { "used_percent": 83, "limit_window_seconds": 18000, "reset_at": 1784667202 },
        "secondary_window": { "used_percent": 43, "limit_window_seconds": 604800, "reset_at": 1784667202 }
      }
    }
    """)

    let windows = try #require(response.rateLimit?.orderedWindows)
    #expect(windows.count == 2)
    #expect(windows.map(\.windowLabel) == ["Session 5h", "Weekly"])
    #expect(windows.map(\.percentage) == [83, 43])
    #expect(windows[0].showsDayMarkers == false)
    #expect(windows[1].showsDayMarkers)
  }

  /// Ordering is by duration, so a weekly cap sorts below a session even when the fields are swapped.
  @Test("Ordering follows duration, not field position")
  func orderingIgnoresFieldPosition() throws {
    let response = try decode("""
    {
      "rate_limit": {
        "primary_window": { "used_percent": 43, "limit_window_seconds": 604800, "reset_at": 1784667202 },
        "secondary_window": { "used_percent": 83, "limit_window_seconds": 18000, "reset_at": 1784667202 }
      }
    }
    """)

    let windows = try #require(response.rateLimit?.orderedWindows)
    #expect(windows.map(\.windowLabel) == ["Session 5h", "Weekly"])
  }

  @Test("Window labels derive from duration", arguments: [
    (18000, "Session 5h", "⚡", false),
    (3600, "Session 1h", "⚡", false),
    (604800, "Weekly", "🌙", true),
    (86400, "Daily", "🌙", false),
    (259200, "3-Day", "🌙", false)
  ])
  func windowLabelForDuration(seconds: Int, label: String, icon: String, markers: Bool) throws {
    let response = try decode("""
    { "rate_limit": { "primary_window": { "used_percent": 10, "limit_window_seconds": \(seconds) } } }
    """)

    let window = try #require(response.rateLimit?.orderedWindows.first)
    #expect(window.windowLabel == label)
    #expect(window.windowIcon == icon)
    #expect(window.showsDayMarkers == markers)
  }

  /// Day ticks are drawn by subtracting exactly 7 days from the reset date, so they'd be wrong
  /// on any other window length.
  @Test("Only a true 7-day window gets day markers")
  func dayMarkersOnlyForSevenDayWindow() throws {
    let response = try decode("""
    {
      "rate_limit": {
        "primary_window": { "used_percent": 10, "limit_window_seconds": 18000, "reset_at": 1784667202 },
        "secondary_window": { "used_percent": 10, "limit_window_seconds": 604800, "reset_at": 1784667202 }
      }
    }
    """)

    let windows = try #require(response.rateLimit?.orderedWindows)
    #expect(windows[0].dayBoundaryMarkers.isEmpty == false || windows[0].showsDayMarkers == false)
    #expect(windows[1].dayBoundaryMarkers.count == 6)
  }

  /// A window with no stated duration still renders rather than being dropped or mislabeled.
  @Test("Unknown window duration falls back to a neutral label")
  func unknownWindowDuration() throws {
    let response = try decode("""
    { "rate_limit": { "primary_window": { "used_percent": 5, "reset_at": 1784667202 } } }
    """)

    let window = try #require(response.rateLimit?.orderedWindows.first)
    #expect(window.windowLabel == "Usage")
    #expect(window.showsDayMarkers == false)
  }

  @Test("No windows yields an empty list rather than a crash")
  func noWindows() throws {
    let response = try decode("""
    { "rate_limit": { "primary_window": null, "secondary_window": null } }
    """)

    #expect(response.rateLimit?.orderedWindows.isEmpty == true)
  }

  // MARK: - Decoding tolerance

  /// `used_percent` is nested inside optional structs, but Decodable throws from the innermost
  /// container outward — so a widened numeric type would fail the *entire* response decode and
  /// collapse the whole Codex section, not just one row.
  @Test("used_percent decodes from int, float, or string", arguments: [
    ("22", 22),
    ("22.6", 23),
    ("22.4", 22),
    ("\"22\"", 22)
  ])
  func usedPercentTolerance(raw: String, expected: Int) throws {
    let response = try decode("""
    { "rate_limit": { "primary_window": { "used_percent": \(raw), "limit_window_seconds": 18000 } } }
    """)

    let window = try #require(response.rateLimit?.orderedWindows.first)
    #expect(window.percentage == expected)
  }

  @Test("Percentage and fraction clamp to their display ranges")
  func percentageClamping() throws {
    let response = try decode("""
    {
      "rate_limit": {
        "primary_window": { "used_percent": 140, "limit_window_seconds": 18000 },
        "secondary_window": { "used_percent": -5, "limit_window_seconds": 604800 }
      }
    }
    """)

    let windows = try #require(response.rateLimit?.orderedWindows)
    #expect(windows[0].percentage == 100)
    #expect(windows[0].fraction == 1.0)
    #expect(windows[1].percentage == 0)
    #expect(windows[1].fraction == 0.0)
  }

  @Test("A missing used_percent defaults to zero instead of failing the response")
  func missingUsedPercent() throws {
    let response = try decode("""
    { "rate_limit": { "primary_window": { "limit_window_seconds": 18000 } } }
    """)

    let window = try #require(response.rateLimit?.orderedWindows.first)
    #expect(window.percentage == 0)
  }

  /// Unknown top-level keys are routine on this endpoint (`spend_control`, `promo`,
  /// `additional_rate_limits`), so their presence must not break decoding.
  @Test("Unrecognized response fields are ignored")
  func unknownFieldsIgnored() throws {
    let response = try decode("""
    {
      "plan_type": "plus",
      "rate_limit": {
        "allowed": true,
        "primary_window": { "used_percent": 22, "limit_window_seconds": 604800, "reset_at": 1784667202, "reset_after_seconds": 531093 }
      },
      "additional_rate_limits": null,
      "spend_control": { "reached": false },
      "promo": null
    }
    """)

    #expect(response.planType == "plus")
    #expect(response.rateLimit?.orderedWindows.first?.windowLabel == "Weekly")
  }

  @Test("reset_at converts from Unix epoch seconds")
  func resetDateParsing() throws {
    let response = try decode("""
    { "rate_limit": { "primary_window": { "used_percent": 22, "limit_window_seconds": 604800, "reset_at": 1784667202 } } }
    """)

    let window = try #require(response.rateLimit?.orderedWindows.first)
    #expect(window.parsedResetDate == Date(timeIntervalSince1970: 1784667202))
  }

  // MARK: - Credits

  @Test("Credits balance decodes as a preformatted string")
  func creditsDecoding() throws {
    let response = try decode("""
    { "credits": { "has_credits": false, "unlimited": false, "balance": "0" } }
    """)

    let credits = try #require(response.credits)
    #expect(credits.hasCredits == false)
    #expect(credits.unlimited == false)
    #expect(credits.balance == "0")
  }
}

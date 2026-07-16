import Foundation
import Testing

/// Tests for Anthropic usage decoding, focused on the per-model weekly cap.
///
/// The wire format moved per-model quotas out of dedicated fields (`seven_day_sonnet`,
/// `seven_day_omelette`, now all null) and into a generic `limits` array. Each entry states its own
/// `kind` and optional model `scope`, so the Fable weekly cap is identified by data — a
/// `weekly_scoped` entry whose model display name is Fable — never by a hardcoded key.
struct AnthropicUsageTests {
  /// Decodes a JSON payload the way `UsageService` does.
  private func decode(_ json: String) throws -> UsageResponse {
    try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
  }

  // MARK: - Fable weekly cap

  /// Real payload captured 2026-07-16 from a Max account carrying a Fable weekly cap. The scoped
  /// entry is the third element of `limits`; the earlier `session`/`weekly_all` entries and the null
  /// per-model fields are kept verbatim so this fixture matches the wire shape exactly.
  @Test("The Fable weekly cap decodes from the limits array")
  func fableWeeklyDecodesFromLimits() throws {
    let response = try decode(Self.capturedPayload)

    let fable = try #require(response.fableWeekly)
    #expect(fable.percentage == 8)
    #expect(fable.fraction == 0.08)
    #expect(fable.modelDisplayName == "Fable")
    #expect(fable.showsDayMarkers)

    // The wire value carries sub-second precision ("...59.803669+00:00"); assert the parse landed on
    // the right UTC wall-clock second rather than on an exact fractional instant.
    let parsed = try #require(fable.parsedResetDate)
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = try #require(TimeZone(identifier: "UTC"))
    let c = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsed)
    #expect(c.year == 2026 && c.month == 7 && c.day == 19)
    #expect(c.hour == 13 && c.minute == 59 && c.second == 59)
  }

  /// The main Claude buckets keep decoding alongside the new array.
  @Test("Session and weekly buckets still decode from the same payload")
  func coreBucketsUnaffected() throws {
    let response = try decode(Self.capturedPayload)
    #expect(response.fiveHour.percentage == 0)
    #expect(response.sevenDay.percentage == 5)
  }

  /// An account without a Fable cap returns `limits` entries that are all unscoped, so there is no
  /// row to draw.
  @Test("No scoped Fable entry yields no Fable row")
  func fableWeeklyAbsentWhenUnscoped() throws {
    let response = try decode("""
    {
      "five_hour": { "utilization": 0.0, "resets_at": "2026-07-16T17:19:59+00:00" },
      "seven_day": { "utilization": 5.0, "resets_at": "2026-07-19T13:59:59+00:00" },
      "limits": [
        { "kind": "session", "group": "session", "percent": 0, "resets_at": "2026-07-16T17:19:59+00:00", "scope": null },
        { "kind": "weekly_all", "group": "weekly", "percent": 5, "resets_at": "2026-07-19T13:59:59+00:00", "scope": null }
      ]
    }
    """)

    #expect(response.fableWeekly == nil)
  }

  /// A response predating the `limits` array (or one that omits it) must still decode; the Fable row
  /// is simply absent.
  @Test("A payload without a limits array still decodes")
  func limitsAbsent() throws {
    let response = try decode("""
    {
      "five_hour": { "utilization": 0.0, "resets_at": "2026-07-16T17:19:59+00:00" },
      "seven_day": { "utilization": 5.0, "resets_at": "2026-07-19T13:59:59+00:00" }
    }
    """)

    #expect(response.fableWeekly == nil)
  }

  /// The server controls the display name, so matching is case-insensitive and tolerates a version
  /// suffix like "Fable 5". A different scoped model must not be mistaken for Fable.
  @Test("Fable matching is case-insensitive and ignores other scoped models", arguments: [
    ("Fable", true),
    ("fable", true),
    ("Fable 5", true),
    ("Claude Fable", true),
    ("Opus", false),
    ("Sonnet", false)
  ])
  func fableMatching(displayName: String, matches: Bool) throws {
    let response = try decode("""
    {
      "five_hour": { "utilization": 0.0, "resets_at": "2026-07-16T17:19:59+00:00" },
      "seven_day": { "utilization": 5.0, "resets_at": "2026-07-19T13:59:59+00:00" },
      "limits": [
        {
          "kind": "weekly_scoped", "group": "weekly", "percent": 8,
          "resets_at": "2026-07-19T13:59:59+00:00",
          "scope": { "model": { "id": null, "display_name": "\(displayName)" } }
        }
      ]
    }
    """)

    #expect((response.fableWeekly != nil) == matches)
  }

  /// A `weekly_scoped` entry is only the Fable cap when its scope names a model — a scoped entry
  /// with a null model must not slip through as Fable.
  @Test("A weekly_scoped entry with no model is not treated as Fable")
  func scopedWithoutModelIgnored() throws {
    let response = try decode("""
    {
      "five_hour": { "utilization": 0.0, "resets_at": "2026-07-16T17:19:59+00:00" },
      "seven_day": { "utilization": 5.0, "resets_at": "2026-07-19T13:59:59+00:00" },
      "limits": [
        { "kind": "weekly_scoped", "group": "weekly", "percent": 8, "resets_at": "2026-07-19T13:59:59+00:00", "scope": { "model": null } }
      ]
    }
    """)

    #expect(response.fableWeekly == nil)
  }

  /// Verbatim capture from `GET /api/oauth/usage`, 2026-07-16. Trimmed of no fields.
  private static let capturedPayload = """
  {
    "five_hour": {
      "utilization": 0.0,
      "resets_at": "2026-07-16T17:19:59.803331+00:00",
      "limit_dollars": null,
      "used_dollars": null,
      "remaining_dollars": null
    },
    "seven_day": {
      "utilization": 5.0,
      "resets_at": "2026-07-19T13:59:59.803355+00:00",
      "limit_dollars": null,
      "used_dollars": null,
      "remaining_dollars": null
    },
    "seven_day_oauth_apps": null,
    "seven_day_opus": null,
    "seven_day_sonnet": null,
    "seven_day_cowork": null,
    "seven_day_omelette": null,
    "tangelo": null,
    "iguana_necktie": null,
    "omelette_promotional": null,
    "nimbus_quill": null,
    "cinder_cove": null,
    "amber_ladder": null,
    "extra_usage": {
      "is_enabled": false,
      "monthly_limit": null,
      "used_credits": null,
      "utilization": null,
      "currency": null,
      "decimal_places": null,
      "disabled_reason": null,
      "daily": null,
      "weekly": null
    },
    "limits": [
      {
        "kind": "session",
        "group": "session",
        "percent": 0,
        "severity": "normal",
        "resets_at": "2026-07-16T17:19:59.803331+00:00",
        "scope": null,
        "is_active": false
      },
      {
        "kind": "weekly_all",
        "group": "weekly",
        "percent": 5,
        "severity": "normal",
        "resets_at": "2026-07-19T13:59:59.803355+00:00",
        "scope": null,
        "is_active": false
      },
      {
        "kind": "weekly_scoped",
        "group": "weekly",
        "percent": 8,
        "severity": "normal",
        "resets_at": "2026-07-19T13:59:59.803669+00:00",
        "scope": {
          "model": {
            "id": null,
            "display_name": "Fable"
          },
          "surface": null
        },
        "is_active": true
      }
    ],
    "spend": {
      "used": { "amount_minor": 0, "currency": "USD", "exponent": 2 },
      "limit": null,
      "percent": 0,
      "severity": "normal",
      "enabled": false,
      "disabled_reason": null,
      "cap": null,
      "balance": null,
      "auto_reload": null,
      "can_purchase_credits": false,
      "can_toggle": false
    },
    "member_dashboard_available": false
  }
  """
}

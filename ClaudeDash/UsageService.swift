import Foundation
import Observation

/// Fetches Claude usage data from the Anthropic API using OAuth credentials from the macOS Keychain.
@Observable
class UsageService {
  var usage: UsageResponse?
  var error: String?
  var lastUpdated: Date?

  private var timer: Timer?
  private let pollingInterval: TimeInterval = 60
  private let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
  private let oauthTokenURL = "https://platform.claude.com/v1/oauth/token"

  init() {
    fetchUsage()
    startPolling()
  }

  deinit {
    timer?.invalidate()
  }

  /// Starts the polling timer to refresh usage data every 60 seconds.
  func startPolling() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
      self?.fetchUsage()
    }
  }

  /// Kicks off an async usage fetch.
  func fetchUsage() {
    Task { await fetchUsageAsync() }
  }

  /// Fetches usage data from the API, automatically refreshing expired tokens.
  @MainActor
  private func fetchUsageAsync() async {
    guard var credentials = readOAuthCredentialsFromKeychain() else {
      error = "Auth required — sign in to Claude Code first"
      return
    }

    // Proactive refresh: if token expires within 5 minutes, refresh preemptively.
    if credentials.isExpired(buffer: 300) {
      if let refreshed = await refreshAccessToken(using: credentials) {
        credentials = refreshed
      } else {
        error = "Auth token expired — sign in to Claude Code again"
        return
      }
    }

    let result = await performUsageRequest(with: credentials)

    switch result {
    case .success(let response):
      usage = response
      error = nil
      lastUpdated = Date()

    case .failure(.unauthorized):
      // Reactive refresh: try once on 401.
      if let refreshed = await refreshAccessToken(using: credentials) {
        let retry = await performUsageRequest(with: refreshed)
        switch retry {
        case .success(let response):
          usage = response
          error = nil
          lastUpdated = Date()
        case .failure(let retryError):
          error = retryError.message
        }
      } else {
        error = "Auth expired or revoked — sign in to Claude Code again"
      }

    case .failure(let fetchError):
      error = fetchError.message
    }
  }

  // MARK: - API Request

  private enum FetchError: Error {
    case network(String)
    case invalidResponse
    case unauthorized
    case httpError(Int)
    case noData
    case parseFailed

    var message: String {
      switch self {
      case .network(let msg): return "Network error: \(msg)"
      case .invalidResponse: return "Invalid response"
      case .unauthorized: return "Auth expired or revoked — sign in to Claude Code again"
      case .httpError(let code): return "API error (HTTP \(code))"
      case .noData: return "No data received"
      case .parseFailed: return "Failed to parse response"
      }
    }
  }

  /// Performs the actual GET request to the usage API.
  private func performUsageRequest(with credentials: OAuthCredentials) async -> Result<UsageResponse, FetchError> {
    guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
      return .failure(.invalidResponse)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      return .failure(.network(error.localizedDescription))
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      return .failure(.invalidResponse)
    }

    if httpResponse.statusCode == 401 {
      return .failure(.unauthorized)
    }

    guard httpResponse.statusCode == 200 else {
      return .failure(.httpError(httpResponse.statusCode))
    }

    do {
      let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
      return .success(decoded)
    } catch {
      return .failure(.parseFailed)
    }
  }

  // MARK: - OAuth Credentials

  private struct OAuthCredentials {
    let accessToken: String
    let expiresAt: Date?
    let refreshToken: String?
    let rawJSON: [String: Any]

    /// Returns true if the token expires within the given buffer (in seconds).
    func isExpired(buffer: TimeInterval = 300) -> Bool {
      guard let expiresAt = expiresAt else { return false }
      return expiresAt <= Date().addingTimeInterval(buffer)
    }
  }

  /// Reads OAuth credentials from the macOS Keychain via the security CLI.
  private func readOAuthCredentialsFromKeychain() -> OAuthCredentials? {
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return nil
    }

    guard process.terminationStatus == 0 else { return nil }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
      return nil
    }

    guard let jsonData = raw.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
          let oauthEntry = json["claudeAiOauth"] as? [String: Any],
          let accessToken = oauthEntry["accessToken"] as? String else {
      return nil
    }

    let expiresAt = (oauthEntry["expiresAt"] as? NSNumber)
      .map { Date(timeIntervalSince1970: $0.doubleValue / 1000.0) }
    let refreshToken = oauthEntry["refreshToken"] as? String

    return OAuthCredentials(accessToken: accessToken, expiresAt: expiresAt, refreshToken: refreshToken, rawJSON: json)
  }

  // MARK: - Token Refresh

  /// Refreshes the access token using the refresh token, writes updated credentials to keychain.
  private func refreshAccessToken(using credentials: OAuthCredentials) async -> OAuthCredentials? {
    guard let refreshToken = credentials.refreshToken else { return nil }
    guard let url = URL(string: oauthTokenURL) else { return nil }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    var components = URLComponents()
    components.queryItems = [
      URLQueryItem(name: "grant_type", value: "refresh_token"),
      URLQueryItem(name: "refresh_token", value: refreshToken),
      URLQueryItem(name: "client_id", value: oauthClientID),
    ]
    request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      return nil
    }

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      return nil
    }

    guard let tokenResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let newAccessToken = tokenResponse["access_token"] as? String else {
      return nil
    }

    let newRefreshToken = tokenResponse["refresh_token"] as? String ?? refreshToken
    let expiresIn = tokenResponse["expires_in"] as? Double
    let newExpiresAt: Date? = expiresIn.map { Date().addingTimeInterval($0) }

    // Rebuild the keychain JSON, preserving all existing fields.
    var updatedJSON = credentials.rawJSON
    var updatedOAuth = (updatedJSON["claudeAiOauth"] as? [String: Any]) ?? [:]
    updatedOAuth["accessToken"] = newAccessToken
    updatedOAuth["refreshToken"] = newRefreshToken
    if let newExpiresAt = newExpiresAt {
      updatedOAuth["expiresAt"] = Int64(newExpiresAt.timeIntervalSince1970 * 1000.0)
    }
    updatedJSON["claudeAiOauth"] = updatedOAuth

    writeCredentialsToKeychain(updatedJSON)

    return OAuthCredentials(accessToken: newAccessToken, expiresAt: newExpiresAt, refreshToken: newRefreshToken, rawJSON: updatedJSON)
  }

  /// Writes updated credentials JSON back to the macOS Keychain.
  private func writeCredentialsToKeychain(_ json: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: json),
          let jsonString = String(data: data, encoding: .utf8) else {
      return
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = [
      "add-generic-password", "-U",
      "-s", "Claude Code-credentials",
      "-a", NSUserName(),
      "-w", jsonString,
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      // Non-fatal — the session still uses the refreshed tokens in memory.
    }
  }
}

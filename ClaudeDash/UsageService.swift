import Foundation
import Observation

/// Fetches Claude usage data from the Anthropic API using OAuth credentials from the macOS Keychain.
///
/// Reads initial credentials from keychain, then manages its own token refresh cycle in memory.
/// Never writes back to keychain — Claude Code owns that storage.
@Observable
class UsageService {
  var usage: UsageResponse?
  var error: String?
  var lastUpdated: Date?

  private var timer: Timer?
  private let pollingInterval: TimeInterval = 60
  private let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
  private let oauthTokenURL = "https://platform.claude.com/v1/oauth/token"

  /// In-memory credentials, refreshed independently of Claude Code.
  private var cachedCredentials: OAuthCredentials?

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

  /// Fetches usage data, using cached in-memory credentials and refreshing as needed.
  @MainActor
  private func fetchUsageAsync() async {
    // Use cached credentials if available, otherwise read from keychain.
    if cachedCredentials == nil {
      cachedCredentials = readOAuthCredentialsFromKeychain()
    }

    guard var credentials = cachedCredentials else {
      error = "Auth required — sign in to Claude Code first"
      return
    }

    // Proactive refresh: if token expires within 5 minutes, refresh preemptively.
    if credentials.isExpired(buffer: 300) {
      // Always re-read keychain first — another process may have refreshed the token.
      if let fresh = readOAuthCredentialsFromKeychain(), fresh.accessToken != credentials.accessToken {
        credentials = fresh
        cachedCredentials = fresh
      } else if let refreshed = await refreshAccessToken(using: credentials) {
        credentials = refreshed
        cachedCredentials = refreshed
      } else {
        error = "Token expired — run /login in Claude Code"
        cachedCredentials = nil
        return
      }
    }

    let result = await performUsageRequest(with: credentials.accessToken)

    switch result {
    case .success(let response):
      usage = response
      error = nil
      lastUpdated = Date()

    case .failure(let fetchError) where fetchError.mayBeStaleToken:
      // Try refreshing the token in memory.
      if let refreshed = await refreshAccessToken(using: credentials) {
        cachedCredentials = refreshed
        let retry = await performUsageRequest(with: refreshed.accessToken)
        switch retry {
        case .success(let response):
          usage = response
          error = nil
          lastUpdated = Date()
        case .failure(let retryError):
          error = retryError.message
        }
      } else {
        // Refresh failed — try re-reading keychain in case user ran /login.
        if let fresh = readOAuthCredentialsFromKeychain(), fresh.accessToken != credentials.accessToken {
          cachedCredentials = fresh
          let retry = await performUsageRequest(with: fresh.accessToken)
          switch retry {
          case .success(let response):
            usage = response
            error = nil
            lastUpdated = Date()
          case .failure(let retryError):
            error = retryError.message
          }
        } else {
          error = "Token expired — run /login in Claude Code"
          cachedCredentials = nil
        }
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
    case rateLimited
    case httpError(Int)
    case noData
    case parseFailed

    /// Whether this error suggests the token may be invalid and a keychain re-read could help.
    var mayBeStaleToken: Bool {
      switch self {
      case .unauthorized, .rateLimited: return true
      default: return false
      }
    }

    var message: String {
      switch self {
      case .network(let msg): return "Network error: \(msg)"
      case .invalidResponse: return "Invalid response"
      case .unauthorized: return "Auth expired or revoked — sign in to Claude Code again"
      case .rateLimited: return "Rate limited — token may be invalid, use Claude Code to refresh"
      case .httpError(let code): return "API error (HTTP \(code))"
      case .noData: return "No data received"
      case .parseFailed: return "Failed to parse response"
      }
    }
  }

  /// Performs the actual GET request to the usage API.
  private func performUsageRequest(with accessToken: String) async -> Result<UsageResponse, FetchError> {
    guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
      return .failure(.invalidResponse)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
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

    if httpResponse.statusCode == 429 {
      return .failure(.rateLimited)
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

    return OAuthCredentials(accessToken: accessToken, expiresAt: expiresAt, refreshToken: refreshToken)
  }

  // MARK: - Token Refresh

  /// Refreshes the access token using the refresh token. Keeps new credentials in memory only — never writes to keychain.
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

    return OAuthCredentials(accessToken: newAccessToken, expiresAt: newExpiresAt, refreshToken: newRefreshToken)
  }
}

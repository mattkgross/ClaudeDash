import Foundation
import Observation

/// Fetches Codex (OpenAI) usage data from the ChatGPT backend, using OAuth credentials stored at `~/.codex/auth.json`.
///
/// The Codex CLI manages its own token refresh and writes the refreshed token back to `auth.json`.
/// We rely on that — re-reading the file on every poll picks up newly refreshed tokens automatically.
/// If the file is missing, the section is hidden (the user hasn't installed Codex).
@Observable
class CodexUsageService {
  /// Most recent successful response. Nil until first fetch completes.
  var usage: CodexUsageResponse?
  /// Most recent error message, suitable for display. Nil when last fetch was successful.
  var error: String?
  /// Timestamp of the most recent successful fetch.
  var lastUpdated: Date?
  /// True iff `~/.codex/auth.json` exists. Drives whether the popover renders the Codex section.
  var isAvailable: Bool = false

  private var timer: Timer?
  private let pollingInterval: TimeInterval = 60
  private let usageURL = "https://chatgpt.com/backend-api/wham/usage"

  init() {
    refreshAvailability()
    if isAvailable {
      fetchUsage()
    }
    startPolling()
  }

  deinit {
    timer?.invalidate()
  }

  /// Starts the polling timer to refresh usage data every 60 seconds.
  func startPolling() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
      self?.refreshAvailability()
      if self?.isAvailable == true {
        self?.fetchUsage()
      }
    }
  }

  /// Kicks off an async usage fetch.
  func fetchUsage() {
    Task { await fetchUsageAsync() }
  }

  /// Updates `isAvailable` based on whether we can read the Codex auth file.
  /// Under App Sandbox, `FileManager.fileExists` returns false for paths outside the container even when
  /// our entitlement grants read access — so we determine availability by attempting a real read instead.
  private func refreshAvailability() {
    if readCodexCredentials() != nil {
      isAvailable = true
    } else {
      isAvailable = false
      usage = nil
      error = nil
    }
  }

  @MainActor
  private func fetchUsageAsync() async {
    guard let credentials = readCodexCredentials() else {
      error = "Sign in via `codex login`"
      return
    }

    let result = await performUsageRequest(accessToken: credentials.accessToken, accountID: credentials.accountID)

    switch result {
    case .success(let response):
      usage = response
      error = nil
      lastUpdated = Date()

    case .failure(let fetchError):
      // On 401, re-read auth.json once — Codex CLI may have refreshed since our last poll.
      if fetchError.mayBeStaleToken,
         let fresh = readCodexCredentials(),
         fresh.accessToken != credentials.accessToken {
        let retry = await performUsageRequest(accessToken: fresh.accessToken, accountID: fresh.accountID)
        switch retry {
        case .success(let response):
          usage = response
          error = nil
          lastUpdated = Date()
        case .failure(let retryError):
          error = retryError.message
        }
      } else {
        error = fetchError.message
      }
    }
  }

  // MARK: - API Request

  private enum FetchError: Error {
    case network(String)
    case invalidResponse
    case unauthorized
    case rateLimited
    case httpError(Int)
    case parseFailed

    /// Whether this error suggests the token may be invalid and a re-read of auth.json could help.
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
      case .unauthorized: return "Auth expired — run `codex login`"
      case .rateLimited: return "Rate limited by Codex backend"
      case .httpError(let code): return "Codex API error (HTTP \(code))"
      case .parseFailed: return "Failed to parse Codex response"
      }
    }
  }

  /// Performs the actual GET request to the Codex usage API.
  private func performUsageRequest(accessToken: String, accountID: String?) async -> Result<CodexUsageResponse, FetchError> {
    guard let url = URL(string: usageURL) else {
      return .failure(.invalidResponse)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    if let accountID {
      request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
    }
    let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    request.setValue("AgentDash/\(bundleVersion)", forHTTPHeaderField: "User-Agent")

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
      let decoded = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
      return .success(decoded)
    } catch {
      return .failure(.parseFailed)
    }
  }

  // MARK: - Auth file

  private struct CodexCredentials {
    let accessToken: String
    let accountID: String?
  }

  /// Resolves the absolute path to `~/.codex/auth.json`.
  /// Uses `getpwuid` because `NSHomeDirectory()` in a sandboxed app returns the container path
  /// (e.g. `~/Library/Containers/<bundle-id>/Data`), not the real user home.
  private func authJSONPath() -> String {
    if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
      return String(cString: home) + "/.codex/auth.json"
    }
    return NSHomeDirectory() + "/.codex/auth.json"
  }

  /// Reads credentials from `~/.codex/auth.json`. Read access is granted by the
  /// `temporary-exception.files.home-relative-path.read-only` entitlement.
  private func readCodexCredentials() -> CodexCredentials? {
    let url = URL(fileURLWithPath: authJSONPath())
    guard let data = try? Data(contentsOf: url) else { return nil }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tokens = json["tokens"] as? [String: Any],
          let accessToken = tokens["access_token"] as? String,
          !accessToken.isEmpty else {
      return nil
    }

    let accountID = tokens["account_id"] as? String
    return CodexCredentials(accessToken: accessToken, accountID: accountID)
  }
}

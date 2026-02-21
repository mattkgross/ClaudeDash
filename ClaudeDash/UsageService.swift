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

  init() {
    fetchUsage()
    startPolling()
  }

  deinit {
    timer?.invalidate()
  }

  /// Starts the polling timer to refresh usage data every 2 minutes.
  func startPolling() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
      self?.fetchUsage()
    }
  }

  /// Fetches usage data from the API.
  func fetchUsage() {
    guard let credentials = readOAuthCredentialsFromKeychain() else {
      error = "Auth required — sign in to Claude Code first"
      return
    }

    if let expiresAt = credentials.expiresAt, expiresAt <= Date() {
      error = "Auth token expired — sign in to Claude Code again"
      return
    }

    guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

    URLSession.shared.dataTask(with: request) { [weak self] data, response, networkError in
      DispatchQueue.main.async {
        if let networkError = networkError {
          self?.error = "Network error: \(networkError.localizedDescription)"
          return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
          self?.error = "Invalid response"
          return
        }

        guard httpResponse.statusCode == 200 else {
          if httpResponse.statusCode == 401 {
            self?.error = "Auth expired or revoked — sign in to Claude Code again"
          } else {
            self?.error = "API error (HTTP \(httpResponse.statusCode))"
          }
          return
        }

        guard let data = data else {
          self?.error = "No data received"
          return
        }

        do {
          let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
          self?.usage = decoded
          self?.error = nil
          self?.lastUpdated = Date()
        } catch {
          self?.error = "Failed to parse response"
        }
      }
    }.resume()
  }

  private struct OAuthCredentials {
    let accessToken: String
    let expiresAt: Date?
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

    // The keychain value is a JSON object; extract the OAuth access token.
    guard let jsonData = raw.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
          let oauthEntry = json["claudeAiOauth"] as? [String: Any],
          let accessToken = oauthEntry["accessToken"] as? String else {
      return nil
    }

    let expiresAt = (oauthEntry["expiresAt"] as? NSNumber)
      .map { Date(timeIntervalSince1970: $0.doubleValue / 1000.0) }

    return OAuthCredentials(accessToken: accessToken, expiresAt: expiresAt)
  }
}

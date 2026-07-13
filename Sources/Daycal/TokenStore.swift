import Foundation

struct OAuthToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiration: Date

    var isExpired: Bool {
        Date() >= expiration.addingTimeInterval(-60)
    }
}

@MainActor
final class TokenStore {
    private let tokenKey = "DaycalOAuthToken"
    private let userDefaults = UserDefaults.standard
    private var refreshTask: Task<OAuthToken, Error>?

    var hasToken: Bool {
        loadToken() != nil
    }

    func save(token: OAuthToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        userDefaults.set(data, forKey: tokenKey)
    }

    func loadToken() -> OAuthToken? {
        guard let data = userDefaults.data(forKey: tokenKey) else { return nil }
        return try? JSONDecoder().decode(OAuthToken.self, from: data)
    }

    func clear() {
        refreshTask?.cancel()
        refreshTask = nil
        userDefaults.removeObject(forKey: tokenKey)
    }

    func validToken() async throws -> OAuthToken {
        guard let token = loadToken() else {
            throw CalendarAuthError.missingToken
        }
        if !token.isExpired {
            return token
        }
        return try await refreshedToken()
    }

    /// Refreshes even if the access token looks valid — used when the API
    /// rejects a token before its stated expiration (e.g. revoked mid-flight).
    func refreshedToken() async throws -> OAuthToken {
        if let refreshTask {
            return try await refreshTask.value
        }

        guard let token = loadToken() else {
            throw CalendarAuthError.missingToken
        }
        guard !token.refreshToken.isEmpty else {
            clear()
            throw CalendarAuthError.reauthRequired
        }

        let task = Task {
            try await GoogleAuthService().refresh(token: token)
        }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            let refreshed = try await task.value
            save(token: refreshed)
            return refreshed
        } catch CalendarAuthError.reauthRequired {
            // The refresh token was rejected outright; a new sign-in is the
            // only way forward. Transient failures keep the token for retry.
            clear()
            throw CalendarAuthError.reauthRequired
        }
    }
}

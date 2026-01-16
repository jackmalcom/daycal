import Foundation

struct OAuthToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiration: Date

    var isExpired: Bool {
        Date() >= expiration.addingTimeInterval(-60)
    }
}

final class TokenStore {
    private let tokenKey = "DaycalOAuthToken"
    private let userDefaults = UserDefaults.standard

    var hasToken: Bool {
        loadToken() != nil
    }

    var hasValidToken: Bool {
        guard let token = loadToken() else { return false }
        return !token.isExpired
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
        userDefaults.removeObject(forKey: tokenKey)
    }

    func validToken() async throws -> OAuthToken {
        guard let token = loadToken() else {
            throw CalendarAuthError.missingToken
        }

        if token.isExpired {
            let refreshed = try await GoogleAuthService().refresh(token: token)
            save(token: refreshed)
            return refreshed
        }

        return token
    }
}

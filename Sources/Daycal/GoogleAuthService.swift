import Foundation
import AppKit

enum CalendarAuthError: Error, LocalizedError {
    case missingToken
    case invalidRedirect
    case tokenExchangeFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "No Google token available."
        case .invalidRedirect:
            return "Invalid redirect from Google."
        case .tokenExchangeFailed:
            return "Could not exchange authorization code."
        case .cancelled:
            return "Sign-in was cancelled."
        }
    }
}

final class GoogleAuthService: NSObject {
    private var authContinuation: CheckedContinuation<OAuthToken, Error>?
    private let redirectServer = RedirectServer()

    func signIn() async throws -> OAuthToken {
        let state = UUID().uuidString
        try redirectServer.start()
        let url = buildAuthURL(state: state)
        NSWorkspace.shared.open(url)

        return try await withCheckedThrowingContinuation { continuation in
            authContinuation = continuation
            AuthRedirectHandler.shared.start { [weak self] result in
                switch result {
                case .success(let code):
                    Task {
                        do {
                            let token = try await self?.exchangeCodeForToken(code: code)
                            self?.redirectServer.stop()
                            if let token {
                                continuation.resume(returning: token)
                            } else {
                                continuation.resume(throwing: CalendarAuthError.tokenExchangeFailed)
                            }
                        } catch {
                            self?.redirectServer.stop()
                            continuation.resume(throwing: error)
                        }
                    }
                case .failure(let error):
                    self?.redirectServer.stop()
                    continuation.resume(throwing: error)
                }
            }

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, self.redirectServer.isRunning else { return }
                self.redirectServer.stop()
                continuation.resume(throwing: CalendarAuthError.cancelled)
            }
        }
    }

    func refresh(token: OAuthToken) async throws -> OAuthToken {
        var request = URLRequest(url: GoogleOAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": GoogleOAuthConfig.clientID,
            "client_secret": GoogleOAuthConfig.clientSecret,
            "refresh_token": token.refreshToken,
            "grant_type": "refresh_token"
        ]
        request.httpBody = body
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CalendarAuthError.tokenExchangeFailed
        }

        let payload = try JSONDecoder().decode(TokenResponse.self, from: data)
        return OAuthToken(
            accessToken: payload.accessToken,
            refreshToken: token.refreshToken,
            expiration: Date().addingTimeInterval(TimeInterval(payload.expiresIn))
        )
    }

    private func buildAuthURL(state: String) -> URL {
        var components = URLComponents(url: GoogleOAuthConfig.authURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleOAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleOAuthConfig.calendarScope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state)
        ]
        return components.url!
    }

    private func exchangeCodeForToken(code: String) async throws -> OAuthToken {
        var request = URLRequest(url: GoogleOAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code": code,
            "client_id": GoogleOAuthConfig.clientID,
            "client_secret": GoogleOAuthConfig.clientSecret,
            "redirect_uri": GoogleOAuthConfig.redirectURI,
            "grant_type": "authorization_code"
        ]

        request.httpBody = body
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CalendarAuthError.tokenExchangeFailed
        }

        let payload = try JSONDecoder().decode(TokenResponse.self, from: data)
        return OAuthToken(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken ?? "",
            expiration: Date().addingTimeInterval(TimeInterval(payload.expiresIn))
        )
    }
}

private struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

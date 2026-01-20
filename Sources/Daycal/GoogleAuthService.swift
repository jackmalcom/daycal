import Foundation
import AppKit

enum CalendarAuthError: Error, LocalizedError {
    case missingToken
    case invalidRedirect
    case tokenExchangeFailed
    case cancelled
    case stateMismatch

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
        case .stateMismatch:
            return "Sign-in response did not match the request."
        }
    }
}


final class GoogleAuthService: NSObject {
    private var authContinuation: CheckedContinuation<OAuthToken, Error>?
    private let redirectServer = RedirectServer()

    private static func exchangeCodeForToken(code: String) async throws -> OAuthToken {
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

    func signIn() async throws -> OAuthToken {
        let state = UUID().uuidString
        try redirectServer.start()
        let server = redirectServer
        let url = buildAuthURL(state: state)
        NSWorkspace.shared.open(url)

        return try await withCheckedThrowingContinuation { continuation in
            authContinuation = continuation
            AuthRedirectHandler.shared.start { result in
                switch result {
                case .success(let response):
                    guard response.state == state else {
                        server.stop()
                        continuation.resume(throwing: CalendarAuthError.stateMismatch)
                        return
                    }
                    Task {
                        do {
                            let token = try await GoogleAuthService.exchangeCodeForToken(code: response.code)
                            server.stop()
                            continuation.resume(returning: token)
                        } catch {
                            server.stop()
                            continuation.resume(throwing: error)
                        }
                    }
                case .failure(let error):
                    server.stop()
                    continuation.resume(throwing: error)
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard server.isRunning else { return }
                server.stop()
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

import Foundation
import AppKit

enum CalendarAuthError: Error, LocalizedError, Equatable {
    case missingToken
    case invalidRedirect
    case tokenExchangeFailed
    case cancelled
    case stateMismatch
    case reauthRequired

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
        case .reauthRequired:
            return "Your Google session expired. Please sign in again."
        }
    }
}


final class GoogleAuthService: NSObject {
    /// One in-flight sign-in. Guarantees the continuation resumes exactly once
    /// even when the redirect, the timeout, and a restarted sign-in race.
    private final class SignInAttempt {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<OAuthToken, Error>?

        init(_ continuation: CheckedContinuation<OAuthToken, Error>) {
            self.continuation = continuation
        }

        func resume(_ result: Result<OAuthToken, Error>) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            switch result {
            case .success(let token):
                continuation?.resume(returning: token)
            case .failure(let error):
                continuation?.resume(throwing: error)
            }
        }
    }

    private let redirectServer = RedirectServer()
    private let attemptLock = NSLock()
    private var currentAttempt: SignInAttempt?

    private static func exchangeCodeForToken(code: String) async throws -> OAuthToken {
        let body = [
            "code": code,
            "client_id": GoogleOAuthConfig.clientID,
            "client_secret": GoogleOAuthConfig.clientSecret,
            "redirect_uri": GoogleOAuthConfig.redirectURI,
            "grant_type": "authorization_code"
        ]

        let (data, response) = try await URLSession.shared.data(for: tokenRequest(body: body))
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
        let url = buildAuthURL(state: state)

        return try await withCheckedThrowingContinuation { continuation in
            let attempt = SignInAttempt(continuation)
            attemptLock.lock()
            currentAttempt = attempt
            attemptLock.unlock()

            AuthRedirectHandler.shared.start { [weak self] result in
                switch result {
                case .success(let response):
                    guard response.state == state else {
                        self?.finish(attempt, with: .failure(CalendarAuthError.stateMismatch))
                        return
                    }
                    Task { [weak self] in
                        do {
                            let token = try await GoogleAuthService.exchangeCodeForToken(code: response.code)
                            self?.finish(attempt, with: .success(token))
                        } catch {
                            self?.finish(attempt, with: .failure(error))
                        }
                    }
                case .failure(let error):
                    self?.finish(attempt, with: .failure(error))
                }
            }

            NSWorkspace.shared.open(url)

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                self?.finish(attempt, with: .failure(CalendarAuthError.cancelled))
            }
        }
    }

    /// Resumes the attempt (at most once) and stops the redirect server unless
    /// a newer sign-in attempt has taken it over.
    private func finish(_ attempt: SignInAttempt, with result: Result<OAuthToken, Error>) {
        attempt.resume(result)
        attemptLock.lock()
        let isCurrent = currentAttempt === attempt
        if isCurrent {
            currentAttempt = nil
        }
        attemptLock.unlock()
        if isCurrent {
            redirectServer.stop()
        }
    }

    func refresh(token: OAuthToken) async throws -> OAuthToken {
        let body = [
            "client_id": GoogleOAuthConfig.clientID,
            "client_secret": GoogleOAuthConfig.clientSecret,
            "refresh_token": token.refreshToken,
            "grant_type": "refresh_token"
        ]

        let (data, response) = try await URLSession.shared.data(for: Self.tokenRequest(body: body))
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            // Only a rejected grant means the refresh token itself is dead and
            // the user must sign in again. Anything else (5xx, rate limits) is
            // transient — keep the token and retry later.
            if http.statusCode >= 500 {
                throw URLError(.badServerResponse)
            }
            let oauthError = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data)
            if oauthError?.error == "invalid_grant" {
                throw CalendarAuthError.reauthRequired
            }
            throw CalendarAuthError.tokenExchangeFailed
        }

        let payload = try JSONDecoder().decode(TokenResponse.self, from: data)
        return OAuthToken(
            accessToken: payload.accessToken,
            refreshToken: token.refreshToken,
            expiration: Date().addingTimeInterval(TimeInterval(payload.expiresIn))
        )
    }

    private static func tokenRequest(body: [String: String]) -> URLRequest {
        var request = URLRequest(url: GoogleOAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        return request
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

private struct OAuthErrorResponse: Codable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

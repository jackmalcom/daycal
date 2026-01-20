import Foundation

final class AuthRedirectHandler {
    struct AuthResponse {
        let code: String
        let state: String?
    }

    static let shared = AuthRedirectHandler()

    private var completion: ((Result<AuthResponse, Error>) -> Void)?

    private init() {}

    func start(completion: @escaping (Result<AuthResponse, Error>) -> Void) {
        self.completion = completion
    }

    func handle(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems,
              let code = items.first(where: { $0.name == "code" })?.value else {
            completion?(.failure(CalendarAuthError.invalidRedirect))
            completion = nil
            return
        }

        let state = items.first(where: { $0.name == "state" })?.value
        completion?(.success(AuthResponse(code: code, state: state)))
        completion = nil
    }
}

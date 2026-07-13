import Foundation

final class AuthRedirectHandler {
    struct AuthResponse {
        let code: String
        let state: String?
    }

    static let shared = AuthRedirectHandler()

    private let lock = NSLock()
    private var completion: ((Result<AuthResponse, Error>) -> Void)?

    private init() {}

    func start(completion: @escaping (Result<AuthResponse, Error>) -> Void) {
        lock.lock()
        let previous = self.completion
        self.completion = completion
        lock.unlock()
        // A restarted sign-in supersedes the old attempt; resolve it so its
        // continuation doesn't dangle forever.
        previous?(.failure(CalendarAuthError.cancelled))
    }

    func handle(url: URL) {
        lock.lock()
        let completion = self.completion
        self.completion = nil
        lock.unlock()
        guard let completion else { return }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems,
              let code = items.first(where: { $0.name == "code" })?.value else {
            completion(.failure(CalendarAuthError.invalidRedirect))
            return
        }

        let state = items.first(where: { $0.name == "state" })?.value
        completion(.success(AuthResponse(code: code, state: state)))
    }
}

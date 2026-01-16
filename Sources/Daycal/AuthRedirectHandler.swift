import Foundation

final class AuthRedirectHandler {
    static let shared = AuthRedirectHandler()

    private var completion: ((Result<String, Error>) -> Void)?

    private init() {}

    func start(completion: @escaping (Result<String, Error>) -> Void) {
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

        completion?(.success(code))
        completion = nil
    }
}

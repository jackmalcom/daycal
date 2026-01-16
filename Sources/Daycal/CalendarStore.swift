import Foundation
import Combine

@MainActor
final class CalendarStore: ObservableObject {
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var authState: AuthState = .signedOut
    @Published private(set) var isLoading = false

    private let tokenStore = TokenStore()
    private let calendarService = GoogleCalendarService()
    private let authService = GoogleAuthService()
    private var refreshTask: Task<Void, Never>?
    private var signInTask: Task<Void, Never>?

    enum AuthState {
        case signedOut
        case signingIn
        case signedIn
        case error(String)
    }

    init() {
        Task {
            if tokenStore.hasToken {
                authState = .signedIn
                await refreshEvents()
                scheduleAutoRefresh()
            } else {
                authState = .signedOut
            }
        }
    }

    func signIn() {
        signInTask?.cancel()
        authState = .signingIn
        signInTask = Task {
            do {
                let token = try await authService.signIn()
                tokenStore.save(token: token)
                authState = .signedIn
                await refreshEvents()
                scheduleAutoRefresh()
            } catch {
                if Task.isCancelled { return }
                authState = .error(error.localizedDescription)
            }
        }
    }

    func signOut() {
        signInTask?.cancel()
        signInTask = nil
        tokenStore.clear()
        authState = .signedOut
        events = []
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refreshEvents() async {
        guard tokenStore.hasValidToken else {
            authState = .signedOut
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let token = try await tokenStore.validToken()
            events = try await calendarService.fetchTodayEvents(token: token)
        } catch {
            if let authError = error as? CalendarAuthError, authError == .missingToken {
                authState = .signedOut
                return
            }
            authState = .error(error.localizedDescription)
        }
    }

    private func scheduleAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                await refreshEvents()
            }
        }
    }
}

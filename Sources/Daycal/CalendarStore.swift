import Foundation
import Combine
import Network

@MainActor
final class CalendarStore: ObservableObject {
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var authState: AuthState = .signedOut
    @Published private(set) var isLoading = false
    @Published private(set) var isOnline = true

    private let tokenStore = TokenStore()
    private let calendarService = GoogleCalendarService()
    private let authService = GoogleAuthService()
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "daycal.network")
    private var refreshTask: Task<Void, Never>?
    private var signInTask: Task<Void, Never>?

    enum AuthState: Equatable {
        case signedOut
        case signingIn
        case signedIn
        case offline
        case error(String)
    }

    init() {
        startNetworkMonitoring()
        Task {
            await restoreSession()
        }
    }

    private func restoreSession() async {
        do {
            _ = try await tokenStore.validToken()
            authState = .signedIn
            await refreshEvents()
            scheduleAutoRefresh()
        } catch {
            if isOfflineError(error) {
                if tokenStore.hasToken {
                    authState = .offline
                    scheduleAutoRefresh()
                } else {
                    authState = .signedOut
                }
                return
            }

            if let authError = error as? CalendarAuthError, authError == .missingToken {
                authState = .signedOut
            } else {
                authState = .error(error.localizedDescription)
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
                if isOfflineError(error) {
                    authState = tokenStore.hasToken ? .offline : .signedOut
                    return
                }
                if let authError = error as? CalendarAuthError, authError == .missingToken {
                    authState = .signedOut
                } else {
                    authState = .error(error.localizedDescription)
                }
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
        if !isOnline {
            if authState == .signedIn {
                authState = .offline
            }
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let token = try await tokenStore.validToken()
            events = try await calendarService.fetchTodayEvents(token: token)
            if authState == .offline {
                authState = .signedIn
            }
        } catch {
            if let authError = error as? CalendarAuthError, authError == .missingToken {
                authState = .signedOut
                return
            }
            if isOfflineError(error) {
                authState = .offline
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

    private func startNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let online = path.status == .satisfied
                guard online != self.isOnline else { return }
                self.isOnline = online

                if online {
                    if self.authState == .offline {
                        self.authState = .signedIn
                    }
                    await self.refreshEvents()
                    self.scheduleAutoRefresh()
                } else if self.authState == .signedIn {
                    self.authState = .offline
                }
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    private func isOfflineError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotConnectToHost,
             .cannotFindHost,
             .timedOut,
             .dnsLookupFailed,
             .dataNotAllowed:
            return true
        default:
            return false
        }
    }
}

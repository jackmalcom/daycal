import Foundation
import Combine
import Network
import AppKit

@MainActor
final class CalendarStore: ObservableObject {
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var authState: AuthState = .signedOut
    @Published private(set) var isLoading = false
    @Published private(set) var isOnline = true
    @Published private(set) var now = Date()
    @Published private(set) var lastSync: Date?

    private let tokenStore = TokenStore()
    private let calendarService = GoogleCalendarService()
    private let authService = GoogleAuthService()
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "daycal.network")
    private var refreshTask: Task<Void, Never>?
    private var signInTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    enum AuthState: Equatable {
        case signedOut
        case signingIn
        case signedIn
        case offline
        case error(String)
    }

    init() {
        startClock()
        startNetworkMonitoring()
        observeWake()
        Task {
            await restoreSession()
        }
    }

    private func restoreSession() async {
        guard tokenStore.hasToken else {
            authState = .signedOut
            return
        }
        // Trust the stored token until proven otherwise: refreshEvents demotes
        // to offline/signedOut as needed, so a dead network at launch never
        // blocks showing the signed-in UI.
        authState = isOnline ? .signedIn : .offline
        await refreshEvents()
        scheduleAutoRefresh()
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
                if Task.isCancelled || isCancellationError(error) {
                    return
                }
                if let authError = error as? CalendarAuthError, authError == .cancelled {
                    if authState == .signingIn {
                        authState = .signedOut
                    }
                    return
                }
                if isOfflineError(error) {
                    authState = tokenStore.hasToken ? .offline : .signedOut
                    return
                }
                if let authError = error as? CalendarAuthError,
                   authError == .missingToken || authError == .reauthRequired {
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
        lastSync = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refreshEvents() async {
        guard authState != .signedOut, authState != .signingIn else { return }

        if !isOnline {
            authState = tokenStore.hasToken ? .offline : .signedOut
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            var token = try await tokenStore.validToken()
            do {
                events = try await calendarService.fetchTodayEvents(token: token)
            } catch CalendarServiceError.unauthorized {
                // The access token was rejected before its stated expiration
                // (revocation, clock skew). Force one refresh and retry.
                token = try await tokenStore.refreshedToken()
                events = try await calendarService.fetchTodayEvents(token: token)
            }
            lastSync = Date()
            authState = .signedIn
        } catch {
            if isCancellationError(error) {
                return
            }
            if let authError = error as? CalendarAuthError,
               authError == .missingToken || authError == .reauthRequired {
                events = []
                authState = .signedOut
                return
            }
            if isOfflineError(error) {
                authState = tokenStore.hasToken ? .offline : .signedOut
                return
            }
            // Transient failure (5xx, rate limit, flaky wake-from-sleep
            // networking): keep the cached schedule and let the auto-refresh
            // loop retry. Only surface an error if there is nothing to show.
            if lastSync == nil && events.isEmpty {
                authState = .error(error.localizedDescription)
            }
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

    private func startClock() {
        clockTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
                now = Date()
            }
        }
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.now = Date()
                // Give the network stack a moment to come back up.
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self.refreshEvents()
            }
        }
    }

    private func startNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { @MainActor in
                await self.handlePathUpdate(path)
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    private func handlePathUpdate(_ path: NWPath) async {
        let online = path.status == .satisfied
        guard online != isOnline else { return }
        isOnline = online

        if online {
            await refreshEvents()
        } else if authState == .signedIn {
            authState = .offline
        }
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
             .dataNotAllowed,
             .internationalRoamingOff,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        return false
    }
}

extension CalendarStore: @unchecked Sendable {}

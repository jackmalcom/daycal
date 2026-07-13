import SwiftUI

struct EventsMenuView: View {
    @ObservedObject var calendarStore: CalendarStore
    @StateObject private var launchAtLoginManager = LaunchAtLoginManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch calendarStore.authState {
            case .signedOut:
                Text("Connect Google Calendar to get started.")
                Button("Sign In") {
                    calendarStore.signIn()
                }
            case .signingIn:
                Text("Waiting for Google sign-in...")
                Button("Restart Sign In") {
                    calendarStore.signIn()
                }
            case .signedIn, .offline:
                if calendarStore.authState == .offline {
                    Label("Offline — showing last synced schedule.", systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if calendarStore.isLoading && upcomingEvents.isEmpty {
                    Text("Loading today’s meetings...")
                } else if upcomingEvents.isEmpty {
                    Text("No more meetings today.")
                } else {
                    ForEach(upcomingEvents) { event in
                        HStack {
                            Button(action: {
                                openEvent(event)
                            }) {
                                VStack(alignment: .leading) {
                                    Text(event.title)
                                    Text(eventTimeText(event))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if let conferenceLink = event.conferenceLink {
                                Button(action: {
                                    openConference(conferenceLink)
                                }) {
                                    Image(systemName: "video")
                                        .frame(maxHeight: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                Divider()
                Toggle("Start on Login", isOn: $launchAtLoginManager.isEnabled)
                Divider()
                HStack(spacing: 8) {
                    Button {
                        Task {
                            await calendarStore.refreshEvents()
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        calendarStore.signOut()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "power")
                            Text("Quit")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            case .error(let message):
                Text("Error: \(message)")
                HStack(spacing: 8) {
                    Button("Try Again") {
                        calendarStore.signIn()
                    }
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
        .menuWindowResizing()
    }

    private var upcomingEvents: [CalendarEvent] {
        calendarStore.events.filter { $0.end > calendarStore.now && !$0.isWorkingLocation }
    }

    private func openEvent(_ event: CalendarEvent) {
        NSWorkspace.shared.open(event.htmlLink)
    }

    private func openConference(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func eventTimeText(_ event: CalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: event.start)) – \(formatter.string(from: event.end))"
    }
}

// MenuBarExtra's window style doesn't shrink its panel when the content gets
// smaller (e.g. after meetings pass while the menu is closed), leaving blank
// space. Measure the content's ideal size and resize the hosting panel to fit,
// keeping the top edge anchored under the status item.
private extension View {
    func menuWindowResizing() -> some View {
        modifier(MenuWindowResizing())
    }
}

private struct MenuWindowResizing: ViewModifier {
    @State private var window: NSWindow?
    @State private var contentSize: CGSize?

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                contentSize = size
                syncWindowSize()
            }
            .background(WindowFinder { newWindow in
                window = newWindow
                syncWindowSize()
            })
    }

    private func syncWindowSize() {
        guard let window, let contentSize,
              contentSize.width > 1, contentSize.height > 1 else { return }
        let target = window.frameRect(forContentRect: CGRect(origin: .zero, size: contentSize)).size
        var frame = window.frame
        guard abs(frame.width - target.width) > 0.5 || abs(frame.height - target.height) > 0.5 else { return }
        frame.origin.y += frame.height - target.height
        frame.size = target
        window.setFrame(frame, display: true)
    }
}

private struct WindowFinder: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: WindowTrackingView, context: Context) {
        nsView.onChange = onChange
    }

    final class WindowTrackingView: NSView {
        var onChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let window = self.window
            DispatchQueue.main.async { [weak self] in
                self?.onChange?(window)
            }
        }
    }
}

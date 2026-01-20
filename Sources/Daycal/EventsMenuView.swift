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
            case .signedIn:
                if calendarStore.isLoading {
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
        .frame(minWidth: 260)
    }

    private var upcomingEvents: [CalendarEvent] {
        calendarStore.events.filter { $0.end > Date() && !$0.isWorkingLocation }
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

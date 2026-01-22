import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var calendarStore: CalendarStore

    var body: some View {
        Text(labelText)
            .font(.system(size: 12, weight: .medium))
    }

    private var labelText: String {
        switch calendarStore.authState {
        case .signedIn:
            guard let nextEvent = nextRelevantEvent else {
                return "No meetings"
            }

            if nextEvent.isOngoing {
                return "\(nextEvent.title) - \(timeRemainingText(for: nextEvent)) left"
            }

            return "\(nextEvent.title) in \(timeUntilText(for: nextEvent))"
        case .signingIn:
            return "Signing in..."
        case .signedOut:
            return "Daycal"
        case .offline:
            return "Offline"
        case .error:
            return "Auth error"
        }
    }

    private var nextRelevantEvent: CalendarEvent? {
        calendarStore.events.first { $0.end > Date() && !$0.isWorkingLocation }
    }

    private func timeUntilText(for event: CalendarEvent) -> String {
        formatDuration(event.timeUntilStart)
    }

    private func timeRemainingText(for event: CalendarEvent) -> String {
        formatDuration(event.timeRemaining)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(interval / 60))
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remaining = minutes % 60
        if remaining == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remaining)m"
    }
}

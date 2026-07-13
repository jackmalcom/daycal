import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var calendarStore: CalendarStore

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: content.icon)
            if let text = content.text {
                Text(text)
                    .font(.system(size: 12, weight: .medium))
            }
        }
    }

    private var content: (icon: String, text: String?) {
        switch calendarStore.authState {
        case .signedIn, .offline:
            let now = calendarStore.now
            guard let event = nextRelevantEvent(at: now) else {
                return ("calendar", nil)
            }

            let icon = event.conferenceLink != nil ? "video.fill" : "calendar.badge.clock"
            let emoji = event.firstEmoji.map { "\($0) " } ?? ""

            if event.isOngoing(at: now) {
                return (icon, "\(emoji)\(formatDuration(event.timeRemaining(at: now))) left")
            }
            return (icon, "\(emoji)in \(formatDuration(event.timeUntilStart(at: now)))")
        case .signingIn:
            return ("calendar", "…")
        case .signedOut, .error:
            return ("calendar.badge.exclamationmark", nil)
        }
    }

    private func nextRelevantEvent(at date: Date) -> CalendarEvent? {
        calendarStore.events.first { $0.end > date && !$0.isWorkingLocation }
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

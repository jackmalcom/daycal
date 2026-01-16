import Foundation

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let htmlLink: URL
    let eventType: String?
    let conferenceLink: URL?

    var isOngoing: Bool {
        let now = Date()
        return start <= now && end > now
    }

    var isWorkingLocation: Bool {
        return eventType == "workingLocation"
    }

    var timeUntilStart: TimeInterval {
        max(0, start.timeIntervalSinceNow)
    }

    var timeRemaining: TimeInterval {
        max(0, end.timeIntervalSinceNow)
    }
}

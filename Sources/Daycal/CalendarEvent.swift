import Foundation

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let htmlLink: URL
    let eventType: String?
    let conferenceLink: URL?

    var isWorkingLocation: Bool {
        return eventType == "workingLocation"
    }

    var firstEmoji: Character? {
        title.first(where: \.isEmoji)
    }

    func isOngoing(at date: Date) -> Bool {
        start <= date && end > date
    }

    func timeUntilStart(at date: Date) -> TimeInterval {
        max(0, start.timeIntervalSince(date))
    }

    func timeRemaining(at date: Date) -> TimeInterval {
        max(0, end.timeIntervalSince(date))
    }
}

private extension Character {
    var isEmoji: Bool {
        guard let first = unicodeScalars.first else { return false }
        if first.properties.isEmojiPresentation { return true }
        // Multi-scalar emoji whose base scalar defaults to text presentation
        // (e.g. ❤️) carry U+FE0F or an emoji-presentation scalar.
        return unicodeScalars.count > 1 && unicodeScalars.contains {
            $0.properties.isEmojiPresentation || $0.value == 0xFE0F
        }
    }
}

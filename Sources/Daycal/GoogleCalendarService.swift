import Foundation

final class GoogleCalendarService {
    func fetchTodayEvents(token: OAuthToken) async throws -> [CalendarEvent] {
        let calendarURL = try makeEventsURL()
        var request = URLRequest(url: calendarURL)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CalendarAuthError.tokenExchangeFailed
        }

        let payload = try JSONDecoder().decode(CalendarResponse.self, from: data)
        return payload.items.compactMap { item -> CalendarEvent? in
            guard let start = item.start?.dateTime ?? item.start?.date,
                  let end = item.end?.dateTime ?? item.end?.date,
                  let htmlLinkString = item.htmlLink,
                  let htmlLink = URL(string: htmlLinkString) else {
                return nil
            }

            let resolvedEventType = item.eventType ?? (item.workingLocationProperties == nil ? nil : "workingLocation")
            let conferenceLink = item.conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" })?.uri
            return CalendarEvent(
                id: item.id,
                title: item.summary ?? "Untitled",
                start: start,
                end: end,
                htmlLink: htmlLink,
                eventType: resolvedEventType,
                conferenceLink: conferenceLink.flatMap(URL.init(string:))
            )
        }
        .sorted { $0.start < $1.start }
    }

    private func makeEventsURL() throws -> URL {
        let calendarID = "primary"
        let now = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            throw CalendarAuthError.tokenExchangeFailed
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.path = "/calendar/v3/calendars/\(calendarID)/events"
        components.queryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "timeMin", value: formatter.string(from: startOfDay)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: endOfDay))
        ]
        guard let url = components.url else {
            throw CalendarAuthError.tokenExchangeFailed
        }
        return url
    }
}

private struct CalendarResponse: Codable {
    let items: [CalendarItem]
}

private struct CalendarItem: Codable {
    let id: String
    let summary: String?
    let start: CalendarDate?
    let end: CalendarDate?
    let htmlLink: String?
    let eventType: String?
    let workingLocationProperties: WorkingLocationProperties?
    let conferenceData: ConferenceData?
}

private struct WorkingLocationProperties: Codable {
    let type: String?
}

private struct ConferenceData: Codable {
    let entryPoints: [ConferenceEntryPoint]?
}

private struct ConferenceEntryPoint: Codable {
    let entryPointType: String
    let uri: String
}

private struct CalendarDate: Codable {
    let dateTime: Date?
    let date: Date?

    private enum CodingKeys: String, CodingKey {
        case dateTime
        case date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let dateTimeString = try container.decodeIfPresent(String.self, forKey: .dateTime) {
            dateTime = CalendarDate.parseDateTime(dateTimeString)
        } else {
            dateTime = nil
        }

        if let dateString = try container.decodeIfPresent(String.self, forKey: .date) {
            date = CalendarDate.parseDate(dateString)
        } else {
            date = nil
        }
    }

    private static func parseDateTime(_ value: String) -> Date? {
        if let date = isoFormatterWithFractional.date(from: value) {
            return date
        }
        return isoFormatter.date(from: value)
    }

    private static func parseDate(_ value: String) -> Date? {
        return dateFormatter.date(from: value)
    }

    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

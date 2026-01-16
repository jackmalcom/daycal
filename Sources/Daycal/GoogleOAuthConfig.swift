import Foundation

struct GoogleOAuthConfig {
    static let clientID = "383261090717-9s4c84uuu69qmpb7i6irghf1lli3pskf.apps.googleusercontent.com"
    static let clientSecret = "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"
    static let redirectURI = "http://localhost:8765/oauth2redirect"

    static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    static let authURL = URL(string: "https://accounts.google.com/o/oauth2/auth")!
    static let calendarScope = "https://www.googleapis.com/auth/calendar.readonly"
}

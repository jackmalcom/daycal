import SwiftUI

@main
struct DaycalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var calendarStore = CalendarStore()

    var body: some Scene {
        MenuBarExtra {
            EventsMenuView(calendarStore: calendarStore)
        } label: {
            MenuBarLabelView(calendarStore: calendarStore)
        }
        .menuBarExtraStyle(.window)
    }
}

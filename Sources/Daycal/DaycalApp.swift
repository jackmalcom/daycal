import SwiftUI

@main
struct DaycalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var calendarStore = CalendarStore()
    @StateObject private var updateManager = UpdateManager()

    var body: some Scene {
        MenuBarExtra {
            EventsMenuView(calendarStore: calendarStore)
                .onAppear {
                    updateManager.start()
                }
        } label: {
            MenuBarLabelView(calendarStore: calendarStore)
        }
        .menuBarExtraStyle(.window)
    }
}

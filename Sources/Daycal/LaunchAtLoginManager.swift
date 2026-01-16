import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            setEnabled(isEnabled)
        }
    }

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            isEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}

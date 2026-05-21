import Foundation
import ServiceManagement

enum LaunchAtLoginManager {
    private static let preferenceKey = "launchAtLoginEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: preferenceKey) }
        set { UserDefaults.standard.set(newValue, forKey: preferenceKey) }
    }

    static var isRegisteredWithSystem: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        default:
            return false
        }
    }

    static func syncWithSystem() {
        guard isEnabled, !isRegisteredWithSystem else { return }
        _ = apply(enabled: true)
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        isEnabled = enabled
        return apply(enabled: enabled)
    }

    @discardableResult
    private static func apply(enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("ClipXS launch at login failed: \(error.localizedDescription)")
            if enabled {
                isEnabled = false
            }
            return false
        }
    }
}

import Foundation
import ServiceManagement

/// Launch-at-login toggle backed by `SMAppService.mainApp` (macOS 13+; REQUIREMENTS FR-17).
///
/// The login-item state lives entirely inside the Service Management database — there is no separate
/// preference to keep in sync, so `isEnabled` always reflects the source of truth. Registration works
/// under the App Sandbox, so this needs no rework for Phase 4.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Enables/disables the login item. Throws if Service Management refuses (e.g. the app is being
    /// run from a quarantined/translocated path); callers surface the error to the user.
    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled { try service.register() }
        } else {
            if service.status == .enabled { try service.unregister() }
        }
    }
}

import Cocoa
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let hotKey = HotKeyManager()
    private var overlay: SelectionOverlayController?
    private var editor: EditorWindowController?
    private var settingsWindow: SettingsWindowController?
    private var launchAtLoginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        registerHotKey()
        // Re-register live when the user changes the shortcut in Settings.
        NotificationCenter.default.addObserver(self, selector: #selector(registerHotKey),
                                               name: Settings.hotKeyChanged, object: nil)
    }

    /// (Re)registers the global hotkey from the persisted setting (default ⌘1), or unregisters it
    /// entirely if the user cleared the shortcut (capture then only via the menu bar).
    @objc private func registerHotKey() {
        let settings = Settings.shared
        guard settings.hasHotKey else {
            hotKey.unregister()
            return
        }
        hotKey.register(keyCode: settings.hotKeyCode,
                        modifiers: settings.hotKeyModifiers) { [weak self] in
            self?.beginCapture()
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder",
                                   accessibilityDescription: "ahdishot")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let capItem = NSMenuItem(title: "Capture Region", action: #selector(menuCapture), keyEquivalent: "")
        capItem.target = self
        menu.addItem(capItem)

        let folderItem = NSMenuItem(title: "Open Screenshots Folder", action: #selector(openFolder), keyEquivalent: "")
        folderItem.target = self
        menu.addItem(folderItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit ahdishot", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self // refresh the Launch-at-Login check state when the menu opens
        statusItem.menu = menu
    }

    /// Keep the Launch-at-Login check mark in sync with the actual login-item state each time the
    /// menu opens (it can change via Settings or System Settings).
    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let controller = SettingsWindowController()
            controller.onLaunchAtLoginChanged = { [weak self] in
                self?.launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
            }
            settingsWindow = controller
        }
        settingsWindow?.show()
    }

    @objc private func toggleLaunchAtLogin() {
        let enable = !LaunchAtLogin.isEnabled
        do {
            try LaunchAtLogin.setEnabled(enable)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't \(enable ? "enable" : "disable") launch at login"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func menuCapture() { beginCapture() }

    @objc private func openFolder() {
        if let dir = try? ScreenCapturer.saveDirectory() {
            NSWorkspace.shared.open(dir)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Capture flow

    private func beginCapture() {
        guard overlay == nil else { return } // already selecting
        let controller = SelectionOverlayController()
        overlay = controller
        controller.begin { [weak self] result in
            self?.overlay = nil
            guard let result = result else { return } // cancelled
            self?.handleSelection(screen: result.screen, rect: result.rect)
        }
    }

    private func handleSelection(screen: NSScreen, rect: NSRect) {
        Task { @MainActor in
            do {
                // Grab the whole display as a frozen frame, then open the inline editor over it.
                // Capturing the full display (not just the crop) is what lets the selection be
                // re-cropped/moved inside the editor, and sidesteps full-screen-Space overlay quirks.
                let image = try await ScreenCapturer.captureFullDisplay(screen: screen)
                self.presentEditor(image: image, screen: screen, selection: rect)
            } catch {
                self.presentCaptureError(error)
            }
        }
    }

    @MainActor
    private func presentEditor(image: CGImage, screen: NSScreen, selection: NSRect) {
        guard editor == nil else { return }
        let controller = EditorWindowController()
        editor = controller
        controller.present(image: image, screen: screen, selection: selection) { [weak self] in
            self?.editor = nil
        }
    }

    private func presentCaptureError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "ahdishot couldn't capture the screen"
        alert.informativeText = error.localizedDescription
            + "\n\nOn first run, grant Screen Recording permission in "
            + "System Settings ▸ Privacy & Security ▸ Screen Recording, then try again."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

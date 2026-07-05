import Cocoa
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotKey = HotKeyManager()
    private var overlay: SelectionOverlayController?
    private var editor: EditorWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        // Default hotkey: Cmd+1 (owner's choice; will be user-configurable in a later phase).
        hotKey.register(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(cmdKey)) { [weak self] in
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

        let aboutItem = NSMenuItem(title: "ahdishot (Phase 1)", action: nil, keyEquivalent: "")
        aboutItem.isEnabled = false
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit ahdishot", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
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

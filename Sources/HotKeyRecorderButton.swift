import Cocoa
import Carbon

/// A click-to-record shortcut field. Click it, press a key combination, and it reports the captured
/// Carbon `keyCode` + modifier mask (the exact pair `HotKeyManager.register` and `RegisterEventHotKey`
/// expect). While recording it installs a local event monitor so it can capture (and swallow) even
/// Command-based combos that the menu/window would otherwise treat as key equivalents.
///
/// A modifier is required — a bare key would shadow that key globally in every app, which we never
/// want. `Esc` cancels recording without changing the shortcut.
final class HotKeyRecorderButton: NSButton {
    /// Called with the captured Carbon keyCode + modifier mask when a valid combo is recorded.
    var onCapture: ((_ code: UInt32, _ modifiers: UInt32) -> Void)?

    private var isRecording = false
    private var monitor: Any?
    private var code: UInt32 = 0
    private var modifiers: UInt32 = 0

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows an existing shortcut without entering recording mode. Zero modifiers means "no hotkey"
    /// (the user cleared it) — shown as a prompt to set one.
    func display(code: UInt32, modifiers: UInt32) {
        self.code = code
        self.modifiers = modifiers
        title = modifiers == 0 ? "Click to set…"
                               : HotKeyRecorderButton.string(code: code, modifiers: modifiers)
    }

    @objc private func toggleRecording() {
        isRecording ? stopRecording(restoreTitle: true) : startRecording()
    }

    private func startRecording() {
        isRecording = true
        title = "Type shortcut…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handle(event)
            return nil // swallow the event so it doesn't fire menu/app shortcuts
        }
    }

    private func stopRecording(restoreTitle: Bool) {
        isRecording = false
        if let monitor = monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if restoreTitle { display(code: code, modifiers: modifiers) }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording(restoreTitle: true) // cancel, keep the current shortcut
            return
        }
        let mods = HotKeyRecorderButton.carbonModifiers(from: event.modifierFlags)
        guard mods != 0 else {
            NSSound.beep() // reject a bare key — it would hijack that key everywhere
            return
        }
        let newCode = UInt32(event.keyCode)
        stopRecording(restoreTitle: false)
        display(code: newCode, modifiers: mods)
        onCapture?(newCode, mods)
    }

    override var acceptsFirstResponder: Bool { false }

    // MARK: - Conversion & display

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        return m
    }

    /// Human-readable shortcut, e.g. `⌘1`, `⌥⇧4`. Modifier order matches macOS convention (⌃⌥⇧⌘).
    static func string(code: UInt32, modifiers: UInt32) -> String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += keyName(code)
        return s
    }

    private static func keyName(_ code: UInt32) -> String {
        if let name = keyNames[Int(code)] { return name }
        return "Key \(code)"
    }

    /// Virtual-keycode → label for the keys a shortcut is plausibly built from.
    private static let keyNames: [Int: String] = [
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_Grave: "`",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

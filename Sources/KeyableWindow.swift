import Cocoa

/// A borderless `NSWindow` that can still become key/main so its content view receives keyboard
/// events (Esc, ⌘Z). Plain borderless windows refuse key status by default, which is why the
/// Phase 1 overlay's Esc-to-cancel never fired. Used by both the selection overlay and the editor.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

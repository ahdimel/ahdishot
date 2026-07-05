import Cocoa

// ahdishot — native Apple Silicon screenshot tool.
// Phase 1: global hotkey -> region drag-select -> ScreenCaptureKit grab -> copy + auto-save PNG.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Agent app: no Dock icon, menu bar only (also set via LSUIElement in Info.plist).
app.setActivationPolicy(.accessory)
app.run()

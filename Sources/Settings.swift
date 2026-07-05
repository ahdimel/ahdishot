import Cocoa
import Carbon

/// Output image format (REQUIREMENTS §2/§3.4). Default PNG.
enum ImageFormat: String, CaseIterable {
    case png
    case jpg

    var fileExtension: String { rawValue }
    var displayName: String { self == .png ? "PNG" : "JPEG" }
}

/// App-wide persisted settings (REQUIREMENTS §3.5). Thin wrapper over `UserDefaults` plus a
/// notification so the hotkey can be re-registered live when it changes.
///
/// The save folder is stored as a **bookmark** (not a raw path): today a plain bookmark, but this
/// is the App-Store-ready entry point — Phase 4 swaps `bookmarkData()` / `URL(resolvingBookmarkData:)`
/// for their `.withSecurityScope` variants once the sandbox `user-selected.read-write` entitlement
/// is in place (REQUIREMENTS §9). Nothing else has to change.
final class Settings {
    static let shared = Settings()

    /// Posted when the global hotkey changes so `AppDelegate` re-registers it.
    static let hotKeyChanged = Notification.Name("ahdishot.hotKeyChanged")

    private let defaults = UserDefaults.standard

    private enum Key {
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let saveFolderBookmark = "saveFolderBookmark"
        static let imageFormat = "imageFormat"
        static let defaultColorIndex = "defaultColorIndex"
        static let defaultThickness = "defaultThickness"
        // Launch-at-login state is owned by SMAppService (see LaunchAtLogin), not mirrored here.
    }

    private init() {
        defaults.register(defaults: [
            Key.hotKeyCode: Int(kVK_ANSI_1),
            Key.hotKeyModifiers: Int(cmdKey),
            Key.imageFormat: ImageFormat.png.rawValue,
            Key.defaultColorIndex: 0,
            Key.defaultThickness: Double(thicknessSteps[1]), // medium
        ])
    }

    // MARK: - Global hotkey

    var hotKeyCode: UInt32 { UInt32(defaults.integer(forKey: Key.hotKeyCode)) }
    var hotKeyModifiers: UInt32 { UInt32(defaults.integer(forKey: Key.hotKeyModifiers)) }

    /// Whether a global hotkey is set. "None" is represented by **zero modifiers** (every valid hotkey
    /// requires ≥1 modifier), not by keyCode — keyCode 0 is a real key (`kVK_ANSI_A`). When there's no
    /// hotkey, capture is menu-bar-only.
    var hasHotKey: Bool { hotKeyModifiers != 0 }

    func setHotKey(code: UInt32, modifiers: UInt32) {
        defaults.set(Int(code), forKey: Key.hotKeyCode)
        defaults.set(Int(modifiers), forKey: Key.hotKeyModifiers)
        NotificationCenter.default.post(name: Settings.hotKeyChanged, object: nil)
    }

    /// Removes the global hotkey (capture then only via the menu bar).
    func clearHotKey() {
        defaults.set(0, forKey: Key.hotKeyCode)
        defaults.set(0, forKey: Key.hotKeyModifiers)
        NotificationCenter.default.post(name: Settings.hotKeyChanged, object: nil)
    }

    // MARK: - Image format

    var imageFormat: ImageFormat {
        get { ImageFormat(rawValue: defaults.string(forKey: Key.imageFormat) ?? "") ?? .png }
        set { defaults.set(newValue.rawValue, forKey: Key.imageFormat) }
    }

    // MARK: - Default annotation color & thickness

    var defaultColorIndex: Int {
        get { min(max(0, defaults.integer(forKey: Key.defaultColorIndex)), Palette.colors.count - 1) }
        set { defaults.set(min(max(0, newValue), Palette.colors.count - 1), forKey: Key.defaultColorIndex) }
    }

    var defaultColor: NSColor { Palette.colors[defaultColorIndex] }

    var defaultThickness: CGFloat {
        get {
            let stored = CGFloat(defaults.double(forKey: Key.defaultThickness))
            return thicknessSteps.contains(stored) ? stored : thicknessSteps[1]
        }
        set { defaults.set(Double(newValue), forKey: Key.defaultThickness) }
    }

    // MARK: - Save folder

    /// The folder screenshots are written to. Resolves the stored bookmark, falling back to the
    /// default `~/Pictures/ahdishot/` if unset or unresolvable (e.g. the folder was deleted).
    func saveFolderURL() -> URL {
        if let data = defaults.data(forKey: Key.saveFolderBookmark) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, relativeTo: nil,
                                  bookmarkDataIsStale: &stale) {
                return url
            }
        }
        return Settings.defaultSaveFolder
    }

    func setSaveFolder(_ url: URL) {
        if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil,
                                            relativeTo: nil) {
            defaults.set(data, forKey: Key.saveFolderBookmark)
        }
    }

    static var defaultSaveFolder: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
        return pictures.appendingPathComponent("ahdishot", isDirectory: true)
    }
}

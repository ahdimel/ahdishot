import Cocoa
import ScreenCaptureKit

enum CaptureError: Error, LocalizedError {
    case noDisplay
    case cropFailed
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .noDisplay:   return "Could not find the display to capture."
        case .cropFailed:  return "Failed to crop the captured image to the selection."
        case .encodeFailed: return "Failed to encode the captured image."
        }
    }
}

/// Captures a display via ScreenCaptureKit and crops to the selected region.
enum ScreenCapturer {

    /// Captures the entire `screen` at native (Retina) pixel resolution and returns the full
    /// display image. The editor keeps this frozen frame so the selection can be re-cropped or
    /// moved after the fact; export crops it via `crop(_:screen:localRect:)`.
    static func captureFullDisplay(screen: NSScreen) async throws -> CGImage {
        let scale = screen.backingScaleFactor
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
            ?? CGMainDisplayID()

        // Let the overlay windows leave the composite before we grab the screen.
        try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms

        let content = try await SCShareableContent.current
        guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int((screen.frame.width * scale).rounded())
        config.height = Int((screen.frame.height * scale).rounded())
        config.showsCursor = false
        config.scalesToFit = false
        config.captureResolution = .best

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Crops a full-display capture to `localRect`, given in the screen's local
    /// (bottom-left origin, points) space. Converts to the image's pixel, top-left-origin space.
    static func crop(_ fullImage: CGImage, screen: NSScreen, localRect: NSRect) throws -> CGImage {
        let scale = screen.backingScaleFactor
        let yTop = screen.frame.height - (localRect.origin.y + localRect.height)
        let cropRect = CGRect(
            x: (localRect.origin.x * scale).rounded(),
            y: (yTop * scale).rounded(),
            width: (localRect.width * scale).rounded(),
            height: (localRect.height * scale).rounded()
        )
        guard let cropped = fullImage.cropping(to: cropRect) else {
            throw CaptureError.cropFailed
        }
        return cropped
    }

    // MARK: - Output

    static func copyToClipboard(_ image: CGImage) {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])
        // Clipboard is always PNG (lossless, universally pasteable) regardless of the save format.
        if let data = encode(image, as: .png) {
            pasteboard.setData(data, forType: .png)
        }
    }

    /// Saves `image` to the configured folder using the configured format (PNG/JPG), with a
    /// timestamped filename (REQUIREMENTS FR-11).
    @discardableResult
    static func save(_ image: CGImage) throws -> URL {
        let format = Settings.shared.imageFormat
        guard let data = encode(image, as: format) else { throw CaptureError.encodeFailed }
        let url = try saveDirectory()
            .appendingPathComponent("ahdishot_\(timestamp()).\(format.fileExtension)")
        try data.write(to: url)
        return url
    }

    /// The user-configured save folder (default `~/Pictures/ahdishot/`), created if missing.
    static func saveDirectory() throws -> URL {
        let dir = Settings.shared.saveFolderURL()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Helpers

    private static func encode(_ image: CGImage, as format: ImageFormat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: image.width, height: image.height)
        switch format {
        case .png:
            return rep.representation(using: .png, properties: [:])
        case .jpg:
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_'at'_HH.mm.ss"
        return formatter.string(from: Date())
    }
}

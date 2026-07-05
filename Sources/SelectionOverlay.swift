import Cocoa

/// Result of a region selection: which screen it happened on, and the rect in that
/// screen's local (bottom-left origin, points) coordinate space.
struct SelectionResult {
    let screen: NSScreen
    let rect: NSRect
}

/// Puts a borderless dimmed overlay on every display and lets the user drag-select a region.
/// Calls `completion` once with a result, or `nil` if cancelled (Esc / zero-size drag).
final class SelectionOverlayController {
    private var windows: [NSWindow] = []
    private var completion: ((SelectionResult?) -> Void)?
    private var finished = false

    func begin(completion: @escaping (SelectionResult?) -> Void) {
        self.completion = completion

        for screen in NSScreen.screens {
            let window = KeyableWindow(contentRect: screen.frame,
                                       styleMask: .borderless,
                                       backing: .buffered,
                                       defer: false)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.owningScreen = screen
            view.onFinish = { [weak self] rect in self?.finish(screen: screen, rect: rect) }
            view.onCancel = { [weak self] in self?.finish(screen: nil, rect: nil) }
            window.contentView = view

            window.setFrame(screen.frame, display: true)
            windows.append(window)
            window.orderFrontRegardless()
        }

        NSApp.activate(ignoringOtherApps: true)
        // Make the first window key and route keystrokes to its view so Esc cancels (Phase 1 bug).
        if let first = windows.first {
            first.makeKeyAndOrderFront(nil)
            first.makeFirstResponder(first.contentView)
        }
    }

    private func finish(screen: NSScreen?, rect: NSRect?) {
        guard !finished else { return }
        finished = true

        for window in windows { window.orderOut(nil) }
        windows.removeAll()

        let result: SelectionResult?
        if let screen = screen, let rect = rect, rect.width >= 1, rect.height >= 1 {
            result = SelectionResult(screen: screen, rect: rect)
        } else {
            result = nil
        }

        let completion = self.completion
        self.completion = nil
        completion?(result)
    }
}

/// Draws the dimmed backdrop with a transparent "hole" for the current selection,
/// plus a border and a live pixel-dimensions readout. Handles the drag interaction.
final class SelectionView: NSView {
    weak var owningScreen: NSScreen?
    var onFinish: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var selectionRect: NSRect = .zero

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current else { return }

        NSColor(white: 0, alpha: 0.35).setFill()
        bounds.fill()

        guard selectionRect.width > 0, selectionRect.height > 0 else { return }

        // Punch a transparent hole so the real screen shows through the selection.
        ctx.compositingOperation = .clear
        selectionRect.fill()
        ctx.compositingOperation = .sourceOver

        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: selectionRect)
        border.lineWidth = 1
        border.stroke()

        drawDimensions(for: selectionRect)
    }

    private func drawDimensions(for rect: NSRect) {
        let scale = owningScreen?.backingScaleFactor ?? 1
        let pxW = Int((rect.width * scale).rounded())
        let pxH = Int((rect.height * scale).rounded())
        let text = "\(pxW) × \(pxH)"

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attrs)
        let pad: CGFloat = 5

        var origin = NSPoint(x: rect.minX, y: rect.maxY + pad)
        if origin.y + textSize.height > bounds.maxY - 2 {
            origin.y = rect.maxY - textSize.height - pad  // flip inside when near top edge
        }

        let bg = NSRect(x: origin.x - pad, y: origin.y - pad / 2,
                        width: textSize.width + pad * 2, height: textSize.height + pad)
        NSColor(white: 0, alpha: 0.6).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 3, yRadius: 3).fill()
        text.draw(at: origin, withAttributes: attrs)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        selectionRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        selectionRect = rect(from: start, to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = startPoint else { onCancel?(); return }
        let finalRect = rect(from: start, to: convert(event.locationInWindow, from: nil))
        startPoint = nil
        if finalRect.width >= 2, finalRect.height >= 2 {
            onFinish?(finalRect)
        } else {
            onCancel?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel?()
        }
    }

    private func rect(from a: NSPoint, to b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

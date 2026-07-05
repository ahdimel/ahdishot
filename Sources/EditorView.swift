import Cocoa

// MARK: - Shared tool vocabulary (used by EditorView and EditorToolbar)

/// The armed drawing tool. There is deliberately no "select" tool — the selection's handles and
/// border are always live, so you can move/resize the crop no matter which draw tool is active.
enum Tool: CaseIterable {
    case rectangle, ellipse, arrow, line, pencil, marker, text
}

/// The fixed color palette (REQUIREMENTS §5): red (default), orange, yellow, green, blue, purple,
/// black, white. Explicit sRGB values so exported PNGs are consistent across displays.
enum Palette {
    static let colors: [NSColor] = [
        NSColor(srgbRed: 0.90, green: 0.20, blue: 0.18, alpha: 1), // red
        NSColor(srgbRed: 0.98, green: 0.58, blue: 0.10, alpha: 1), // orange
        NSColor(srgbRed: 0.98, green: 0.82, blue: 0.12, alpha: 1), // yellow
        NSColor(srgbRed: 0.18, green: 0.70, blue: 0.28, alpha: 1), // green
        NSColor(srgbRed: 0.13, green: 0.45, blue: 0.95, alpha: 1), // blue
        NSColor(srgbRed: 0.60, green: 0.25, blue: 0.85, alpha: 1), // purple
        NSColor(srgbRed: 0.00, green: 0.00, blue: 0.00, alpha: 1), // black
        NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1), // white
    ]
    static let defaultColor = colors[0]
}

/// Stroke widths (thin / medium / thick), confirmed 2 / 4 / 6 pt.
let thicknessSteps: [CGFloat] = [2, 4, 6]

/// Wide text-size preset range (REQUIREMENTS §5).
let textSizePresets: [CGFloat] = [8, 10, 12, 14, 18, 24, 36, 48, 72, 96]

/// Per-tool remembered options (color, stroke width, text size). Each tool keeps its own.
struct ToolSettings {
    var color: NSColor = Palette.defaultColor
    var thickness: CGFloat = thicknessSteps[1] // medium
    var textSize: CGFloat = 24
}

// MARK: - EditorView

/// The editor canvas: draws the frozen full-display capture, dims everything outside the current
/// selection, hosts the annotation objects, and handles all mouse/keyboard interaction (drawing,
/// moving/resizing the crop, text entry). Non-flipped so its point space matches `NSScreen`.
final class EditorView: NSView {
    private let displayImage: NSImage
    private let displayCGImage: CGImage
    let owningScreen: NSScreen

    private(set) var selectionRect: NSRect
    private var annotations: [Annotation] = []

    var activeTool: Tool = .rectangle
    private var settingsByTool: [Tool: ToolSettings] = [:]

    /// Fired whenever the selection moves/resizes so the toolbar can reposition.
    var onSelectionChanged: (() -> Void)?
    /// Fired for Esc / close.
    var onDismiss: (() -> Void)?

    // Interaction state
    private enum DragMode {
        case none
        case drawing(Annotation)
        case moveSelection
        case resizeSelection(Handle)
    }
    private enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }
    private var dragMode: DragMode = .none
    private var lastPoint: NSPoint = .zero

    // Active text entry
    private var activeTextField: NSTextField?
    private var pendingTextSize: CGFloat = 24
    private var pendingTextColor: NSColor = Palette.defaultColor

    init(image: CGImage, screen: NSScreen, selection: NSRect) {
        self.displayCGImage = image
        self.owningScreen = screen
        self.displayImage = NSImage(cgImage: image,
                                    size: NSSize(width: screen.frame.width, height: screen.frame.height))
        self.selectionRect = selection
        // Seed every tool with the user's configured default color/thickness (REQUIREMENTS FR-16);
        // each tool then remembers its own edits from there.
        var defaults = ToolSettings()
        defaults.color = Settings.shared.defaultColor
        defaults.thickness = Settings.shared.defaultThickness
        for tool in Tool.allCases { settingsByTool[tool] = defaults }
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Tool settings access (for the toolbar)

    func settings(for tool: Tool) -> ToolSettings { settingsByTool[tool] ?? ToolSettings() }
    func setColor(_ color: NSColor, for tool: Tool) { settingsByTool[tool]?.color = color }
    func setThickness(_ thickness: CGFloat, for tool: Tool) { settingsByTool[tool]?.thickness = thickness }
    func setTextSize(_ size: CGFloat, for tool: Tool) { settingsByTool[tool]?.textSize = size }

    private var activeSettings: ToolSettings { settings(for: activeTool) }

    // MARK: Undo

    func undo() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        // 1. The frozen capture.
        displayImage.draw(in: bounds)

        // 2. Dim everything outside the selection (even-odd punches the selection out).
        let dim = NSBezierPath(rect: bounds)
        dim.append(NSBezierPath(rect: selectionRect))
        dim.windingRule = .evenOdd
        NSColor(white: 0, alpha: 0.35).setFill()
        dim.fill()

        // 3. Annotations, clipped to the selection (matches "clipped, not scaled, on export").
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selectionRect).setClip()
        for annotation in annotations { annotation.draw() }
        NSGraphicsContext.restoreGraphicsState()

        // 4. Selection chrome.
        drawSelectionChrome()
    }

    private func drawSelectionChrome() {
        NSColor.white.withAlphaComponent(0.95).setStroke()
        let border = NSBezierPath(rect: selectionRect)
        border.lineWidth = 1
        border.stroke()

        for point in handlePositions().values {
            let box = NSRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            NSColor.white.setFill()
            NSColor(white: 0.3, alpha: 1).setStroke()
            let path = NSBezierPath(rect: box)
            path.fill()
            path.lineWidth = 1
            path.stroke()
        }

        drawDimensions()
    }

    private func drawDimensions() {
        let scale = owningScreen.backingScaleFactor
        let pxW = Int((selectionRect.width * scale).rounded())
        let pxH = Int((selectionRect.height * scale).rounded())
        let text = "\(pxW) × \(pxH)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attrs)
        let pad: CGFloat = 5
        var origin = NSPoint(x: selectionRect.minX, y: selectionRect.maxY + pad)
        if origin.y + size.height > bounds.maxY - 2 {
            origin.y = selectionRect.maxY - size.height - pad
        }
        let bg = NSRect(x: origin.x - pad, y: origin.y - pad / 2,
                        width: size.width + pad * 2, height: size.height + pad)
        NSColor(white: 0, alpha: 0.6).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 3, yRadius: 3).fill()
        text.draw(at: origin, withAttributes: attrs)
    }

    // MARK: Selection geometry

    private func handlePositions() -> [Handle: NSPoint] {
        let r = selectionRect
        return [
            .bottomLeft: NSPoint(x: r.minX, y: r.minY),
            .bottom: NSPoint(x: r.midX, y: r.minY),
            .bottomRight: NSPoint(x: r.maxX, y: r.minY),
            .right: NSPoint(x: r.maxX, y: r.midY),
            .topRight: NSPoint(x: r.maxX, y: r.maxY),
            .top: NSPoint(x: r.midX, y: r.maxY),
            .topLeft: NSPoint(x: r.minX, y: r.maxY),
            .left: NSPoint(x: r.minX, y: r.midY),
        ]
    }

    private func handle(at p: NSPoint) -> Handle? {
        let tol: CGFloat = 8
        for (handle, pt) in handlePositions() where abs(p.x - pt.x) <= tol && abs(p.y - pt.y) <= tol {
            return handle
        }
        return nil
    }

    /// True on the selection's border band (for moving), excluding the handle hot-spots.
    private func onBorder(_ p: NSPoint) -> Bool {
        guard handle(at: p) == nil else { return false }
        let outer = selectionRect.insetBy(dx: -6, dy: -6)
        let inner = selectionRect.insetBy(dx: 6, dy: 6)
        return outer.contains(p) && !inner.contains(p)
    }

    private func clampToBounds(_ point: NSPoint) -> NSPoint {
        NSPoint(x: min(max(0, point.x), bounds.width),
                y: min(max(0, point.y), bounds.height))
    }

    private func resizeSelection(_ handle: Handle, to raw: NSPoint) {
        let p = clampToBounds(raw)
        let r = selectionRect
        var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        switch handle {
        case .left, .topLeft, .bottomLeft: minX = p.x
        default: break
        }
        switch handle {
        case .right, .topRight, .bottomRight: maxX = p.x
        default: break
        }
        switch handle {
        case .bottom, .bottomLeft, .bottomRight: minY = p.y
        default: break
        }
        switch handle {
        case .top, .topLeft, .topRight: maxY = p.y
        default: break
        }
        let minSize: CGFloat = 10
        let newRect = NSRect(x: min(minX, maxX), y: min(minY, maxY),
                             width: max(minSize, abs(maxX - minX)),
                             height: max(minSize, abs(maxY - minY)))
        selectionRect = newRect
        onSelectionChanged?()
        needsDisplay = true
    }

    private func moveSelection(by delta: NSPoint) {
        var r = selectionRect.offsetBy(dx: delta.x, dy: delta.y)
        r.origin.x = min(max(0, r.origin.x), bounds.width - r.width)
        r.origin.y = min(max(0, r.origin.y), bounds.height - r.height)
        selectionRect = r
        onSelectionChanged?()
        needsDisplay = true
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        // A pending text field commits on any click elsewhere.
        if activeTextField != nil {
            commitActiveText()
            return
        }

        let p = convert(event.locationInWindow, from: nil)
        lastPoint = p

        if let handle = handle(at: p) {
            dragMode = .resizeSelection(handle)
            return
        }
        if onBorder(p) {
            dragMode = .moveSelection
            return
        }
        guard selectionRect.contains(p) else {
            dragMode = .none // clicks outside the crop do nothing
            return
        }

        if activeTool == .text {
            placeTextField(at: p)
            dragMode = .none
            return
        }
        beginDrawing(at: p)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch dragMode {
        case .resizeSelection(let handle):
            resizeSelection(handle, to: p)
        case .moveSelection:
            moveSelection(by: NSPoint(x: p.x - lastPoint.x, y: p.y - lastPoint.y))
            lastPoint = p
        case .drawing(let annotation):
            switch annotation {
            case let two as TwoPointAnnotation: two.end = p
            case let free as FreehandAnnotation: free.add(p)
            default: break
            }
            needsDisplay = true
        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        // Drop accidental zero-length two-point shapes (a click, not a drag).
        if case .drawing(let annotation) = dragMode,
           let two = annotation as? TwoPointAnnotation,
           hypot(two.end.x - two.start.x, two.end.y - two.start.y) < 3 {
            removeLastIfPresent(annotation)
            needsDisplay = true
        }
        dragMode = .none
    }

    private func beginDrawing(at p: NSPoint) {
        let s = activeSettings
        let annotation: Annotation
        switch activeTool {
        case .rectangle: annotation = RectangleAnnotation(start: p, end: p, color: s.color, thickness: s.thickness)
        case .ellipse:   annotation = EllipseAnnotation(start: p, end: p, color: s.color, thickness: s.thickness)
        case .line:      annotation = LineAnnotation(start: p, end: p, color: s.color, thickness: s.thickness)
        case .arrow:     annotation = ArrowAnnotation(start: p, end: p, color: s.color, thickness: s.thickness)
        case .pencil:    annotation = FreehandAnnotation(start: p, color: s.color, thickness: s.thickness)
        case .marker:    annotation = FreehandAnnotation(start: p,
                                                         color: s.color.withAlphaComponent(0.4),
                                                         thickness: s.thickness * 4)
        case .text:      return // handled separately
        }
        annotations.append(annotation)
        dragMode = .drawing(annotation)
        needsDisplay = true
    }

    private func removeLastIfPresent(_ annotation: Annotation) {
        if annotations.last === annotation { annotations.removeLast() }
    }

    // MARK: Text entry

    private func placeTextField(at p: NSPoint) {
        let s = activeSettings
        pendingTextSize = s.textSize
        pendingTextColor = s.color

        let field = NSTextField(frame: NSRect(x: p.x, y: p.y, width: 320, height: s.textSize * 1.5))
        field.font = NSFont.systemFont(ofSize: s.textSize)
        field.textColor = s.color
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = "Text…"
        field.target = self
        field.action = #selector(textFieldCommitted)
        addSubview(field)
        activeTextField = field
        window?.makeFirstResponder(field)
    }

    @objc private func textFieldCommitted() { commitActiveText() }

    private func commitActiveText() {
        guard let field = activeTextField else { return }
        let string = field.stringValue
        let frameOrigin = field.frame.origin
        field.removeFromSuperview()
        activeTextField = nil
        window?.makeFirstResponder(self)

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Nudge to roughly match the field's text baseline (NSTextField has a small inset).
        let origin = NSPoint(x: frameOrigin.x + 2, y: frameOrigin.y + 3)
        annotations.append(TextAnnotation(text: string, origin: origin,
                                          fontSize: pendingTextSize, color: pendingTextColor))
        needsDisplay = true
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            if activeTextField != nil {
                cancelActiveText()
            } else {
                onDismiss?()
            }
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            undo()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func cancelActiveText() {
        activeTextField?.removeFromSuperview()
        activeTextField = nil
        window?.makeFirstResponder(self)
    }

    // MARK: Export

    /// Rasterizes the current selection with its annotations baked in, at native pixel resolution.
    func flatten() -> CGImage? {
        commitActiveText() // fold any in-progress text before exporting

        guard let background = try? ScreenCapturer.crop(displayCGImage, screen: owningScreen,
                                                        localRect: selectionRect) else { return nil }
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: background.width, pixelsHigh: background.height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = selectionRect.size // points; the rep scales up to its pixel backing
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx

        NSImage(cgImage: background, size: selectionRect.size)
            .draw(in: NSRect(origin: .zero, size: selectionRect.size))

        // Shift view-space coordinates into the crop's origin, then clip to the selection.
        let xform = NSAffineTransform()
        xform.translateX(by: -selectionRect.origin.x, yBy: -selectionRect.origin.y)
        xform.concat()
        NSBezierPath(rect: selectionRect).setClip()
        for annotation in annotations { annotation.draw() }

        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
}

import Cocoa

/// A non-destructive annotation drawn on top of the captured image. Objects are stored in an
/// ordered list on the editor (undo = remove the last one) and rasterized on export.
///
/// All geometry is stored in the **editor view's point space** (non-flipped, bottom-left origin,
/// 1:1 with the full display). Because coordinates are absolute in that space, moving or
/// re-cropping the selection never moves an annotation — it only changes what's exported.
/// `draw()` renders into whatever `NSGraphicsContext` is current (the live view or the flatten
/// bitmap), so the same code paints both.
protocol Annotation: AnyObject {
    func draw()
}

// MARK: - Two-point shapes (rectangle, ellipse, line, arrow)

/// Shared base for annotations defined by a start and an end drag point.
class TwoPointAnnotation: Annotation {
    var start: NSPoint
    var end: NSPoint
    let color: NSColor
    let thickness: CGFloat

    init(start: NSPoint, end: NSPoint, color: NSColor, thickness: CGFloat) {
        self.start = start
        self.end = end
        self.color = color
        self.thickness = thickness
    }

    /// Normalized bounding rect of the two points.
    var rect: NSRect {
        NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(start.x - end.x), height: abs(start.y - end.y))
    }

    func draw() {}
}

final class RectangleAnnotation: TwoPointAnnotation {
    override func draw() {
        color.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = thickness
        path.stroke()
    }
}

final class EllipseAnnotation: TwoPointAnnotation {
    override func draw() {
        color.setStroke()
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = thickness
        path.stroke()
    }
}

final class LineAnnotation: TwoPointAnnotation {
    override func draw() {
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = thickness
        path.lineCapStyle = .round
        path.stroke()
    }
}

final class ArrowAnnotation: TwoPointAnnotation {
    override func draw() {
        color.setStroke()
        color.setFill()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(12, thickness * 4)
        let headAngle: CGFloat = .pi / 6 // 30°

        // Shaft (stop a little short so the round cap doesn't poke through the head).
        let shaftEnd = NSPoint(x: end.x - cos(angle) * headLength * 0.6,
                               y: end.y - sin(angle) * headLength * 0.6)
        let shaft = NSBezierPath()
        shaft.move(to: start)
        shaft.line(to: shaftEnd)
        shaft.lineWidth = thickness
        shaft.lineCapStyle = .round
        shaft.stroke()

        // Filled arrowhead.
        let p1 = NSPoint(x: end.x - headLength * cos(angle - headAngle),
                         y: end.y - headLength * sin(angle - headAngle))
        let p2 = NSPoint(x: end.x - headLength * cos(angle + headAngle),
                         y: end.y - headLength * sin(angle + headAngle))
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: p1)
        head.line(to: p2)
        head.close()
        head.fill()
    }
}

// MARK: - Freehand (pencil, marker)

/// Freehand stroke through a list of points. Used for the pencil (opaque) and, with a translucent
/// color and wider width, the marker/highlighter. Drawn as a single path so a translucent marker
/// keeps uniform alpha instead of darkening where the stroke crosses itself.
final class FreehandAnnotation: Annotation {
    private(set) var points: [NSPoint]
    let color: NSColor
    let thickness: CGFloat

    init(start: NSPoint, color: NSColor, thickness: CGFloat) {
        self.points = [start]
        self.color = color
        self.thickness = thickness
    }

    func add(_ point: NSPoint) { points.append(point) }

    func draw() {
        guard let first = points.first else { return }
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: first)
        for point in points.dropFirst() { path.line(to: point) }
        // A lone click (no drag) still shows a dot.
        if points.count == 1 { path.line(to: first) }
        path.lineWidth = thickness
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
}

// MARK: - Text

final class TextAnnotation: Annotation {
    var text: String
    let origin: NSPoint // bottom-left of the text in view point space
    let fontSize: CGFloat
    let color: NSColor

    init(text: String, origin: NSPoint, fontSize: CGFloat, color: NSColor) {
        self.text = text
        self.origin = origin
        self.fontSize = fontSize
        self.color = color
    }

    var attributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: color]
    }

    func draw() {
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}

import Cocoa

/// The single combined bottom toolbar (REQUIREMENTS §4): draw tools + undo on the left, a
/// separator, then the Copy / Save / Close actions. Lives as a subview of the editor canvas and
/// repositions itself just outside the selection's bottom edge (flipping above when there's no
/// room). Selecting a draw tool opens a tool-options popover anchored to its button.
final class EditorToolbar: NSView {
    private weak var editorView: EditorView?

    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?

    private let toolOrder: [(Tool, String)] = [
        (.rectangle, "rectangle"),
        (.ellipse, "circle"),
        (.arrow, "arrow.up.right"),
        (.line, "line.diagonal"),
        (.pencil, "pencil"),
        (.marker, "highlighter"),
        (.text, "textformat"),
    ]
    private var toolButtons: [Tool: NSButton] = [:]

    private var popover: NSPopover?
    private var popoverTool: Tool?

    private let buttonSize: CGFloat = 30
    private let spacing: CGFloat = 3
    private let padding: CGFloat = 7
    private let separatorWidth: CGFloat = 11

    init(editorView: EditorView) {
        self.editorView = editorView
        super.init(frame: .zero)
        buildButtons()
        highlightActiveTool()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { false }

    // MARK: Build

    private func buildButtons() {
        var x = padding
        let y = padding

        for (tool, symbol) in toolOrder {
            let button = makeButton(symbol: symbol, action: #selector(toolButtonClicked))
            button.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
            addSubview(button)
            toolButtons[tool] = button
            x += buttonSize + spacing
        }

        let undo = makeButton(symbol: "arrow.uturn.backward", action: #selector(undoClicked))
        undo.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        addSubview(undo)
        x += buttonSize + spacing

        // Separator between draw tools and actions.
        let sepX = x + (separatorWidth - 1) / 2
        let separator = NSBox(frame: NSRect(x: sepX, y: y + 4, width: 1, height: buttonSize - 8))
        separator.boxType = .separator
        addSubview(separator)
        x += separatorWidth + spacing

        for (symbol, action) in [("doc.on.doc", #selector(copyClicked)),
                                 ("square.and.arrow.down", #selector(saveClicked)),
                                 ("xmark", #selector(closeClicked))] {
            let button = makeButton(symbol: symbol, action: action)
            button.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
            addSubview(button)
            x += buttonSize + spacing
        }

        let totalWidth = x - spacing + padding
        setFrameSize(NSSize(width: totalWidth, height: buttonSize + padding * 2))
    }

    private func makeButton(symbol: String, action: Selector) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        button.contentTintColor = .white
        button.target = self
        button.action = action
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        return button
    }

    // MARK: Background

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        NSColor(white: 0.12, alpha: 0.96).setFill()
        bg.fill()
        NSColor(white: 1, alpha: 0.12).setStroke()
        bg.lineWidth = 1
        bg.stroke()
    }

    // MARK: Actions

    @objc private func toolButtonClicked(_ sender: NSButton) {
        guard let tool = toolButtons.first(where: { $0.value === sender })?.key,
              let editorView = editorView else { return }

        // Toggle the popover off if the same tool is clicked while its options are showing.
        if popover?.isShown == true, popoverTool == tool {
            closePopover()
            return
        }

        editorView.activeTool = tool
        highlightActiveTool()
        showOptionsPopover(for: tool, anchor: sender)
    }

    @objc private func undoClicked() { closePopover(); editorView?.undo() }
    @objc private func copyClicked() { closePopover(); onCopy?() }
    @objc private func saveClicked() { closePopover(); onSave?() }
    @objc private func closeClicked() { closePopover(); onClose?() }

    private func highlightActiveTool() {
        for (tool, button) in toolButtons {
            let active = (tool == editorView?.activeTool)
            button.layer?.backgroundColor = active
                ? NSColor(white: 1, alpha: 0.22).cgColor
                : NSColor.clear.cgColor
        }
    }

    // MARK: Popover

    private func showOptionsPopover(for tool: Tool, anchor: NSButton) {
        closePopover()
        guard let editorView = editorView else { return }

        let controller = ToolOptionsController(tool: tool,
                                               settings: editorView.settings(for: tool),
                                               showTextSize: tool == .text)
        controller.onColor = { [weak editorView] color in editorView?.setColor(color, for: tool) }
        controller.onThickness = { [weak editorView] thickness in editorView?.setThickness(thickness, for: tool) }
        controller.onTextSize = { [weak editorView] size in editorView?.setTextSize(size, for: tool) }

        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        self.popover = popover
        self.popoverTool = tool
    }

    private func closePopover() {
        popover?.close()
        popover = nil
        popoverTool = nil
    }

    // MARK: Positioning

    /// Places the toolbar centered just below the selection, flipping above it when there's no
    /// room, and clamped to stay fully on-screen.
    func reposition(around selection: NSRect, in container: NSRect) {
        let size = frame.size
        var x = selection.midX - size.width / 2
        x = min(max(8, x), container.width - size.width - 8)

        let gap: CGFloat = 10
        var y = selection.minY - gap - size.height // below the selection
        if y < 8 { y = selection.maxY + gap }       // flip above if no room below
        y = min(max(8, y), container.height - size.height - 8)

        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Tool options popover content

/// The popover shown when a draw tool is selected: fixed color swatches, a thickness segmented
/// control, and (for the text tool) a size-preset menu. Reports changes back via closures.
final class ToolOptionsController: NSViewController {
    private let tool: Tool
    private let settings: ToolSettings
    private let showTextSize: Bool

    var onColor: ((NSColor) -> Void)?
    var onThickness: ((CGFloat) -> Void)?
    var onTextSize: ((CGFloat) -> Void)?

    private var swatchButtons: [NSButton] = []

    init(tool: Tool, settings: ToolSettings, showTextSize: Bool) {
        self.tool = tool
        self.settings = settings
        self.showTextSize = showTextSize
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let pad: CGFloat = 12
        let swatch: CGFloat = 22
        let swatchSpacing: CGFloat = 6
        let colors = Palette.colors
        let rowWidth = CGFloat(colors.count) * swatch + CGFloat(colors.count - 1) * swatchSpacing
        let width = rowWidth + pad * 2

        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 0))

        var y = pad

        // Optional text-size popup (drawn at the bottom row).
        if showTextSize {
            let popup = NSPopUpButton(frame: NSRect(x: pad, y: y, width: rowWidth, height: 24), pullsDown: false)
            for size in textSizePresets { popup.addItem(withTitle: "\(Int(size)) pt") }
            if let index = textSizePresets.firstIndex(of: settings.textSize) {
                popup.selectItem(at: index)
            }
            popup.target = self
            popup.action = #selector(textSizeChanged)
            root.addSubview(popup)
            y += 24 + 10
        }

        // Thickness segmented control — only for stroke-based tools. Text has no stroke (its size
        // is set by the "pt" popup above), so showing a thickness control there does nothing.
        if tool != .text {
            let segment = NSSegmentedControl(labels: ["Thin", "Med", "Thick"],
                                             trackingMode: .selectOne, target: self,
                                             action: #selector(thicknessChanged))
            segment.frame = NSRect(x: pad, y: y, width: rowWidth, height: 24)
            if let index = thicknessSteps.firstIndex(of: settings.thickness) {
                segment.selectedSegment = index
            }
            root.addSubview(segment)
            y += 24 + 10
        }

        // Color swatches.
        var x = pad
        for (index, color) in colors.enumerated() {
            let button = NSButton(frame: NSRect(x: x, y: y, width: swatch, height: swatch))
            button.title = ""
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.backgroundColor = color.cgColor
            button.layer?.cornerRadius = swatch / 2
            button.layer?.borderColor = NSColor(white: 0.5, alpha: 1).cgColor
            button.layer?.borderWidth = 1
            button.tag = index
            button.target = self
            button.action = #selector(swatchChanged)
            root.addSubview(button)
            swatchButtons.append(button)
            x += swatch + swatchSpacing
        }
        y += swatch + pad

        root.frame = NSRect(x: 0, y: 0, width: width, height: y)
        view = root
        updateSwatchSelection(for: settings.color)
    }

    @objc private func swatchChanged(_ sender: NSButton) {
        let color = Palette.colors[sender.tag]
        updateSwatchSelection(for: color)
        onColor?(color)
    }

    @objc private func thicknessChanged(_ sender: NSSegmentedControl) {
        guard sender.selectedSegment >= 0, sender.selectedSegment < thicknessSteps.count else { return }
        onThickness?(thicknessSteps[sender.selectedSegment])
    }

    @objc private func textSizeChanged(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem >= 0, sender.indexOfSelectedItem < textSizePresets.count else { return }
        onTextSize?(textSizePresets[sender.indexOfSelectedItem])
    }

    private func updateSwatchSelection(for color: NSColor) {
        for (index, button) in swatchButtons.enumerated() {
            let selected = Palette.colors[index] == color
            button.layer?.borderColor = selected
                ? NSColor.white.cgColor
                : NSColor(white: 0.5, alpha: 1).cgColor
            button.layer?.borderWidth = selected ? 3 : 1
        }
    }
}

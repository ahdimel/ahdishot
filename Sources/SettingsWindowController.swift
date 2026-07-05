import Cocoa

/// A single palette-color swatch button. Draws its fill and shows a ring when selected.
private final class SwatchButton: NSButton {
    let color: NSColor
    var isSelected = false { didSet { needsDisplay = true } }

    init(color: NSColor, index: Int) {
        self.color = color
        super.init(frame: .zero)
        tag = index
        title = ""
        isBordered = false
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 24).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 3, dy: 3)
        color.setFill()
        NSBezierPath(roundedRect: inset, xRadius: 4, yRadius: 4).fill()
        // A hairline keeps white/black swatches visible against the window.
        NSColor(white: 0.5, alpha: 0.5).setStroke()
        let outline = NSBezierPath(roundedRect: inset, xRadius: 4, yRadius: 4)
        outline.lineWidth = 1
        outline.stroke()
        if isSelected {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}

/// The Settings window (REQUIREMENTS §3.4/FR-16): global hotkey, save folder, image format,
/// launch-at-login, and default annotation color/thickness. Built programmatically (no xib) and
/// reused across opens. Writes straight through to `Settings` / `LaunchAtLogin`.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var hotKeyButton: HotKeyRecorderButton!
    private var folderPathLabel: NSTextField!
    private var formatPopup: NSPopUpButton!
    private var launchCheckbox: NSButton!
    private var thicknessControl: NSSegmentedControl!
    private var swatches: [SwatchButton] = []

    /// Fired when launch-at-login is changed here so the menu-bar item can refresh its check state.
    var onLaunchAtLoginChanged: (() -> Void)?

    func show() {
        if window == nil { build() }
        syncFromSettings()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Construction

    private func build() {
        hotKeyButton = HotKeyRecorderButton()
        hotKeyButton.onCapture = { code, mods in
            Settings.shared.setHotKey(code: code, modifiers: mods)
        }
        let clearHotKeyButton = NSButton(title: "Clear", target: self, action: #selector(clearHotKey))
        clearHotKeyButton.bezelStyle = .rounded
        let hotKeyRow = NSStackView(views: [hotKeyButton, clearHotKeyButton])
        hotKeyRow.orientation = .horizontal
        hotKeyRow.spacing = 8

        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))
        chooseButton.bezelStyle = .rounded
        folderPathLabel = NSTextField(labelWithString: "")
        folderPathLabel.lineBreakMode = .byTruncatingMiddle
        folderPathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let folderRow = NSStackView(views: [folderPathLabel, chooseButton])
        folderRow.orientation = .horizontal
        folderRow.spacing = 8

        formatPopup = NSPopUpButton()
        formatPopup.addItems(withTitles: ImageFormat.allCases.map { $0.displayName })
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)

        launchCheckbox = NSButton(checkboxWithTitle: "Launch ahdishot at login",
                                  target: self, action: #selector(launchToggled))

        thicknessControl = NSSegmentedControl(labels: ["Thin", "Medium", "Thick"],
                                              trackingMode: .selectOne,
                                              target: self, action: #selector(thicknessChanged))

        let swatchRow = NSStackView()
        swatchRow.orientation = .horizontal
        swatchRow.spacing = 4
        for (i, color) in Palette.colors.enumerated() {
            let swatch = SwatchButton(color: color, index: i)
            swatch.target = self
            swatch.action = #selector(colorChosen(_:))
            swatches.append(swatch)
            swatchRow.addArrangedSubview(swatch)
        }

        let rows = NSStackView(views: [
            labeledRow("Global hotkey", hotKeyRow),
            labeledRow("Save folder", folderRow),
            labeledRow("Image format", formatPopup),
            labeledRow("Startup", launchCheckbox),
            labeledRow("Default color", swatchRow),
            labeledRow("Default thickness", thicknessControl),
        ])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 14
        rows.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            rows.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            rows.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            rows.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "ahdishot Settings"
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
    }

    /// A form row: a fixed-width right-aligned caption followed by its control.
    private func labeledRow(_ caption: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: caption)
        label.alignment = .right
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 120).isActive = true
        control.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        // Fill the window width so the save-folder path row can truncate rather than push wide.
        row.widthAnchor.constraint(equalToConstant: 400).isActive = true
        return row
    }

    // MARK: - Sync UI ← Settings

    private func syncFromSettings() {
        let s = Settings.shared
        hotKeyButton.display(code: s.hotKeyCode, modifiers: s.hotKeyModifiers)
        folderPathLabel.stringValue = displayPath(for: s.saveFolderURL())
        formatPopup.selectItem(at: ImageFormat.allCases.firstIndex(of: s.imageFormat) ?? 0)
        launchCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
        thicknessControl.selectedSegment = thicknessSteps.firstIndex(of: s.defaultThickness) ?? 1
        for swatch in swatches { swatch.isSelected = (swatch.tag == s.defaultColorIndex) }
    }

    private func displayPath(for url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    // MARK: - Actions

    @objc private func clearHotKey() {
        Settings.shared.clearHotKey()
        hotKeyButton.display(code: 0, modifiers: 0)
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = Settings.shared.saveFolderURL()
        if panel.runModal() == .OK, let url = panel.url {
            Settings.shared.setSaveFolder(url)
            folderPathLabel.stringValue = displayPath(for: url)
        }
    }

    @objc private func formatChanged() {
        let index = formatPopup.indexOfSelectedItem
        if ImageFormat.allCases.indices.contains(index) {
            Settings.shared.imageFormat = ImageFormat.allCases[index]
        }
    }

    @objc private func launchToggled() {
        let enable = launchCheckbox.state == .on
        do {
            try LaunchAtLogin.setEnabled(enable)
        } catch {
            launchCheckbox.state = enable ? .off : .on // revert the visual toggle
            let alert = NSAlert()
            alert.messageText = "Couldn't \(enable ? "enable" : "disable") launch at login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        onLaunchAtLoginChanged?()
    }

    @objc private func thicknessChanged() {
        let index = thicknessControl.selectedSegment
        if thicknessSteps.indices.contains(index) {
            Settings.shared.defaultThickness = thicknessSteps[index]
        }
    }

    @objc private func colorChosen(_ sender: SwatchButton) {
        Settings.shared.defaultColorIndex = sender.tag
        for swatch in swatches { swatch.isSelected = (swatch === sender) }
    }
}

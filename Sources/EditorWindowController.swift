import Cocoa

/// Hosts the inline annotation editor: one borderless full-display window showing the frozen
/// capture, with the `EditorView` canvas and its toolbar. Wires the Copy / Save / Close actions
/// and tears everything down on dismiss. Copy and Save both dismiss after acting (owner decision).
final class EditorWindowController {
    private var window: KeyableWindow?
    private var editorView: EditorView?
    private var toolbar: EditorToolbar?
    private var onDismiss: (() -> Void)?

    func present(image: CGImage, screen: NSScreen, selection: NSRect, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss

        let window = KeyableWindow(contentRect: screen.frame,
                                   styleMask: .borderless,
                                   backing: .buffered,
                                   defer: false)
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let editor = EditorView(image: image, screen: screen, selection: selection)
        editor.onDismiss = { [weak self] in self?.dismiss() }

        let toolbar = EditorToolbar(editorView: editor)
        toolbar.onCopy = { [weak self] in self?.performCopy() }
        toolbar.onSave = { [weak self] in self?.performSave() }
        toolbar.onClose = { [weak self] in self?.dismiss() }
        editor.addSubview(toolbar)

        editor.onSelectionChanged = { [weak editor, weak toolbar] in
            guard let editor = editor, let toolbar = toolbar else { return }
            toolbar.reposition(around: editor.selectionRect, in: editor.bounds)
        }

        window.contentView = editor
        window.setFrame(screen.frame, display: true)

        self.window = window
        self.editorView = editor
        self.toolbar = toolbar

        toolbar.reposition(around: selection, in: editor.bounds)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
    }

    private func performCopy() {
        if let image = editorView?.flatten() {
            ScreenCapturer.copyToClipboard(image)
        }
        dismiss()
    }

    private func performSave() {
        if let image = editorView?.flatten() {
            do { _ = try ScreenCapturer.save(image) }
            catch { NSLog("ahdishot: save failed — \(error.localizedDescription)") }
        }
        dismiss()
    }

    private func dismiss() {
        window?.orderOut(nil)
        window = nil
        editorView = nil
        toolbar = nil
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }
}

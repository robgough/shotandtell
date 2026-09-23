import AppKit
import SwiftUI

/// Owns one editor window and the document behind it.
///
/// Held by the app delegate for as long as the window is open — an
/// `NSWindowController` with nothing retaining it closes the moment ARC notices.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    /// Named around the `document` that NSWindowController already declares
    /// for NSDocument-based apps, which this isn't.
    private let editorDocument: EditorDocument
    private let onClose: (EditorWindowController) -> Void
    private let onExported: (URL) -> Void

    convenience init(
        capture: CapturedImage,
        onExported: @escaping (URL) -> Void,
        onClose: @escaping (EditorWindowController) -> Void
    ) {
        self.init(document: EditorDocument(capture: capture), onExported: onExported, onClose: onClose)
    }

    /// Reopening keeps the same document, so the marks and the title survive.
    init(
        document: EditorDocument,
        onExported: @escaping (URL) -> Void,
        onClose: @escaping (EditorWindowController) -> Void
    ) {
        self.editorDocument = document
        self.onClose = onClose
        self.onExported = onExported

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Shot and Tell"
        // The toolbar runs to the top of the window rather than sitting under a
        // separate title bar, which is what a Mac app looks like now.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("EditorWindow")

        super.init(window: window)

        window.delegate = self

        let hosting = NSHostingController(
            rootView: EditorView(
                document: editorDocument,
                onDone: { [weak self] in self?.finish() },
                onSaveAndClose: { [weak self] in self?.finish(.saveOnly) },
                onCopy: { [weak self] in self?.copyOnly() }
            )
        )
        // Bridges SwiftUI's `.toolbar` into this window's real NSToolbar, which
        // is what buys the standard traffic-light spacing and unified title-bar
        // height. Hand-rolling a toolbar row inside the content view can't get
        // there: NSHostingController honours the title bar's safe area, so the
        // content already starts below it, and any leading padding added to
        // clear the traffic lights just opens a hole beside controls that are
        // a row too low. Must be set before the controller becomes the content.
        hosting.sceneBridgingOptions = [.toolbars]
        // Left alone, NSHostingController propagates the SwiftUI view's own
        // sizing to the window, and the editor opened at its minimum instead of
        // the size asked for above. The window decides how big it is.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.contentMinSize = NSSize(width: 900, height: 540)
        window.center()
        // The document's own undo manager, so ⌘Z in the window undoes marks
        // rather than whatever the focused text field last did.
        window.isRestorable = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Exposed so the app delegate can hold on to it and reopen the capture
    /// later. Not called `document`: NSWindowController already has one.
    var capturedDocument: EditorDocument { editorDocument }

    private func finish(_ options: Exporter.Options? = nil) {
        // Nil means "the standing preference": copy, and save too unless the
        // user has turned saving off.
        let resolved = options ?? Exporter.Options(
            copiesToClipboard: true,
            savesToDisk: Settings.shared.savesToDisk
        )
        Task { await finishExport(resolved) }
    }

    /// Copy without saving or closing — for when you want the image now and
    /// aren't finished marking it up.
    private func copyOnly() {
        Task {
            do {
                _ = try await Exporter.export(editorDocument.composition, options: .copyOnly)
            } catch {
                present(error)
            }
        }
    }

    /// Closing the window *is* discarding, so the question is asked here rather
    /// than by a destructive button in the toolbar — which isn't a Mac pattern,
    /// and left ⌘W and the red button as a silent way to lose the same work.
    ///
    /// Throwing away a capture with marks on it is worth one question. Throwing
    /// away an untouched one isn't.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if editorDocument.composition.annotations.isEmpty || hasConfirmedDiscard {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Discard this capture?"
        alert.informativeText = "It has marks on it that haven't been copied or saved."
        alert.alertStyle = .warning
        // Keep Editing first, so it's the default and Return doesn't destroy the
        // capture. The destructive option should take a deliberate click.
        alert.addButton(withTitle: "Keep Editing")
        let discard = alert.addButton(withTitle: "Discard")
        discard.hasDestructiveAction = true
        alert.beginSheetModal(for: sender) { [weak self] response in
            guard response == .alertSecondButtonReturn, let self else { return }
            hasConfirmedDiscard = true
            close()
        }
        return false
    }

    /// Set once the sheet has been answered, so the close it then performs isn't
    /// intercepted and asked about all over again.
    private var hasConfirmedDiscard = false

    /// Exporting is not discarding — don't ask on the way out of Copy & Close.
    private func closeAfterExport() {
        hasConfirmedDiscard = true
        close()
    }

    private func finishExport(_ options: Exporter.Options) async {
        do {
            let result = try await Exporter.export(editorDocument.composition, options: options)
            if let url = result.fileURL {
                Log.app.notice("Saved to \(url.lastPathComponent, privacy: .public)")
                onExported(url)
            }
            closeAfterExport()
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't finish the screenshot"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        editorDocument.undoManager
    }

    func windowWillClose(_ notification: Notification) {
        onClose(self)
    }
}

// MARK: - Zoom

/// The View menu's zoom commands. Here rather than on the canvas so they reach
/// the editor through the responder chain even while a legend field has focus
/// — the canvas isn't in the chain then, the window controller always is.
extension EditorWindowController {
    @objc func zoomCanvasIn(_ sender: Any?) { editorDocument.zoomIn() }
    @objc func zoomCanvasOut(_ sender: Any?) { editorDocument.zoomOut() }
    @objc func zoomCanvasToActualSize(_ sender: Any?) { editorDocument.zoomToActualSize() }
    @objc func zoomCanvasToFit(_ sender: Any?) { editorDocument.zoomToFit() }
}

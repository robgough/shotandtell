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
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Shot and Tell"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("EditorWindow")

        super.init(window: window)

        window.delegate = self

        let hosting = NSHostingController(
            rootView: EditorView(
                document: editorDocument,
                onDone: { [weak self] in self?.finish() },
                onCopy: { [weak self] in self?.copyOnly() },
                onCancel: { [weak self] in self?.discard() }
            )
        )
        // Left alone, NSHostingController propagates the SwiftUI view's own
        // sizing to the window, and the editor opened at its 780×460 minimum
        // instead of the size asked for above. The window decides how big it is.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 1040, height: 660))
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

    private func finish() {
        Task { await finishExport() }
    }

    /// Copy without saving or closing — for when you want the image now and
    /// aren't finished marking it up.
    private func copyOnly() {
        Task {
            do {
                _ = try await Exporter.export(editorDocument.composition, saveToDisk: false)
            } catch {
                present(error)
            }
        }
    }

    /// Throwing away a capture with marks on it is worth one question. Throwing
    /// away an untouched one isn't.
    private func discard() {
        guard !editorDocument.composition.annotations.isEmpty else {
            close()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Discard this capture?"
        alert.informativeText = "It has marks on it that haven't been copied or saved."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Keep Editing")
        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.close() }
        }
    }

    private func finishExport() async {
        do {
            let result = try await Exporter.export(editorDocument.composition)
            if let url = result.fileURL {
                Log.app.notice("Saved to \(url.lastPathComponent, privacy: .public)")
                onExported(url)
            }
            close()
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

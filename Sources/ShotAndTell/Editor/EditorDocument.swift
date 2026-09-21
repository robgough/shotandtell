import AppKit
import Observation
import SwiftUI

/// The editable state of one capture: the composition itself, plus the things
/// that are about editing it rather than about the finished image (which tool
/// is active, what's selected, which legend field wants focus).
///
/// The split matters — `Composition` is what gets rendered and eventually
/// exported, and nothing in it knows that an editor exists.
@Observable
final class EditorDocument {
    var composition: Composition {
        // The canvas is an AppKit view that SwiftUI can't see inside, so it
        // needs an explicit signal that something changed rather than relying
        // on observation reaching it.
        didSet { revision &+= 1 }
    }
    private(set) var revision = 0
    var tool: EditorTool = .pin
    var selection: UUID?
    /// Set when a new annotation is created, so the legend can move the cursor
    /// into its description field. Cleared once the field has taken focus.
    var pendingFocus: UUID?

    @ObservationIgnored let undoManager = UndoManager()

    init(capture: CapturedImage) {
        composition = Composition(
            capture: capture,
            // The captured app's name is a better starting point than an empty
            // field, and it's the thing people would type anyway.
            title: capture.sourceDescription ?? "",
            background: Settings.shared.defaultBackground,
            appearance: Settings.shared.resolvedAppearance()
        )
    }

    // MARK: - Editing

    func add(_ annotation: Annotation) {
        mutate("Add \(annotation.isNumbered ? "Mark" : "Redaction")") { $0.append(annotation) }
        selection = annotation.id
        if annotation.isNumbered { pendingFocus = annotation.id }
    }

    func remove(_ id: UUID) {
        guard composition.annotations.contains(where: { $0.id == id }) else { return }
        mutate("Delete Mark") { $0.removeAll { $0.id == id } }
        if selection == id { selection = nil }
    }

    func move(_ id: UUID, by delta: CGVector) {
        mutate("Move Mark", coalescing: true) { annotations in
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
            annotations[index].move(by: delta)
        }
    }

    func setText(_ text: String, for id: UUID) {
        guard let index = composition.annotations.firstIndex(where: { $0.id == id }),
              composition.annotations[index].text != text
        else { return }
        // Typing is not registered with the undo manager per keystroke — the
        // text field has its own undo, and interleaving the two produces an undo
        // stack that surprises everybody.
        composition.annotations[index].text = text
    }

    func binding(for id: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.composition.annotations.first { $0.id == id }?.text ?? ""
            },
            set: { [weak self] in self?.setText($0, for: id) }
        )
    }

    /// Every structural change goes through here so undo is registered in one
    /// place. Snapshotting the whole array is coarse, but an annotation list is
    /// a handful of small values and the alternative is a bug per operation.
    private func mutate(_ name: String, coalescing: Bool = false, _ body: (inout [Annotation]) -> Void) {
        let before = composition.annotations
        body(&composition.annotations)
        guard composition.annotations != before else { return }

        // A drag produces a move per mouse event; without coalescing, undoing a
        // single drag would take dozens of ⌘Z.
        if coalescing, undoManager.isUndoing == false, lastCoalescedName == name, undoManager.canUndo {
            return
        }
        lastCoalescedName = coalescing ? name : nil

        undoManager.registerUndo(withTarget: self) { document in
            let redo = document.composition.annotations
            document.composition.annotations = before
            document.undoManager.registerUndo(withTarget: document) { document in
                document.composition.annotations = redo
            }
        }
        undoManager.setActionName(name)
    }

    @ObservationIgnored private var lastCoalescedName: String?

    /// Called when a drag finishes, so the next one starts a fresh undo group.
    func endCoalescing() {
        lastCoalescedName = nil
    }
}

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
    /// Bumped when focus should go back to the canvas — after Escape in a
    /// description field — so the single-key tool shortcuts work again.
    private(set) var canvasFocusRequests = 0

    func focusCanvas() {
        canvasFocusRequests &+= 1
    }

    /// True while the on-device model is looking at the capture. Shown in the
    /// legend so an empty title field doesn't just sit there looking broken.
    private(set) var isSuggestingTitle = false

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

        if composition.title.isEmpty {
            suggestTitle()
        }
    }

    /// Fills the title in from the on-device model, if there is one and the user
    /// hasn't started typing one themselves.
    ///
    /// Only when the field is empty — a window capture already prefills the
    /// app's name, and replacing something concrete with a guess is a poor
    /// trade. The check is repeated after the model answers, because it takes a
    /// moment and the user may well have typed in the meantime.
    private func suggestTitle() {
        guard #available(macOS 27, *), TitleSuggester.isAvailable else { return }

        isSuggestingTitle = true
        let image = composition.capture.image
        Task { [weak self] in
            let suggestion = await TitleSuggester.suggest(for: image)
            guard let self else { return }
            isSuggestingTitle = false
            guard let suggestion, composition.title.isEmpty else { return }
            composition.title = suggestion
        }
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

    /// Used by the canvas's resize handles.
    func setKind(_ kind: Annotation.Kind, for id: UUID) {
        mutate("Resize Mark", coalescing: true) { annotations in
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
            annotations[index].kind = kind
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

        registerRestore(to: before)
        undoManager.setActionName(name)
    }

    /// Registers an undo that restores `snapshot` — and, when it runs, registers
    /// the same thing again for whatever it replaced.
    ///
    /// The re-entrance is the important part. Registering a *separate* redo
    /// closure that itself registers nothing leaves the stack one level short:
    /// undo, redo, and then the next undo skips the change entirely and eats the
    /// one before it, with the stack and the document disagreeing from then on.
    private func registerRestore(to snapshot: [Annotation]) {
        undoManager.registerUndo(withTarget: self) { document in
            let current = document.composition.annotations
            document.composition.annotations = document.preservingText(of: current, in: snapshot)
            document.registerRestore(to: current)
        }
    }

    /// Structural undo shouldn't throw away typing.
    ///
    /// Descriptions aren't registered with the undo manager (the text field has
    /// its own), so a snapshot taken before a mark was moved also contains the
    /// text as it was then. Restoring it verbatim would silently revert a
    /// sentence written since — which reads as the app eating your work. Marks
    /// that still exist keep whatever is currently typed against them.
    private func preservingText(of current: [Annotation], in snapshot: [Annotation]) -> [Annotation] {
        let texts = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0.text) })
        return snapshot.map { annotation in
            var restored = annotation
            if let text = texts[annotation.id] { restored.text = text }
            return restored
        }
    }

    @ObservationIgnored private var lastCoalescedName: String?

    /// Called when a drag finishes, so the next one starts a fresh undo group.
    func endCoalescing() {
        lastCoalescedName = nil
    }
}

import SwiftUI

/// One line of the legend: the number, what it means, and a way to be rid of it.
///
/// Its own type because it needs hover state of its own, and because the
/// alignment between the badge and the first line of a wrapping description is
/// fiddly enough to deserve somewhere to explain itself.
struct LegendEntryRow: View {
    @Bindable var document: EditorDocument
    let number: Int
    let total: Int
    let annotation: Annotation
    let markerColour: Color
    var focus: FocusState<UUID?>.Binding
    let onReleaseFocus: () -> Void

    @State private var hovering = false

    /// Half the cap height of the body font — how far above the baseline the
    /// optical centre of a line of text sits.
    ///
    /// The badge is a fixed-size circle, so aligning it against a wrapping text
    /// field needs its *centre* put on the first line's optical centre. Padding
    /// would do it for exactly one font size and one badge size and break the
    /// moment either changed; this is expressed in the same terms the compositor
    /// uses to place the badge in the exported image, so the panel and the
    /// export agree by construction.
    private static let capCentreAboveBaseline = NSFont.preferredFont(forTextStyle: .body).capHeight / 2

    private var isSelected: Bool { document.selection == annotation.id }

    var body: some View {
        // Read here, on the main actor, and captured as a plain CGFloat: the
        // alignment closure is Sendable and can't reach main-actor state itself.
        let badgeBaselineOffset = Self.capCentreAboveBaseline

        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(markerColour, in: .circle)
                // After the frame and background, so the guide belongs to the
                // whole badge rather than to the numeral inside it.
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions[VerticalAlignment.center] + badgeBaselineOffset
                }
                .help("\(annotation.kindName.capitalized) \(number)")
                // The row's own context menu below is unreachable across most
                // of the row, because the text field puts up its Look Up / Cut /
                // Copy menu instead. The badge is the one part of the row that
                // reliably belongs to the mark rather than to the text.
                .contextMenu { markActions }

            TextField(
                "Describe this",
                text: document.binding(for: annotation.id),
                prompt: Text("Describe this \(annotation.kindName)"),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1...6)
            .focused(focus, equals: annotation.id)
            // Escape and Return both hand focus back to the canvas, where the
            // single-key tool shortcuts live. Without somewhere to go, the only
            // way out of a description is the mouse.
            .onKeyPress(.escape) {
                onReleaseFocus()
                return .handled
            }
            .onKeyPress(.return, phases: .down) { press in
                // ⇧↩ and ⌥↩ still put a line break in a long description.
                guard press.modifiers.isEmpty else { return .ignored }
                onReleaseFocus()
                return .handled
            }
            // Reordering from the keyboard, since the context menu can't be
            // reached over the text itself.
            //
            // `contains`, not equality: arrow keys arrive carrying `.numericPad`
            // as well, so comparing the set to exactly [.command, .option] never
            // matches and the shortcut silently does nothing.
            .onKeyPress(.upArrow, phases: .down) { press in
                guard press.modifiers.isSuperset(of: [.command, .option]) else { return .ignored }
                document.moveNumbered(annotation.id, by: -1)
                return .handled
            }
            .onKeyPress(.downArrow, phases: .down) { press in
                guard press.modifiers.isSuperset(of: [.command, .option]) else { return .ignored }
                document.moveNumbered(annotation.id, by: 1)
                return .handled
            }

            Button(role: .destructive) {
                document.remove(annotation.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            // Kept in the layout at zero opacity rather than removed, so the
            // description's width doesn't jump as the pointer crosses the row.
            // A delete button on every row all the time reads as an edit mode.
            .opacity(hovering || isSelected ? 1 : 0)
            .help("Remove this mark")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(rowBackground)
        }
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture { document.selection = annotation.id }
        .contextMenu { markActions }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(annotation.kindName.capitalized) \(number)")
    }

    @ViewBuilder
    private var markActions: some View {
        Button("Move Up") { document.moveNumbered(annotation.id, by: -1) }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(number == 1)
        Button("Move Down") { document.moveNumbered(annotation.id, by: 1) }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(number == total)
        Divider()
        Button("Delete Mark", role: .destructive) { document.remove(annotation.id) }
    }

    private var rowBackground: AnyShapeStyle {
        if isSelected { AnyShapeStyle(Color.accentColor.opacity(0.14)) }
        else if hovering { AnyShapeStyle(.quaternary.opacity(0.5)) }
        else { AnyShapeStyle(.clear) }
    }
}

extension Annotation {
    /// What to call this mark in a sentence. Used in the empty field's prompt,
    /// where it's the only thing telling you which mark you're describing, and
    /// in the tooltip and accessibility label.
    var kindName: String {
        switch kind {
        case .pin: "pin"
        case .arrow: "arrow"
        case .box: "box"
        case .redaction: "redaction"
        }
    }
}

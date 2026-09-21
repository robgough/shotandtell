import SwiftUI

/// The editor: tools along the top, the composition on the left exactly as it
/// will be exported, and the legend on the right as editable rows.
///
/// Clicking the canvas drops a marker *and* moves the cursor into its
/// description, so the whole flow is click, type, click, type without reaching
/// for the mouse in between. That's the interaction the app exists for.
struct EditorView: View {
    @Bindable var document: EditorDocument
    let onDone: () -> Void
    let onCopy: () -> Void
    let onCancel: () -> Void

    @FocusState private var focusedEntry: UUID?
    @Namespace private var toolSelection

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                CompositionCanvas(
                    document: document,
                    revision: document.revision,
                    focusRequests: document.canvasFocusRequests
                )
                    .frame(minWidth: 420, minHeight: 320)
                Divider()
                legend
                    .frame(width: 300)
                    .background(.regularMaterial)
            }
        }
        .frame(minWidth: 780, minHeight: 460)
        .onChange(of: document.pendingFocus) { _, id in
            guard let id else { return }
            // A cycle later, so the row exists before focus is asked for.
            // Setting it in the same update as the row's creation silently does
            // nothing, which is what made you click into the field by hand.
            DispatchQueue.main.async {
                focusedEntry = id
                document.pendingFocus = nil
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            toolSelector

            Spacer()

            backgroundMenu

            Button {
                let markdown = MarkdownLegend.render(document.composition)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(markdown, forType: .string)
            } label: {
                Label("Copy Legend", systemImage: "text.badge.checkmark")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .help("Copy the legend as text (⇧⌘C)")
            .disabled(document.composition.numbered.isEmpty)

            Button("Copy", action: onCopy)
                .buttonStyle(.glass)
                .keyboardShortcut("c", modifiers: [.command, .option])
                .help("Copy the finished image and leave this window open (⌥⌘C)")

            // Deliberately not `.cancelAction`. That binds Escape, and Escape is
            // what you press to get out of a text field — losing the whole
            // capture, with nothing to show for it, because your finger went to
            // the wrong key.
            Button("Discard", action: onCancel)
                .buttonStyle(.glass)
                .help("Throw this capture away")

            Button("Copy & Close", action: onDone)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.glassProminent)
                .help(doneHelp)
        }
        // Leading room for the traffic lights: the title bar is transparent and
        // the content runs underneath it.
        .padding(.leading, 82)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// One control that happens to have five parts, not five controls.
    ///
    /// Built by hand rather than as a segmented `Picker` because the segments
    /// carry their keyboard shortcut next to the icon, and a segmented picker
    /// renders only an icon *or* a label. The glass is on the container, so the
    /// whole thing reads as a single selector; the selected segment is a pill
    /// that slides between them.
    private var toolSelector: some View {
        HStack(spacing: 2) {
            ForEach(EditorTool.allCases) { tool in
                toolSegment(tool)
            }
        }
        .padding(3)
        .glassEffect(in: .capsule)
        // Without this the toolbar squeezes the segments to fit everything else
        // in, and the shortcut letters are the first thing to get truncated
        // away — which is the whole reason they're there.
        .fixedSize()
        .animation(.snappy(duration: 0.18), value: document.tool)
    }

    private func toolSegment(_ tool: EditorTool) -> some View {
        let key = String(tool.shortcut).uppercased()
        let isSelected = document.tool == tool

        return Button {
            document.tool = tool
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tool.symbol)
                    .imageScale(.small)
                    .frame(width: 15)
                Text(key)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .opacity(isSelected ? 0.85 : 0.5)
                    .fixedSize()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor)
                        .matchedGeometryEffect(id: "selectedTool", in: toolSelection)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help("\(tool.title) — press \(key)")
    }

    private var backgroundMenu: some View {
        Menu {
            Picker("Background", selection: $document.composition.background) {
                Text("Neutral").tag(BackgroundStyle.neutral)
                Divider()
                ForEach(BackgroundStyle.Gradient.allCases, id: \.self) { gradient in
                    Text(gradient.rawValue.capitalized).tag(BackgroundStyle.gradient(gradient))
                }
                Divider()
                ForEach(BackgroundStyle.Tone.allCases, id: \.self) { tone in
                    Text(tone.rawValue.capitalized).tag(BackgroundStyle.solid(tone))
                }
                Divider()
                Text("None").tag(BackgroundStyle.bare)
            }
            .pickerStyle(.inline)

            Picker("Appearance", selection: $document.composition.appearance) {
                Text("Light").tag(Composition.Appearance.light)
                Text("Dark").tag(Composition.Appearance.dark)
            }
            .pickerStyle(.inline)
        } label: {
            Label("Background", systemImage: "paintpalette")
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .fixedSize()
    }

    private var legend: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    TextField("Title", text: $document.composition.title, prompt: Text("Title"))
                        .textFieldStyle(.plain)
                        .font(.title3.weight(.semibold))

                    if document.isSuggestingTitle {
                        ProgressView()
                            .controlSize(.small)
                            .help("Suggesting a title on-device")
                    }
                }

                Divider()

                if document.composition.numbered.isEmpty {
                    Text(emptyHint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }

                ForEach(document.composition.numbered, id: \.annotation.id) { number, annotation in
                    entryRow(number: number, annotation: annotation)
                }

                if !document.composition.redactions.isEmpty {
                    redactionSummary
                }
            }
            .padding(16)
        }
    }

    /// Hands the keyboard back to the canvas so the tool keys work again.
    private func releaseFocus() {
        focusedEntry = nil
        document.focusCanvas()
    }

    private var doneHelp: String {
        Settings.shared.savesToDisk
            ? "Copies the finished image, saves a PNG to \(Settings.shared.saveFolderDisplayName), and closes (⌘↩)"
            : "Copies the finished image and closes (⌘↩)"
    }

    private var emptyHint: String {
        """
        Pick a tool and click the screenshot. Each mark gets a number, and \
        whatever you type here becomes its entry in the legend.

        The keys on the buttons pick a tool while the screenshot has focus. \
        After a mark is placed you're back in Select, so the next click picks \
        something up rather than making another one — and Escape in a \
        description hands focus back to the screenshot.
        """
    }

    private func entryRow(number: Int, annotation: Annotation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color(nsColor: .systemRed), in: .circle)

            TextField("Describe this", text: document.binding(for: annotation.id), axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($focusedEntry, equals: annotation.id)
                // Escape and Return both hand focus back to the canvas, where
                // the single-key tool shortcuts live. Without somewhere to go,
                // the only way out of a description is the mouse — and then the
                // shortcuts may as well not exist.
                .onKeyPress(.escape) {
                    releaseFocus()
                    return .handled
                }
                .onKeyPress(.return, phases: .down) { press in
                    // ⇧↩ and ⌥↩ still put a line break in a long description.
                    guard press.modifiers.isEmpty else { return .ignored }
                    releaseFocus()
                    return .handled
                }

            Button {
                document.remove(annotation.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove this mark")
        }
        .padding(8)
        .background(
            document.selection == annotation.id ? Color.accentColor.opacity(0.12) : .clear,
            in: .rect(cornerRadius: 6)
        )
        .contentShape(.rect)
        .onTapGesture { document.selection = annotation.id }
    }

    private var redactionSummary: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(nsColor: .labelColor).opacity(0.85))
                .frame(width: 22, height: 14)
            Text(document.composition.redactions.count == 1
                 ? "1 redacted area"
                 : "\(document.composition.redactions.count) redacted areas")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 4)
    }
}

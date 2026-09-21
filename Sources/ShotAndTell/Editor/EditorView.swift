import SwiftUI

/// The editor: the composition filling the window, tools in the window's own
/// toolbar, and the legend as an inspector on the right.
///
/// Clicking the canvas drops a marker *and* moves the cursor into its
/// description, so the whole flow is click, type, Return, click, type without
/// reaching for the mouse in between. That's the interaction the app exists for.
struct EditorView: View {
    @Bindable var document: EditorDocument
    let onDone: () -> Void
    let onCopy: () -> Void

    @FocusState private var focusedEntry: UUID?
    @Namespace private var toolSelection

    /// The same colours the exported image uses, so a number in the legend is
    /// the red it will actually be printed in rather than the system red.
    private var palette: Palette {
        Palette.resolve(
            background: document.composition.background,
            appearance: document.composition.appearance
        )
    }

    var body: some View {
        CompositionCanvas(
            document: document,
            revision: document.revision,
            focusRequests: document.canvasFocusRequests
        )
        // The composition runs under the floating toolbar; the canvas fits
        // itself into the safe area so nothing important hides behind it.
        .ignoresSafeArea(edges: .top)
        .inspector(isPresented: .constant(true)) {
            legend.inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) { toolSelector }
            ToolbarSpacer(.flexible)
            ToolbarItem { backgroundMenu }
            ToolbarSpacer(.fixed)
            ToolbarItemGroup(placement: .primaryAction) {
                copyMenu
                Button("Copy & Close", action: onDone)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.glassProminent)
                    .help(doneHelp)
            }
        }
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

    // MARK: - Toolbar

    /// One control that happens to have five parts, not five controls.
    ///
    /// Built by hand rather than as a segmented `Picker` because the segments
    /// carry their keyboard shortcut next to the icon, and a segmented picker
    /// renders only an icon *or* a label. The toolbar item supplies the glass
    /// around it — adding our own here would stack one glass layer on another.
    private var toolSelector: some View {
        HStack(spacing: 2) {
            ForEach(EditorTool.allCases) { tool in
                toolSegment(tool)
            }
        }
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

    /// Copy the image, with the text-only variant tucked inside rather than
    /// sitting in the toolbar as an unlabelled glyph nobody can decode.
    private var copyMenu: some View {
        Menu("Copy") {
            Button("Copy Legend as Text") {
                let markdown = MarkdownLegend.render(document.composition)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(markdown, forType: .string)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(document.composition.numbered.isEmpty)
        } primaryAction: {
            onCopy()
        }
        .menuStyle(.button)
        .help("Copy the finished image and leave this window open (⌥⌘C)")
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
        // A unified-compact toolbar collapses a Label to its icon, and a lone
        // paintpalette glyph is a guess rather than a control.
        .labelStyle(.titleAndIcon)
        .help("Background and appearance of the finished image")
    }

    private var doneHelp: String {
        Settings.shared.savesToDisk
            ? "Copies the finished image, saves a PNG to \(Settings.shared.saveFolderDisplayName), and closes (⌘↩)"
            : "Copies the finished image and closes (⌘↩)"
    }

    // MARK: - Legend

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
                    // One line. The tools carry their own shortcuts and their own
                    // tooltips; a paragraph explaining the focus model here reads
                    // as an apology for it.
                    Text("Click the screenshot to add a mark.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
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

    private func entryRow(number: Int, annotation: Annotation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color(cgColor: palette.marker), in: .circle)

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
                .fill(Color(cgColor: palette.redaction))
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

    /// Hands the keyboard back to the canvas so the tool keys work again.
    private func releaseFocus() {
        focusedEntry = nil
        document.focusCanvas()
    }
}

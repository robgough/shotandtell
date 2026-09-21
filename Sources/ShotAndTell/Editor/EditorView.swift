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

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
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
        HStack(spacing: 12) {
            Picker("Tool", selection: $document.tool) {
                ForEach(EditorTool.allCases) { tool in
                    Label(tool.title, systemImage: tool.symbol)
                        .help(tool.help)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

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
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .help("Copy the legend as text (⇧⌘C)")
            .disabled(document.composition.numbered.isEmpty)

            Button("Copy", action: onCopy)
                .keyboardShortcut("c", modifiers: [.command, .option])
                .help("Copy the finished image and leave this window open (⌥⌘C)")

            // Deliberately not `.cancelAction`. That binds Escape, and Escape is
            // what you press to get out of a text field — losing the whole
            // capture, with nothing to show for it, because your finger went to
            // the wrong key.
            Button("Discard", action: onCancel)
                .help("Throw this capture away")

            Button("Copy & Close", action: onDone)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .help(doneHelp)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
        .menuStyle(.borderlessButton)
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

    private var doneHelp: String {
        Settings.shared.savesToDisk
            ? "Copies the finished image, saves a PNG to \(Settings.shared.saveFolderDisplayName), and closes (⌘↩)"
            : "Copies the finished image and closes (⌘↩)"
    }

    private var emptyHint: String {
        """
        Pick a tool and click the screenshot. Each mark gets a number, and \
        whatever you type here becomes its entry in the legend.

        P, A, B and R pick a tool while the screenshot has focus; Escape in a \
        description sends focus back to it.
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
                // Escape hands focus back to the canvas, where the single-key
                // tool shortcuts live. Without somewhere to go, the only way out
                // of a description is the mouse.
                .onKeyPress(.escape) {
                    focusedEntry = nil
                    document.focusCanvas()
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

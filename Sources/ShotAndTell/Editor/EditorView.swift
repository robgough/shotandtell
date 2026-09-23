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
    let onSaveAndClose: () -> Void
    let onCopy: () -> Void

    @FocusState private var focusedEntry: UUID?
    @Namespace private var toolSelection

    /// The same colours the exported image uses, so a number in the legend is
    /// the red it will actually be printed in rather than the system red.
    private var palette: Palette {
        Palette.resolve(
            background: document.composition.background,
            appearance: document.composition.appearance,
            markerColour: document.composition.markerColour
        )
    }

    var body: some View {
        CompositionCanvas(
            document: document,
            revision: document.revision,
            focusRequests: document.canvasFocusRequests,
            magnification: document.magnification
        )
        // The composition runs under the floating toolbar; the canvas fits
        // itself into the safe area so nothing important hides behind it.
        .ignoresSafeArea(edges: .top)
        // Over the composition rather than up in the toolbar. It changes how the
        // background looks, it's set rarely, and the header is for the things
        // you reach for every time.
        // Over the composition rather than up in the toolbar. They change how
        // the picture looks, or how you're looking at it, and are set rarely —
        // the header is for the things you reach for every time.
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                if document.magnification != nil {
                    controlsBar
                }
                HStack(spacing: 8) {
                    zoomMenu
                    Spacer()
                    markerMenu
                    backgroundMenu
                }
                .padding(16)
            }
            // Glass takes its tint and its text colour from the colour scheme,
            // and left alone that's the *system's* — so a dark Mac put white
            // text on glass over a pale composition, and it was unreadable. These
            // sit on the composition, so they follow the canvas instead.
            .environment(\.colorScheme, palette.canvasIsDark ? .dark : .light)
        }
        .inspector(isPresented: .constant(true)) {
            legend.inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) { toolSelector }
            ToolbarSpacer(.flexible)
            ToolbarItemGroup(placement: .primaryAction) {
                copyMenu
                finishMenu
            }
        }
        // Selection follows focus. Clicking *into* a description never reaches the
        // row's tap gesture — the text field swallows the mouse-down — so
        // without this the dashed ring on the canvas only tracked rows you
        // clicked the padding of. Never the reverse: focus must not follow
        // selection, or clicking a mark on the canvas would steal the keyboard
        // and the tool shortcuts would stop working.
        .onChange(of: focusedEntry) { _, id in
            if let id { document.selection = id }
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

    /// The primary way out, with the variations behind its chevron rather than
    /// as more buttons: most of the time you want all of it, and when you don't
    /// you want to say so once.
    private var finishMenu: some View {
        Menu {
            Button("Save & Close", action: onSaveAndClose)
                .help("Write the PNG without touching the clipboard")
            Divider()
            Toggle("Always Save a PNG", isOn: Binding(
                get: { Settings.shared.savesToDisk },
                set: { Settings.shared.savesToDisk = $0 }
            ))
        } label: {
            Text("Copy & Close")
        } primaryAction: {
            onDone()
        }
        .menuStyle(.button)
        .buttonStyle(.glassProminent)
        .keyboardShortcut(.return, modifiers: .command)
        .help(doneHelp)
    }

    /// Which colour the marks are drawn in.
    ///
    /// Next to the background picker because it's the same kind of decision, and
    /// it matters for the same reason: marks in a colour the screenshot is
    /// already full of are marks nobody can see.
    private var markerMenu: some View {
        Menu {
            // A Picker rather than a row of Buttons: it marks the current choice
            // with a tick by itself, which hand-built menu items don't.
            Picker("Marker colour", selection: $document.composition.markerColour) {
                ForEach(MarkerColour.presets, id: \.self) { colour in
                    Text(colour.name).tag(colour)
                }
                if case .custom = document.composition.markerColour {
                    Text("Custom").tag(document.composition.markerColour)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Button("Custom…") { showColourPanel() }
        } label: {
            // The dot alone. A label saying "Marker" next to a coloured circle
            // is telling people something the circle already told them.
            Circle()
                .fill(Color(cgColor: palette.marker))
                .frame(width: 13, height: 13)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .fixedSize()
        .help("Colour of the numbers, arrows and boxes")
    }

    private func showColourPanel() {
        let current = NSColor(cgColor: palette.marker) ?? .systemRed
        MarkerColourPanel.shared.show(initial: current) { chosen in
            guard let srgb = chosen.usingColorSpace(.sRGB) else { return }
            document.composition.markerColour = .custom(
                red: Double(srgb.redComponent),
                green: Double(srgb.greenComponent),
                blue: Double(srgb.blueComponent)
            )
        }
    }

    /// A frosted bar behind the bottom controls, shown only while zoomed in —
    /// the only time the screenshot passes under them. A real blur, so what's
    /// underneath reads as picture rather than as text competing with the
    /// buttons, tinted towards the canvas colour and finished with a hairline
    /// rather than a fade.
    ///
    /// Not hit-testable: a click on it goes to the canvas, as it would if the
    /// bar weren't there.
    private var controlsBar: some View {
        Rectangle()
            .fill(.regularMaterial)
            .overlay(Color(cgColor: palette.canvasBottom).opacity(0.35))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 0.5)
            }
            .frame(height: CompositionCanvasView.controlsInset)
            .allowsHitTesting(false)
    }

    /// Opposite corner from the colour and background buttons: those change the
    /// picture, this only changes how you're looking at it. Shortcuts are in
    /// the View menu, which is where they're shown.
    private var zoomMenu: some View {
        Menu {
            Button("Zoom In") { document.zoomIn() }
            Button("Zoom Out") { document.zoomOut() }
                .disabled(document.magnification == nil)
            Divider()
            Button("Actual Size") { document.zoomToActualSize() }
            Button("Zoom to Fit") { document.zoomToFit() }
                .disabled(document.magnification == nil)
        } label: {
            Label(zoomLabel, systemImage: "plus.magnifyingglass")
                .monospacedDigit()
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .labelStyle(.titleAndIcon)
        .fixedSize()
        .help("Zoom in to place marks precisely. Pinch, or ⌘-scroll with a mouse.")
    }

    private var zoomLabel: String {
        guard let magnification = document.magnification else { return "Fit" }
        return "\(Int((magnification * 100).rounded()))%"
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
        .labelStyle(.titleAndIcon)
        .fixedSize()
        .help("Background and appearance of the finished image")
    }

    private var doneHelp: String {
        Settings.shared.savesToDisk
            ? "Copies the finished image, saves a PNG to \(Settings.shared.saveFolderDisplayName), and closes (⌘↩)"
            : "Copies the finished image and closes, without saving a file (⌘↩)"
    }

    // MARK: - Legend

    private var legend: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        TextField("Title", text: $document.composition.title, prompt: Text("Title"))
                            .textFieldStyle(.plain)
                            .font(.title3.weight(.semibold))
                            // The first field you land in should behave like the
                            // rest of them.
                            .onKeyPress(.escape) {
                                releaseFocus()
                                return .handled
                            }
                            .onKeyPress(.return, phases: .down) { press in
                                guard press.modifiers.isEmpty else { return .ignored }
                                releaseFocus()
                                return .handled
                            }

                        if document.isSuggestingTitle {
                            ProgressView()
                                .controlSize(.small)
                                .transition(.opacity)
                                .help("Suggesting a title on-device")
                        }
                    }
                    .padding(.horizontal, 8)
                    .animation(.default, value: document.isSuggestingTitle)

                    Divider()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)

                    if document.composition.numbered.isEmpty {
                        // One line. The tools carry their own shortcuts and their
                        // own tooltips; a paragraph explaining the focus model
                        // here reads as an apology for it.
                        Text("Click the screenshot to add a mark.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                    }

                    let entries = document.composition.numbered
                    ForEach(entries, id: \.annotation.id) { number, annotation in
                        LegendEntryRow(
                            document: document,
                            number: number,
                            total: entries.count,
                            annotation: annotation,
                            markerColour: Color(cgColor: palette.marker),
                            focus: $focusedEntry,
                            onReleaseFocus: releaseFocus
                        )
                        .id(annotation.id)
                    }

                    if !document.composition.redactions.isEmpty {
                        redactionSummary
                            .padding(.horizontal, 8)
                    }
                }
                // Rows carry their own 8pt horizontal padding, so everything
                // lines up at 16 while a row's tint bleeds into the gutter —
                // which is how a Mac sidebar behaves.
                .padding(.vertical, 16)
                .padding(.horizontal, 8)
            }
            .onChange(of: document.selection) { _, id in
                guard let id else { return }
                withAnimation(.snappy(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
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
        // The same height as a badge, so the swatch sits on the line an entry
        // would — it's the panel's version of the export's redaction key.
        .frame(height: 22)
        .padding(.top, 4)
    }

    /// Hands the keyboard back to the canvas so the tool keys work again.
    private func releaseFocus() {
        focusedEntry = nil
        document.focusCanvas()
    }
}

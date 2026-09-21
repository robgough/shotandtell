import AppKit

/// Turning a finished composition into the things the user actually wanted: an
/// image on the clipboard, the legend as text alongside it, and a file on disk.
enum Exporter {
    /// The longest edge of the exported PNG, in pixels.
    ///
    /// Rendering at 2x keeps the legend crisp, but an uncapped 2x export of a
    /// large display is several megabytes — slow to paste, and downscaled by
    /// most things it gets pasted into anyway.
    static let maximumPixelEdge: CGFloat = 2400

    struct Result {
        let fileURL: URL?
        let markdown: String
    }

    enum Failure: LocalizedError {
        case noPicturesFolder

        var errorDescription: String? {
            switch self {
            case .noPicturesFolder: "Couldn't find your Pictures folder to save into."
            }
        }
    }

    /// Async, and genuinely off the main thread for the expensive part.
    ///
    /// `nonisolated` is not enough on its own: with approachable concurrency a
    /// nonisolated function runs on its *caller's* actor, so composing and
    /// encoding a full-screen capture — around a third of a second for a 6K
    /// display — would freeze the app at exactly the moment the user pressed
    /// Done. `Task.detached` is what actually moves it, and `Composition` is
    /// Sendable so it can go.
    /// What finishing a capture should actually do.
    ///
    /// Separated because the three ways out of the editor want different
    /// combinations: Copy & Close copies (and saves, if that's the standing
    /// preference), Save & Close writes a file without touching the clipboard,
    /// and the plain Copy button copies without leaving a file behind.
    struct Options {
        var copiesToClipboard = true
        var savesToDisk = true

        static let copyOnly = Options(copiesToClipboard: true, savesToDisk: false)
        static let saveOnly = Options(copiesToClipboard: false, savesToDisk: true)
    }

    @discardableResult
    static func export(_ composition: Composition, options: Options = Options()) async throws -> Result {
        let settings = Settings.shared
        let palette = Palette.resolve(background: composition.background, appearance: composition.appearance)
        let layout = CompositionLayout.solve(composition, palette: palette)
        let scale = exportScale(for: layout.canvasSize, setting: settings.exportScale)

        let (png, pixelWidth, pixelHeight) = try await Task.detached(priority: .userInitiated) {
            let rendered = try Compositor.render(composition, scale: scale)
            let png = try PNGEncoder.encode(rendered.image, scale: scale)
            return (png, rendered.image.width, rendered.image.height)
        }.value

        let markdown = MarkdownLegend.render(composition)

        // The image, and only the image unless asked otherwise. Putting the
        // legend text on the pasteboard at the same time means anything that
        // prefers text pastes the words and drops the picture — which is the
        // opposite of what pressing a button labelled "copy the screenshot"
        // should do.
        if options.copiesToClipboard {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            if settings.copiesLegendText, !markdown.isEmpty {
                pasteboard.setString(markdown, forType: .string)
            }
        }

        var fileURL: URL?
        if options.savesToDisk {
            fileURL = try write(png, title: composition.title, settings: settings)
        }

        Log.app.notice("Exported \(pixelWidth, privacy: .public)×\(pixelHeight, privacy: .public)px")
        return Result(fileURL: fileURL, markdown: markdown)
    }

    static func exportScale(for canvasSize: CGSize, setting: Settings.ExportScale) -> CGFloat {
        switch setting {
        case .standard:
            return 1
        case .retinaFull:
            return 2
        case .retinaCapped:
            let longestEdge = max(canvasSize.width, canvasSize.height)
            guard longestEdge > 0 else { return 2 }
            // Never below 1x. The cap is on the whole canvas, and a long legend
            // makes the canvas tall — fifty entries could push the scale under
            // 0.7 and shrink the *screenshot* to well below the resolution it
            // was captured at, silently. A tall legend should make a tall file,
            // not an unreadable one.
            return max(1, min(2, maximumPixelEdge / longestEdge))
        }
    }

    private static func write(_ png: Data, title: String, settings: Settings) throws -> URL {
        // A folder the user chose is reached through a security-scoped
        // bookmark, and access has to be given back afterwards.
        if let chosen = settings.resolveSaveFolder() {
            defer { chosen.stopAccessing() }
            let url = chosen.url.appending(path: filename(title: title))
            try png.write(to: url, options: .atomic)
            return url
        }

        // Otherwise the default. With the pictures entitlement this resolves to
        // the real ~/Pictures rather than the sandbox container's copy of it.
        guard let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first else {
            throw Failure.noPicturesFolder
        }

        let folder = pictures.appending(path: "Shot and Tell", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let url = folder.appending(path: filename(title: title))
        try png.write(to: url, options: .atomic)
        return url
    }

    /// "Homepage spacing 2026-09-21 at 22.31.45.png" — the title first so a
    /// folder of these is browsable, the timestamp second so nothing collides.
    private static func filename(title: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stamp = formatter.string(from: Date())

        var cleaned = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .prefix(60)
        // A title starting with a dot would make an invisible file, which looks
        // exactly like the save having failed.
        while cleaned.hasPrefix(".") { cleaned = cleaned.dropFirst() }

        return cleaned.isEmpty ? "Shot and Tell \(stamp).png" : "\(cleaned) \(stamp).png"
    }
}

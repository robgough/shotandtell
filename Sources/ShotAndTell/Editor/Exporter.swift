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

    @discardableResult
    static func export(_ composition: Composition, saveToDisk: Bool = true) throws -> Result {
        let palette = Palette.resolve(background: composition.background, appearance: composition.appearance)
        let layout = CompositionLayout.solve(composition, palette: palette)
        let scale = exportScale(for: layout.canvasSize)

        let rendered = try Compositor.render(composition, scale: scale)
        let png = try PNGEncoder.encode(rendered.image, scale: scale)
        let markdown = MarkdownLegend.render(composition)

        // One pasteboard item carrying both: pasting into a chat gets the
        // picture, pasting into a text field gets the words.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if !markdown.isEmpty {
            pasteboard.setString(markdown, forType: .string)
        }

        var fileURL: URL?
        if saveToDisk {
            fileURL = try write(png, title: composition.title)
        }

        Log.app.notice("Exported \(rendered.image.width, privacy: .public)×\(rendered.image.height, privacy: .public)px")
        return Result(fileURL: fileURL, markdown: markdown)
    }

    static func exportScale(for canvasSize: CGSize) -> CGFloat {
        let longestEdge = max(canvasSize.width, canvasSize.height)
        guard longestEdge > 0 else { return 2 }
        return min(2, maximumPixelEdge / longestEdge)
    }

    private static func write(_ png: Data, title: String) throws -> URL {
        // With the pictures entitlement this resolves to the real ~/Pictures
        // rather than the sandbox container's copy of it.
        guard let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first else {
            throw Failure.noPicturesFolder
        }

        let folder = pictures.appending(path: "Shot and tell", directoryHint: .isDirectory)
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

        let cleaned = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .prefix(60)

        return cleaned.isEmpty ? "Shot and tell \(stamp).png" : "\(cleaned) \(stamp).png"
    }
}

import CoreGraphics
import Foundation
import FoundationModels

/// Suggests a title for a capture using Apple's on-device model.
///
/// Entirely optional, and silent when it can't help: Apple Intelligence may be
/// off, the Mac may not be eligible, the model may still be downloading, or the
/// OS may be macOS 26, where the vision-capable API doesn't exist. In every one
/// of those cases the title field simply stays empty and the user types their
/// own, which is what they'd be doing anyway.
///
/// `SystemLanguageModel` runs on the device. That matters here beyond privacy:
/// the app has no network entitlement, so a model that needed the network
/// couldn't be reached even if we asked for it.
@available(macOS 27, *)
enum TitleSuggester {
    static var isAvailable: Bool {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return false }
        return model.capabilities.contains(.vision)
    }

    static func suggest(for image: CGImage) async -> String? {
        guard isAvailable else { return nil }

        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: """
                You name screenshots. Given one, reply with a short title — two \
                to five words — describing what the screenshot shows, as a \
                person would label it in a folder.

                Name the thing on screen, not the act of screenshotting it. \
                Good: "Checkout form", "Settings sidebar", "Build log with \
                errors". Bad: "A screenshot of a website", "Image", "Screen \
                capture of an application window".

                Reply with the title alone. No quotation marks, no trailing full \
                stop, no explanation.
                """
        )

        // Downscaled first: the model doesn't need six thousand pixels across to
        // tell a checkout form from a build log, and a full-resolution Retina
        // capture is slow to encode and slow to run.
        let scaled = downscaled(image, longestEdge: 1024) ?? image

        do {
            let response = try await session.respond {
                "Give this screenshot a title."
                Attachment(scaled)
            }
            return tidied(response.content)
        } catch {
            Log.app.notice("Title suggestion unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Models sometimes answer with a sentence, or with quotes around the
    /// title, however plainly they were asked not to.
    private static func tidied(_ raw: String) -> String? {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.components(separatedBy: .newlines).first ?? title
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’ "))
        while title.hasSuffix(".") { title = String(title.dropLast()) }

        guard !title.isEmpty, title.count <= 60 else { return nil }
        return title
    }

    private static func downscaled(_ image: CGImage, longestEdge: CGFloat) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let factor = longestEdge / max(width, height)
        guard factor < 1 else { return image }

        let target = CGSize(width: (width * factor).rounded(), height: (height * factor).rounded())
        guard let context = CGContext(
            data: nil,
            width: Int(target.width),
            height: Int(target.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: target))
        return context.makeImage()
    }
}

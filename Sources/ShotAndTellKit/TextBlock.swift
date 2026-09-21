import CoreGraphics
import CoreText
import Foundation

/// A wrapped run of text that can measure itself before it's drawn.
///
/// Core Text rather than AppKit, so this stays usable from an iOS target and
/// off the main thread. The compositor needs to know how tall the legend is
/// before it can decide how tall the canvas is, so measuring and drawing have
/// to be separable.
nonisolated struct TextBlock {
    let attributed: NSAttributedString

    init(_ string: String, font: CTFont, colour: CGColor, lineSpacing: CGFloat = 3, alignment: CTTextAlignment = .left) {
        // The settings array holds raw pointers to these values, so they have
        // to stay alive until CTParagraphStyleCreate has copied them. Passing
        // `&alignment` inline gives a pointer that may not outlive the argument.
        var alignment = alignment
        var spacing = lineSpacing
        let paragraph = withUnsafeMutablePointer(to: &alignment) { alignmentPointer in
            withUnsafeMutablePointer(to: &spacing) { spacingPointer in
                let settings = [
                    CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: alignmentPointer),
                    CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: spacingPointer),
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }

        // Core Text's own attribute keys, not AppKit's `.font` /
        // `.foregroundColor`. Those are declared by AppKit, so using them would
        // make this file — and therefore all of ShotAndTellKit — quietly
        // dependent on it, which is exactly what this folder is meant not to be.
        attributed = NSAttributedString(string: string, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: colour,
            kCTParagraphStyleAttributeName as NSAttributedString.Key: paragraph,
        ])
    }

    /// The height this text needs at a given width. Ceiled, because a fractional
    /// shortfall clips the last line's descenders.
    func height(constrainedTo width: CGFloat) -> CGFloat {
        guard !attributed.string.isEmpty else { return 0 }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: width, height: .greatestFiniteMagnitude),
            nil
        )
        return ceil(size.height)
    }

    /// Width of the text if it were never wrapped — used to decide how wide the
    /// legend column wants to be.
    func unwrappedWidth() -> CGFloat {
        guard !attributed.string.isEmpty else { return 0 }
        let line = CTLineCreateWithAttributedString(attributed)
        return ceil(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// Draws into a y-up context. `rect` is in that context's coordinates, and
    /// the text is laid out from its top edge downwards.
    func draw(in rect: CGRect, context: CGContext) {
        guard !attributed.string.isEmpty else { return }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
    }

    static func font(size: CGFloat, emphasised: Bool = false) -> CTFont {
        CTFontCreateUIFontForLanguage(emphasised ? .emphasizedSystem : .system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }
}

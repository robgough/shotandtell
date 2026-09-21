import CoreGraphics
import CoreText
import Foundation

/// Where everything goes, in points, worked out before a single pixel is drawn.
///
/// Separating layout from drawing is what lets the editor hit-test: it knows
/// where the capture landed inside the composition, so a click in the preview
/// can be turned back into a normalised point on the capture. Everything here
/// is in a **y-up** canvas space, matching the Core Graphics context the
/// compositor draws into.
nonisolated struct CompositionLayout: Sendable {
    let canvasSize: CGSize
    let captureRect: CGRect
    let legendRect: CGRect
    let entries: [Entry]
    let titleRect: CGRect
    let ruleY: CGFloat?
    let redactionKeyRect: CGRect?

    nonisolated struct Entry: Sendable {
        let number: Int
        let badgeCentre: CGPoint
        let textRect: CGRect
        let text: String
    }

    // MARK: - Metrics
    //
    // One place for every number, so the composition can be re-proportioned by
    // editing this block rather than hunting through drawing code.

    static let padding: CGFloat = 44
    static let barePadding: CGFloat = 20
    static let columnGap: CGFloat = 36
    static let captureCornerRadius: CGFloat = 10
    static let markerDiameter: CGFloat = 26
    static let badgeDiameter: CGFloat = 22
    static let entrySpacing: CGFloat = 14
    static let titleGap: CGFloat = 14
    static let badgeTextGap: CGFloat = 10
    static let minimumLegendWidth: CGFloat = 240
    static let maximumLegendWidth: CGFloat = 420
    static let titleFontSize: CGFloat = 17
    static let entryFontSize: CGFloat = 13

    static func titleFont() -> CTFont { TextBlock.font(size: titleFontSize, emphasised: true) }
    static func entryFont() -> CTFont { TextBlock.font(size: entryFontSize) }

    // MARK: - Solving

    /// `includeLegend` is false for the editor's canvas, which shows the capture
    /// framed on its background but leaves the legend to the panel beside it —
    /// no point rendering the same list twice, side by side.
    static func solve(_ composition: Composition, palette: Palette, includeLegend: Bool = true) -> CompositionLayout {
        let padding = composition.background == .bare ? barePadding : self.padding
        let captureSize = composition.capture.pointSize

        let entriesText = includeLegend ? composition.numbered.map { (number: $0.number, text: $0.annotation.text) } : []
        let hasLegend = includeLegend && !composition.legendIsEmpty
        let hasRedactionKey = !composition.redactions.isEmpty && hasLegend

        let legendWidth = hasLegend ? legendColumnWidth(title: composition.title, entries: entriesText, beside: captureSize.width) : 0

        // Measure the legend's height before the canvas exists, since the canvas
        // has to be tall enough for whichever column is taller.
        let titleBlock = (!hasLegend || composition.title.isEmpty) ? nil : TextBlock(composition.title, font: titleFont(), colour: palette.ink)
        let titleHeight = titleBlock?.height(constrainedTo: legendWidth) ?? 0

        let textWidth = legendWidth - badgeDiameter - badgeTextGap
        var entryHeights: [CGFloat] = []
        for entry in entriesText {
            let block = TextBlock(displayText(entry.text), font: entryFont(), colour: palette.ink)
            // Never shorter than the badge, or a one-word entry's number would
            // sit proud of its own row.
            entryHeights.append(max(block.height(constrainedTo: textWidth), badgeDiameter))
        }

        var legendHeight: CGFloat = 0
        if titleHeight > 0 { legendHeight += titleHeight + titleGap }
        for (index, height) in entryHeights.enumerated() {
            legendHeight += height
            if index < entryHeights.count - 1 { legendHeight += entrySpacing }
        }
        if hasRedactionKey {
            legendHeight += (legendHeight > 0 ? entrySpacing : 0) + badgeDiameter
        }

        let contentHeight = max(captureSize.height, legendHeight)
        let canvasWidth = padding * 2 + captureSize.width + (hasLegend ? columnGap + legendWidth : 0)
        let canvasHeight = padding * 2 + contentHeight
        let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)

        // y-up: subtract from the top rather than adding from the bottom.
        let contentTop = canvasHeight - padding
        let captureRect = CGRect(
            x: padding,
            y: contentTop - captureSize.height,
            width: captureSize.width,
            height: captureSize.height
        )
        let legendX = captureRect.maxX + columnGap
        let legendRect = CGRect(x: legendX, y: contentTop - legendHeight, width: legendWidth, height: legendHeight)

        // Now place the legend's contents, top down.
        var cursor = contentTop
        var titleRect = CGRect.zero
        var ruleY: CGFloat?
        if titleHeight > 0 {
            titleRect = CGRect(x: legendX, y: cursor - titleHeight, width: legendWidth, height: titleHeight)
            cursor -= titleHeight
            ruleY = cursor - titleGap / 2
            cursor -= titleGap
        }

        var entries: [Entry] = []
        for (index, entry) in entriesText.enumerated() {
            let height = entryHeights[index]
            let rowTop = cursor
            entries.append(Entry(
                number: entry.number,
                badgeCentre: CGPoint(
                    x: legendX + badgeDiameter / 2,
                    // Centred on the first line rather than the whole row, so a
                    // three-line entry doesn't leave its number stranded in the
                    // middle of the paragraph.
                    y: rowTop - entryFontSize * 0.5 - 4
                ),
                textRect: CGRect(
                    x: legendX + badgeDiameter + badgeTextGap,
                    y: rowTop - height,
                    width: textWidth,
                    height: height
                ),
                text: displayText(entry.text)
            ))
            cursor -= height
            if index < entriesText.count - 1 { cursor -= entrySpacing }
        }

        var redactionKeyRect: CGRect?
        if hasRedactionKey {
            if !entries.isEmpty { cursor -= entrySpacing }
            redactionKeyRect = CGRect(x: legendX, y: cursor - badgeDiameter, width: legendWidth, height: badgeDiameter)
        }

        return CompositionLayout(
            canvasSize: canvasSize,
            captureRect: captureRect,
            legendRect: legendRect,
            entries: entries,
            titleRect: titleRect,
            ruleY: ruleY,
            redactionKeyRect: redactionKeyRect
        )
    }

    /// An empty description still needs a row, or the number would vanish from
    /// the legend while staying on the image.
    static func displayText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    /// Wide enough for the text to breathe, narrow enough not to dwarf the
    /// picture — and never more than a fraction of the capture's own width, so
    /// a narrow screenshot doesn't end up as a sliver beside a wall of prose.
    private static func legendColumnWidth(title: String, entries: [(number: Int, text: String)], beside captureWidth: CGFloat) -> CGFloat {
        let font = entryFont()
        var widest: CGFloat = TextBlock(title, font: titleFont(), colour: .black).unwrappedWidth()
        for entry in entries {
            let block = TextBlock(displayText(entry.text), font: font, colour: .black)
            widest = max(widest, block.unwrappedWidth() + badgeDiameter + badgeTextGap)
        }

        let generous = min(widest + 8, maximumLegendWidth)
        let proportional = max(captureWidth * 0.42, minimumLegendWidth)
        return min(max(generous, minimumLegendWidth), min(proportional, maximumLegendWidth))
    }
}

private extension CGColor {
    nonisolated static var black: CGColor { CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1) }
}

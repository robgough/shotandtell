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

        // Measured against the legend's *total* width further down, once the
        // number of columns is known — the title spans all of them.
        let titleBlock = (!hasLegend || composition.title.isEmpty) ? nil : TextBlock(composition.title, font: titleFont(), colour: palette.ink)

        let textWidth = legendWidth - badgeDiameter - badgeTextGap
        var entryHeights: [CGFloat] = []
        for entry in entriesText {
            let block = TextBlock(displayText(entry.text), font: entryFont(), colour: palette.ink)
            // Never shorter than the badge, or a one-word entry's number would
            // sit proud of its own row.
            entryHeights.append(max(block.height(constrainedTo: textWidth), badgeDiameter))
        }

        // Stacked in one column, a long legend runs far past the bottom of the
        // screenshot: fifty marks made an image three times taller than it was
        // wide, with the capture stranded in the top corner and acres of empty
        // background under it. Worse for the app's actual purpose than it looks,
        // because a tall ribbon gets downscaled by whatever it's pasted into
        // until the text is unreadable. So the legend flows into columns and the
        // canvas grows sideways instead.
        let columnTarget = max(captureSize.height, minimumColumnHeight)
        let columns = entryColumns(heights: entryHeights, includingRedactionKey: hasRedactionKey, target: columnTarget)
        let legendTotalWidth = CGFloat(columns.count) * legendWidth + CGFloat(columns.count - 1) * columnGap

        let titleHeightAcrossLegend = titleBlock?.height(constrainedTo: legendTotalWidth) ?? 0
        let tallestColumn = columns.map { column in
            column.reduce(CGFloat(0)) { $0 + entryHeights[$1] } + CGFloat(max(0, column.count - 1)) * entrySpacing
        }.max() ?? 0

        var legendHeight = tallestColumn
        if titleHeightAcrossLegend > 0 { legendHeight += titleHeightAcrossLegend + titleGap }
        if hasRedactionKey { legendHeight += entrySpacing + badgeDiameter }

        // Marks are allowed to sit off the edge of the capture — an arrow
        // starting out in the background and pointing into a corner, a box drawn
        // around something right at the edge. The canvas grows to contain them
        // rather than clipping them away, so what you drew is what gets
        // exported.
        let overflow = marginOverflow(composition, captureSize: captureSize)
        let leftPad = max(padding, overflow.left)
        let rightPad = max(padding, overflow.right)
        let topPad = max(padding, overflow.top)
        let bottomPad = max(padding, overflow.bottom)

        let contentHeight = max(captureSize.height, legendHeight)
        let canvasWidth = leftPad + rightPad + captureSize.width + (hasLegend ? columnGap + legendTotalWidth : 0)
        let canvasHeight = topPad + bottomPad + contentHeight
        let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)

        // y-up: subtract from the top rather than adding from the bottom.
        let contentTop = canvasHeight - topPad
        let captureRect = CGRect(
            x: leftPad,
            y: contentTop - captureSize.height,
            width: captureSize.width,
            height: captureSize.height
        )
        let legendX = captureRect.maxX + columnGap
        let legendRect = CGRect(x: legendX, y: contentTop - legendHeight, width: legendTotalWidth, height: legendHeight)

        // Now place the legend's contents, top down.
        var cursor = contentTop
        var titleRect = CGRect.zero
        var ruleY: CGFloat?
        if titleHeightAcrossLegend > 0 {
            // The title and its rule span every column, not just the first.
            titleRect = CGRect(x: legendX, y: cursor - titleHeightAcrossLegend, width: legendTotalWidth, height: titleHeightAcrossLegend)
            cursor -= titleHeightAcrossLegend
            ruleY = cursor - titleGap / 2
            cursor -= titleGap
        }

        let entriesTop = cursor
        var entries: [Entry] = []
        for (columnIndex, column) in columns.enumerated() {
            let columnX = legendX + CGFloat(columnIndex) * (legendWidth + columnGap)
            var columnCursor = entriesTop

            for (positionInColumn, index) in column.enumerated() {
                let height = entryHeights[index]
                let rowTop = columnCursor
                entries.append(Entry(
                    number: entriesText[index].number,
                    badgeCentre: CGPoint(
                        x: columnX + badgeDiameter / 2,
                        // Centred on the first line rather than the whole row, so
                        // a three-line entry doesn't leave its number stranded in
                        // the middle of the paragraph.
                        y: rowTop - entryFontSize * 0.5 - 4
                    ),
                    textRect: CGRect(
                        x: columnX + badgeDiameter + badgeTextGap,
                        y: rowTop - height,
                        width: textWidth,
                        height: height
                    ),
                    text: displayText(entriesText[index].text)
                ))
                columnCursor -= height
                if positionInColumn < column.count - 1 { columnCursor -= entrySpacing }
            }
        }
        cursor = entriesTop - tallestColumn

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

    /// The tallest a single legend column should get before a second one is
    /// started. Keeps a short capture from forcing one entry per column.
    static let minimumColumnHeight: CGFloat = 420

    /// The most columns worth flowing into. Past this the legend is so long that
    /// the picture has stopped being the point, and a taller image is the lesser
    /// evil against columns too narrow to read.
    static let maximumLegendColumns = 3

    /// Distributes entries into columns, each filled to roughly `target` before
    /// the next is started.
    ///
    /// Returns indices rather than entries so the caller keeps its own ordering
    /// and measurements. Reading order is down each column then across, which is
    /// how a numbered list is read on paper.
    private static func entryColumns(
        heights: [CGFloat],
        includingRedactionKey: Bool,
        target: CGFloat
    ) -> [[Int]] {
        guard !heights.isEmpty else { return [[]] }

        let spacing = entrySpacing
        var total = heights.reduce(0, +) + CGFloat(heights.count - 1) * spacing
        if includingRedactionKey { total += spacing + badgeDiameter }

        let wanted = min(maximumLegendColumns, max(1, Int((total / target).rounded(.up))))
        guard wanted > 1 else { return [Array(heights.indices)] }

        // Aim each column at an equal share, so the columns end up level rather
        // than the last one holding a stub.
        let share = total / CGFloat(wanted)
        var columns: [[Int]] = []
        var current: [Int] = []
        var currentHeight: CGFloat = 0

        for index in heights.indices {
            let height = heights[index]
            let projected = currentHeight + (current.isEmpty ? 0 : spacing) + height
            // Never leave a column empty, and never start a new one once the
            // last is open — the remainder has to go somewhere.
            if !current.isEmpty, projected > share, columns.count < wanted - 1 {
                columns.append(current)
                current = [index]
                currentHeight = height
            } else {
                current.append(index)
                currentHeight = projected
            }
        }
        columns.append(current)
        return columns
    }

    /// How far past each edge of the capture the marks reach, in points.
    ///
    /// Measured from the annotation bounds plus the radius of the number badge,
    /// which is drawn centred on its anchor and so sticks out past the geometry
    /// it belongs to.
    private static func marginOverflow(
        _ composition: Composition,
        captureSize: CGSize
    ) -> (left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
        let allowance = markerDiameter / 2 + 4
        var left: CGFloat = 0, right: CGFloat = 0, top: CGFloat = 0, bottom: CGFloat = 0

        for annotation in composition.annotations {
            let bounds = annotation.bounds
            left = max(left, -bounds.minX * captureSize.width + allowance)
            right = max(right, (bounds.maxX - 1) * captureSize.width + allowance)
            // Normalised y runs downwards from the top of the capture.
            top = max(top, -bounds.minY * captureSize.height + allowance)
            bottom = max(bottom, (bounds.maxY - 1) * captureSize.height + allowance)
        }
        return (left, right, top, bottom)
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

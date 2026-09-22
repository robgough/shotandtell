import CoreGraphics
import CoreText
import Foundation

/// Turns a `Composition` into the finished image.
///
/// This is the single source of truth for what the output looks like. The
/// editor previews by rendering *this*, at whatever scale fits the window,
/// rather than drawing its own approximation in SwiftUI — two renderers of the
/// same thing always drift, and "what you see is what you get" is the whole
/// promise of the editor.
nonisolated enum Compositor {
    struct Output: @unchecked Sendable {
        let image: CGImage
        /// The layout that produced it, so the caller can map a point in the
        /// rendered image back onto the capture.
        let layout: CompositionLayout
    }

    enum Failure: Error {
        case couldNotCreateContext
        case couldNotRender
    }

    /// `scale` is pixels per point: 1 for a quick preview, 2 for export.
    /// `drawsBackground: false` leaves the canvas transparent, for callers that
    /// paint the background themselves across a larger area — the editor does
    /// this so the composition's colour runs to the edges of the window instead
    /// of stopping at a rectangle floating in the middle of it.
    static func render(
        _ composition: Composition,
        scale: CGFloat,
        includeLegend: Bool = true,
        drawsBackground: Bool = true
    ) throws -> Output {
        let palette = Palette.resolve(
            background: composition.background,
            appearance: composition.appearance,
            markerColour: composition.markerColour
        )
        let layout = CompositionLayout.solve(composition, palette: palette, includeLegend: includeLegend)

        let pixelWidth = Int((layout.canvasSize.width * scale).rounded())
        let pixelHeight = Int((layout.canvasSize.height * scale).rounded())

        guard pixelWidth > 0, pixelHeight > 0,
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else {
            throw Failure.couldNotCreateContext
        }

        context.scaleBy(x: scale, y: scale)
        // The bitmap is a whole number of pixels but the canvas is fractional
        // once the export cap kicks in, so drawing exactly `canvasSize` can
        // leave the last row half-covered and semi-transparent. Everything is
        // drawn against this slightly larger rect instead.
        let drawnSize = CGSize(width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high

        if drawsBackground {
            drawBackground(palette: palette, in: CGRect(origin: .zero, size: drawnSize), context: context)
        }
        drawCapture(composition, layout: layout, palette: palette, in: context)
        drawAnnotations(composition, layout: layout, palette: palette, in: context)
        drawLegend(composition, layout: layout, palette: palette, in: context)

        guard let image = context.makeImage() else { throw Failure.couldNotRender }
        return Output(image: image, layout: layout)
    }

    // MARK: - Canvas

    /// Shared with the editor's canvas, which paints the same background across
    /// its whole viewport. Both must use this one implementation or the gradient
    /// in the image and the gradient behind it meet at a visible seam.
    static func drawBackground(palette: Palette, in bounds: CGRect, context: CGContext) {

        guard palette.canvasIsGradient else {
            context.setFillColor(palette.canvasTop)
            context.fill(bounds)
            return
        }

        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [palette.canvasTop, palette.canvasBottom] as CFArray,
            locations: [0, 1]
        ) else {
            context.setFillColor(palette.canvasTop)
            context.fill(bounds)
            return
        }

        context.saveGState()
        context.clip(to: bounds)
        // Top to bottom, in a y-up space, so the first colour is the one at the
        // top of the finished picture.
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: bounds.midX, y: bounds.maxY),
            end: CGPoint(x: bounds.midX, y: bounds.minY),
            options: []
        )
        context.restoreGState()
    }

    private static func drawCapture(_ composition: Composition, layout: CompositionLayout, palette: Palette, in context: CGContext) {
        let rect = layout.captureRect

        guard composition.background.insetsCapture else {
            context.draw(composition.capture.image, in: rect)
            return
        }

        // A window capture already has its own rounded corners cut out of the
        // alpha, and they are not the same radius as ours. Clipping a second
        // shape over the first leaves a wedge between the two curves, and the
        // opaque shape drawn to cast the shadow shows through it as a dark
        // notch in the corner. So: let the window keep its own outline, and cast
        // the shadow from the image's alpha rather than from a rectangle.
        if composition.capture.source.hasOwnShape {
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -10),
                blur: 26,
                color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28)
            )
            context.draw(composition.capture.image, in: rect)
            context.restoreGState()
            return
        }

        let path = CGPath(
            roundedRect: rect,
            cornerWidth: CompositionLayout.captureCornerRadius,
            cornerHeight: CompositionLayout.captureCornerRadius,
            transform: nil
        )

        // The shadow is cast by an opaque shape drawn first, not by the image
        // itself — a screenshot with transparent corners would otherwise cast a
        // shadow through them. That shape is filled with the canvas colour
        // rather than black, so where the rounded corners antialias the image
        // against it the blend goes towards the background instead of towards a
        // dark fringe.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -10),
            blur: 26,
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.20)
        )
        context.addPath(path)
        context.setFillColor(palette.canvasTop)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.clip()
        context.draw(composition.capture.image, in: rect)
        context.restoreGState()

        // Stroked half a point outside the image, so the whole line sits in the
        // margin. A 1pt stroke centred on the path would put half of itself over
        // the outermost row of captured pixels and tint it — measurably: a flat
        // grey capture came out at 141 down its edge instead of 128. Every pixel
        // of the screenshot has to survive intact, because something is going to
        // read it.
        context.addPath(CGPath(
            roundedRect: rect.insetBy(dx: -0.5, dy: -0.5),
            cornerWidth: CompositionLayout.captureCornerRadius + 0.5,
            cornerHeight: CompositionLayout.captureCornerRadius + 0.5,
            transform: nil
        ))
        context.setStrokeColor(palette.captureBorder)
        context.setLineWidth(1)
        context.strokePath()
    }

    // MARK: - Annotations

    private static func drawAnnotations(_ composition: Composition, layout: CompositionLayout, palette: Palette, in context: CGContext) {
        let capture = layout.captureRect

        // Redactions first and separately: they must cover the capture, and they
        // must never be covered by a marker that happens to overlap. They are
        // the only annotation clipped to the capture — covering up part of the
        // background would be meaningless.
        context.saveGState()
        context.addPath(clipPath(for: composition, rect: capture))
        context.clip()
        for redaction in composition.redactions {
            guard case let .redaction(normalised) = redaction.kind else { continue }
            drawRedaction(denormalise(normalised, in: capture), palette: palette, in: context)
        }
        context.restoreGState()

        // Marks are deliberately *not* clipped to the capture: the layout grew
        // the canvas to make room for anything hanging over the edge.
        withMarkShadow(in: context) {
            for (number, annotation) in composition.numbered {
                drawMark(annotation.kind, number: number, capture: capture, palette: palette, in: context)
            }
        }
    }

    /// One numbered mark, in layout coordinates. Also how the editor draws the
    /// mark you're in the middle of dragging out, so the preview is the real
    /// thing — colour, weight, badge and number — rather than an outline that
    /// changes into something else when you let go.
    static func drawMark(_ kind: Annotation.Kind, number: Int, capture: CGRect, palette: Palette, in context: CGContext) {
        switch kind {
        case let .pin(point):
            drawMarker(number: number, centre: denormalise(point, in: capture), palette: palette, in: context)

        case let .arrow(from, to):
            drawArrow(
                from: denormalise(from, in: capture),
                to: denormalise(to, in: capture),
                palette: palette,
                in: context
            )
            drawMarker(number: number, centre: denormalise(from, in: capture), palette: palette, in: context)

        case let .box(normalised):
            let rect = denormalise(normalised, in: capture)
            context.setStrokeColor(palette.marker)
            context.setLineWidth(2.5)
            context.addPath(CGPath(roundedRect: rect.insetBy(dx: 1.25, dy: 1.25), cornerWidth: 4, cornerHeight: 4, transform: nil))
            context.strokePath()
            drawMarker(number: number, centre: CGPoint(x: rect.minX, y: rect.maxY), palette: palette, in: context)

        case let .redaction(normalised):
            drawRedaction(denormalise(normalised, in: capture), palette: palette, in: context)
        }
    }

    static func drawRedaction(_ rect: CGRect, palette: Palette, in context: CGContext) {
        context.setFillColor(palette.redaction)
        // Square corners, and half a point of overdraw. A rounded corner
        // leaves a few of the original pixels showing in the notch, and the
        // antialiased boundary row blends with what's underneath — a small
        // nibble, but the entire point of an opaque fill is that nothing
        // under it survives. Cosmetics lose this argument.
        context.fill(rect.insetBy(dx: -0.5, dy: -0.5))
    }

    /// A soft shadow under the marks, so they sit visibly *on* the screenshot
    /// rather than looking printed into it — a thin arrow over a busy UI
    /// otherwise reads as part of the UI.
    ///
    /// Everything is drawn into one transparency layer and the layer casts the
    /// shadow, rather than each stroke and badge casting its own: an arrow's
    /// shaft, head and badge overlap, and separate shadows darken where they
    /// stack.
    ///
    /// Shadow offset and blur are specified in device space, not user space —
    /// Core Graphics doesn't apply the transform to them — so they're scaled by
    /// hand. Without that, a 2x export gets a shadow half the size of the one on
    /// screen.
    static func withMarkShadow(in context: CGContext, _ draw: () -> Void) {
        let scale = abs(context.ctm.a)
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -1 * scale),
            blur: 3 * scale,
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.4)
        )
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        draw()
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// Markers are clipped to the capture's rounded rectangle so one dropped
    /// near the edge can't spill onto the background.
    private static func clipPath(for composition: Composition, rect: CGRect) -> CGPath {
        guard composition.background.insetsCapture else { return CGPath(rect: rect, transform: nil) }
        return CGPath(
            roundedRect: rect,
            cornerWidth: CompositionLayout.captureCornerRadius,
            cornerHeight: CompositionLayout.captureCornerRadius,
            transform: nil
        )
    }

    private static func drawMarker(number: Int, centre: CGPoint, palette: Palette, in context: CGContext) {
        let diameter = CompositionLayout.markerDiameter
        let rect = CGRect(x: centre.x - diameter / 2, y: centre.y - diameter / 2, width: diameter, height: diameter)

        // A ring, so the marker stays legible on a screenshot that happens to be
        // the same colour as the marker. The same colour as the numeral: white
        // around a white number, and dark around the dark number a pale marker
        // gets. A white ring around a black number reads as two different
        // badges stacked.
        context.setFillColor(palette.markerInk.copy(alpha: 0.95) ?? palette.markerInk)
        context.fillEllipse(in: rect.insetBy(dx: -2, dy: -2))

        context.setFillColor(palette.marker)
        context.fillEllipse(in: rect)

        drawCentred(
            "\(number)",
            font: TextBlock.font(size: 13, emphasised: true),
            colour: palette.markerInk,
            centre: centre,
            in: context
        )
    }

    /// A tapered arrow: a fine tail that swells towards a swept, notched head,
    /// drawn as one filled shape with an outline in the badge ring's colour.
    ///
    /// A constant-width line with a triangle on the end reads as a diagram
    /// connector, and on a busy screenshot it's easily taken for part of the UI.
    /// The taper gives it direction before you reach the head, and the outline
    /// keeps it legible when it crosses something of its own colour — the same
    /// job the ring does for the badge.
    ///
    /// The head grows with the arrow, within limits, so a short arrow isn't all
    /// head and a long one doesn't end in a pinhead.
    private static func drawArrow(from: CGPoint, to: CGPoint, palette: Palette, in context: CGContext) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = (dx * dx + dy * dy).squareRoot()

        // Start the tail just outside the number badge rather than under it.
        let inset = CompositionLayout.markerDiameter / 2 + 3
        let length = distance - inset
        guard length > 12 else { return }

        let headLength = min(max(length * 0.26, 15), 24)
        let headHalfWidth = headLength * 0.6
        // The barbs sweep back past the point where the shaft joins the head,
        // which is what gives the head its notch.
        let neck = length - headLength * 0.7
        let barb = length - headLength
        let tailHalfWidth: CGFloat = 1.4
        let neckHalfWidth = min(max(headLength * 0.17, 2.6), 3.8)

        // Built pointing along +x from the origin, then turned and moved into
        // place, which keeps the geometry readable.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: tailHalfWidth))
        path.addLine(to: CGPoint(x: neck, y: neckHalfWidth))
        path.addLine(to: CGPoint(x: barb, y: headHalfWidth))
        path.addLine(to: CGPoint(x: length, y: 0))
        path.addLine(to: CGPoint(x: barb, y: -headHalfWidth))
        path.addLine(to: CGPoint(x: neck, y: -neckHalfWidth))
        path.addLine(to: CGPoint(x: 0, y: -tailHalfWidth))
        // A round tail rather than a square cut.
        path.addArc(center: .zero, radius: tailHalfWidth,
                    startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: true)
        path.closeSubpath()

        let angle = atan2(dy, dx)
        let origin = CGPoint(x: from.x + dx / distance * inset, y: from.y + dy / distance * inset)
        var transform = CGAffineTransform(translationX: origin.x, y: origin.y).rotated(by: angle)
        guard let placed = path.copy(using: &transform) else { return }

        // Outline first, then the fill over its inner half, so only the outer
        // half of the stroke shows.
        context.saveGState()
        context.addPath(placed)
        context.setStrokeColor(palette.markerInk.copy(alpha: 0.95) ?? palette.markerInk)
        context.setLineWidth(3)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()

        context.addPath(placed)
        context.setFillColor(palette.marker)
        context.fillPath()
    }

    // MARK: - Legend

    private static func drawLegend(_ composition: Composition, layout: CompositionLayout, palette: Palette, in context: CGContext) {
        // An empty legendRect means the layout left the column out entirely.
        guard !composition.legendIsEmpty, layout.legendRect.width > 0 else { return }

        if !composition.title.isEmpty {
            TextBlock(composition.title, font: CompositionLayout.titleFont(), colour: palette.ink)
                .draw(in: layout.titleRect, context: context)
        }

        if let ruleY = layout.ruleY {
            context.setFillColor(palette.rule)
            context.fill(CGRect(x: layout.legendRect.minX, y: ruleY, width: layout.legendRect.width, height: 1))
        }

        for entry in layout.entries {
            let diameter = CompositionLayout.badgeDiameter
            context.setFillColor(palette.marker)
            context.fillEllipse(in: CGRect(
                x: entry.badgeCentre.x - diameter / 2,
                y: entry.badgeCentre.y - diameter / 2,
                width: diameter,
                height: diameter
            ))
            drawCentred(
                "\(entry.number)",
                font: TextBlock.font(size: 11, emphasised: true),
                colour: palette.markerInk,
                centre: entry.badgeCentre,
                in: context
            )

            TextBlock(entry.text, font: CompositionLayout.entryFont(), colour: palette.ink)
                .draw(in: entry.textRect, context: context)
        }

        if let keyRect = layout.redactionKeyRect {
            let swatch = CGRect(x: keyRect.minX, y: keyRect.midY - 7, width: 22, height: 14)
            context.setFillColor(palette.redaction)
            context.addPath(CGPath(roundedRect: swatch, cornerWidth: 3, cornerHeight: 3, transform: nil))
            context.fillPath()

            let label = TextBlock("Redacted", font: CompositionLayout.entryFont(), colour: palette.inkSecondary)
            let height = label.height(constrainedTo: keyRect.width - 32)
            label.draw(in: CGRect(x: swatch.maxX + 10, y: keyRect.midY - height / 2, width: keyRect.width - 32, height: height), context: context)
        }
    }

    // MARK: - Helpers

    private static func drawCentred(_ string: String, font: CTFont, colour: CGColor, centre: CGPoint, in context: CGContext) {
        let attributed = NSAttributedString(string: string, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: colour,
        ])
        let line = CTLineCreateWithAttributedString(attributed)

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))

        context.textPosition = CGPoint(
            x: centre.x - width / 2,
            y: centre.y - (ascent - descent) / 2
        )
        CTLineDraw(line, context)
    }

    /// Normalised (top-left origin, 0…1) to canvas points (y-up).
    static func denormalise(_ point: CGPoint, in captureRect: CGRect) -> CGPoint {
        CGPoint(
            x: captureRect.minX + point.x * captureRect.width,
            y: captureRect.maxY - point.y * captureRect.height
        )
    }

    static func denormalise(_ rect: CGRect, in captureRect: CGRect) -> CGRect {
        let topLeft = denormalise(CGPoint(x: rect.minX, y: rect.minY), in: captureRect)
        let bottomRight = denormalise(CGPoint(x: rect.maxX, y: rect.maxY), in: captureRect)
        return CGRect(
            x: topLeft.x,
            y: bottomRight.y,
            width: bottomRight.x - topLeft.x,
            height: topLeft.y - bottomRight.y
        )
    }

    /// Canvas points (y-up) back to normalised — what the editor needs to turn a
    /// click into an annotation.
    static func normalise(_ point: CGPoint, in captureRect: CGRect) -> CGPoint {
        guard captureRect.width > 0, captureRect.height > 0 else { return .zero }
        return CGPoint(
            x: (point.x - captureRect.minX) / captureRect.width,
            y: (captureRect.maxY - point.y) / captureRect.height
        )
    }
}

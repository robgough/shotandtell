import AppKit
import SwiftUI

/// The canvas: the composited image, drawn exactly as it will be exported, with
/// the editor's own chrome (selection rings, the shape you're currently
/// dragging out) painted on top rather than baked into it.
///
/// Rendering the real compositor output rather than a SwiftUI approximation is
/// the point. The alternative — draw markers twice, once for the screen and
/// once for export — guarantees the two drift apart.
final class CompositionCanvasView: NSView {
    var document: EditorDocument? {
        didSet { invalidate() }
    }

    private var cachedImage: CGImage?
    private var cachedLayout: CompositionLayout?
    private var cachedPalette: Palette?
    private var cacheIsStale = true

    /// Where the composition is drawn inside the view, and how much it was
    /// scaled to get there. Everything about hit testing follows from these.
    ///
    /// Zoomed in, `fitRect` is bigger than the view and `fitScale` is the zoom;
    /// everything that converts between view and canvas goes through these two,
    /// so hit testing, handles and drawing all follow the zoom without knowing
    /// about it.
    private var fitRect: CGRect = .zero
    private var fitScale: CGFloat = 1

    /// Pixels per canvas point the cached image was rendered at.
    private var cachedRenderScale: CGFloat = 0
    /// While zoomed in, the canvas point at the middle of the visible area.
    /// Stored in canvas space so zooming by the menu or the button keeps the
    /// same thing in the middle without anything else to do.
    private var panCentre: CGPoint?
    /// True mid-gesture. The cache isn't re-rendered while a pinch or ⌘-scroll
    /// is changing the scale every frame — on a big capture that's tens of
    /// milliseconds a time — so the last one is stretched until it settles.
    private var isZooming = false
    private var zoomSettle: DispatchWorkItem?

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var movingID: UUID?
    private var lastMovePoint: CGPoint?

    /// Which handle of the selected mark is being dragged, and the normalised
    /// point that stays put while it moves — the opposite corner of a box, or
    /// the other end of an arrow.
    private var resizing: (id: UUID, handle: Handle, anchor: CGPoint)?

    /// How far a mark may go during the current gesture, in normalised
    /// coordinates — fixed at mouse-down.
    ///
    /// Fixed because the canvas grows to fit a mark that reaches into the
    /// margin, which refits it smaller, which puts the same cursor position
    /// further out again. Recomputing each drag event would let a mark held at
    /// the edge of the window creep outwards on every mouse move.
    private var gestureBounds: CGRect?

    enum Handle: CaseIterable {
        case bottomLeft, bottomRight, topLeft, topRight
        /// Arrows resize by their ends rather than by a bounding box.
        case arrowTail, arrowHead
    }

    private static let handleSize: CGFloat = 8

    /// Room left clear along the bottom for the zoom, colour and background
    /// buttons: their 16pt margin, their height, and a gap above them.
    ///
    /// They're glass, and take their text colour from the composition's
    /// background. Zoomed in, the screenshot used to slide in under them, and a
    /// light screenshot under light-on-dark text made them all but invisible.
    /// Keeping the composition out of this strip means they always sit on the
    /// background they were matched to.
    static let controlsInset: CGFloat = 58

    /// Where the composition may be drawn: under the toolbar's safe area, and
    /// above the controls.
    private var contentArea: CGRect {
        let area = safeAreaRect
        return CGRect(x: area.minX, y: area.minY + Self.controlsInset,
                      width: area.width, height: max(0, area.height - Self.controlsInset))
    }

    override var isFlipped: Bool { false }
    /// The whole view is painted now, so AppKit can skip whatever is behind it.
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func invalidate() {
        cacheIsStale = true
        needsDisplay = true
    }

    // MARK: - Rendering

    private func rerenderIfNeeded() {
        guard let document else { return }
        let composition = document.composition

        let palette = Palette.resolve(
            background: composition.background,
            appearance: composition.appearance,
            markerColour: composition.markerColour
        )
        cachedPalette = palette
        // No legend on the canvas: the panel to the right is the legend, and
        // showing it twice just makes the screenshot smaller.
        let layout = CompositionLayout.solve(composition, palette: palette, includeLegend: false)
        cachedLayout = layout

        // contentArea, not bounds: the canvas runs underneath the window's
        // toolbar and the controls along the bottom, and the composition
        // shouldn't be fitted into the parts of itself they cover.
        let area = contentArea
        let fitted = Self.fit(layout.canvasSize, in: area)
        let fitsAt = layout.canvasSize.width > 0 ? fitted.width / layout.canvasSize.width : 1
        if abs(document.fitScale - fitsAt) > 0.0005 {
            // Next cycle: this runs inside draw(_:), and changing observed state
            // here would have SwiftUI updating while AppKit is mid-draw.
            DispatchQueue.main.async { [weak document] in document?.fitScale = fitsAt }
        }

        let scale = document.magnification.map { min(max($0, fitsAt), EditorDocument.maximumMagnification) } ?? fitsAt
        if scale <= fitsAt * 1.001 {
            fitRect = fitted
            panCentre = nil
        } else {
            let size = CGSize(width: layout.canvasSize.width * scale, height: layout.canvasSize.height * scale)
            let centre = panCentre ?? CGPoint(x: layout.canvasSize.width / 2, y: layout.canvasSize.height / 2)
            // Centred on an axis where it still fits; otherwise positioned by
            // the pan and kept from sliding off so far it leaves a gap.
            func origin(_ length: CGFloat, _ lower: CGFloat, _ upper: CGFloat, _ middle: CGFloat) -> CGFloat {
                let span = upper - lower
                if length <= span { return lower + (span - length) / 2 }
                return min(max((lower + upper) / 2 - middle * scale, upper - length), lower)
            }
            let x = origin(size.width, area.minX, area.maxX, centre.x)
            let y = origin(size.height, area.minY, area.maxY, centre.y)
            fitRect = CGRect(x: x, y: y, width: size.width, height: size.height)
            panCentre = CGPoint(x: (area.midX - x) / scale, y: (area.midY - y) / scale)
        }
        fitScale = scale

        // As many pixels as are shown, but never more than the screenshot has:
        // past its own resolution, extra pixels would only be interpolated.
        // Zooming in beyond that shows the screenshot's pixels as pixels
        // instead — see draw(_:).
        let backing = window?.backingScaleFactor ?? 2
        let native = max(composition.capture.scale, backing)
        let wanted = max(0.5, min(scale * backing, native))
        let scaleIsOff = cachedRenderScale == 0 || abs(wanted - cachedRenderScale) / cachedRenderScale > 0.05

        guard cacheIsStale || cachedImage == nil || (scaleIsOff && !isZooming) else { return }

        // Without its background, because the view paints that across its
        // whole area, and without its marks, because draw(_:) draws those live
        // on top — sharp at any zoom, where these pixels won't be.
        cachedImage = try? Compositor.render(
            composition,
            scale: wanted,
            includeLegend: false,
            drawsBackground: false,
            drawsAnnotations: false
        ).image
        cachedRenderScale = wanted
        cacheIsStale = false
    }

    private static func fit(_ size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height, 1)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: bounds.minX + (bounds.width - fitted.width) / 2,
            y: bounds.minY + (bounds.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        rerenderIfNeeded()
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // The composition's own background, edge to edge. Drawn here rather than
        // baked into the image so the window becomes the composition instead of
        // a tinted rectangle marooned in a grey void — and drawn by the
        // compositor's own routine so the gradient can't seam against itself.
        if let cachedPalette {
            Compositor.drawBackground(palette: cachedPalette, in: bounds, context: context)
        }

        // Zoomed in, the composition is bigger than the view. It stops at the
        // legend panel, rather than smearing through its glass. Under the
        // toolbar and the controls strip it carries on — the strip is veiled
        // afterwards, in drawControlsStrip.
        let area = contentArea
        context.saveGState()
        context.clip(to: CGRect(x: area.minX, y: bounds.minY, width: area.width, height: bounds.height))
        defer { context.restoreGState() }

        if let cachedImage {
            // Magnified to twice the rendered resolution or more, show the
            // screenshot's pixels as crisp squares rather than smearing them:
            // that far in, the point is to see exactly where an edge is.
            let shown = fitScale * (window?.backingScaleFactor ?? 2)
            context.interpolationQuality = shown >= cachedRenderScale * 1.99 ? .none : .high
            context.draw(cachedImage, in: fitRect)
        }

        drawMarks(in: context)
        drawSelection(in: context)
        drawDragPreview(in: context)
        drawControlsStrip(in: context)
    }

    /// A band of the background colour behind the bottom controls, mostly
    /// opaque, so a zoomed-in screenshot scrolling under them shows through
    /// faintly without taking their legibility with it. Its top fades in, the
    /// way content goes under a toolbar.
    ///
    /// Only drawn when something is actually under the strip: at Fit the
    /// composition stops above it and there's nothing to veil.
    private func drawControlsStrip(in context: CGContext) {
        guard let palette = cachedPalette else { return }
        let area = contentArea
        guard fitRect.minY < area.minY - 0.5 else { return }

        let strip = CGRect(x: area.minX, y: bounds.minY, width: area.width, height: area.minY - bounds.minY)
        let fade: CGFloat = 12
        let solid = palette.canvasBottom.copy(alpha: 0.86) ?? palette.canvasBottom
        let clear = palette.canvasBottom.copy(alpha: 0) ?? palette.canvasBottom

        context.setFillColor(solid)
        context.fill(CGRect(x: strip.minX, y: strip.minY, width: strip.width, height: strip.height - fade))

        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                     colors: [solid, clear] as CFArray, locations: [0, 1]) {
            context.saveGState()
            context.clip(to: CGRect(x: strip.minX, y: strip.maxY - fade, width: strip.width, height: fade))
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: strip.midX, y: strip.maxY - fade),
                                       end: CGPoint(x: strip.midX, y: strip.maxY), options: [])
            context.restoreGState()
        }
    }

    /// The marks, drawn by the compositor in view space every time, so they're
    /// as sharp at 400% as at fit.
    private func drawMarks(in context: CGContext) {
        guard let document, let layout = cachedLayout, let palette = cachedPalette else { return }
        context.saveGState()
        context.translateBy(x: fitRect.minX, y: fitRect.minY)
        context.scaleBy(x: fitScale, y: fitScale)
        Compositor.drawAnnotations(document.composition, layout: layout, palette: palette, in: context)
        context.restoreGState()
    }

    private func drawSelection(in context: CGContext) {
        guard let document, let layout = cachedLayout, let id = document.selection,
              let annotation = document.composition.annotations.first(where: { $0.id == id })
        else { return }

        let rect = canvasRect(for: annotation, layout: layout)
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [4, 3])
        context.stroke(viewRect(rect).insetBy(dx: -4, dy: -4))
        context.setLineDash(phase: 0, lengths: [])

        for (_, point) in handles(for: annotation, layout: layout) {
            let box = CGRect(
                x: point.x - Self.handleSize / 2,
                y: point.y - Self.handleSize / 2,
                width: Self.handleSize,
                height: Self.handleSize
            )
            context.setFillColor(NSColor.white.cgColor)
            context.fill(box)
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(1)
            context.stroke(box)
        }
    }

    /// Handle positions in view coordinates. Pins have none — they're a point,
    /// and there's nothing to resize.
    private func handles(for annotation: Annotation, layout: CompositionLayout) -> [(Handle, CGPoint)] {
        switch annotation.kind {
        case .pin:
            return []
        case let .arrow(from, to):
            return [
                (.arrowTail, viewPoint(Compositor.denormalise(from, in: layout.captureRect))),
                (.arrowHead, viewPoint(Compositor.denormalise(to, in: layout.captureRect))),
            ]
        case .box, .redaction:
            let rect = viewRect(canvasRect(for: annotation, layout: layout))
            return [
                (.bottomLeft, CGPoint(x: rect.minX, y: rect.minY)),
                (.bottomRight, CGPoint(x: rect.maxX, y: rect.minY)),
                (.topLeft, CGPoint(x: rect.minX, y: rect.maxY)),
                (.topRight, CGPoint(x: rect.maxX, y: rect.maxY)),
            ]
        }
    }

    /// The normalised point that must stay still while `handle` is dragged.
    private func anchor(for handle: Handle, of annotation: Annotation) -> CGPoint {
        switch (handle, annotation.kind) {
        case let (.arrowTail, .arrow(_, to)): to
        case let (.arrowHead, .arrow(from, _)): from
        case let (.bottomLeft, .box(rect)), let (.bottomLeft, .redaction(rect)): CGPoint(x: rect.maxX, y: rect.minY)
        case let (.bottomRight, .box(rect)), let (.bottomRight, .redaction(rect)): CGPoint(x: rect.minX, y: rect.minY)
        case let (.topLeft, .box(rect)), let (.topLeft, .redaction(rect)): CGPoint(x: rect.maxX, y: rect.maxY)
        case let (.topRight, .box(rect)), let (.topRight, .redaction(rect)): CGPoint(x: rect.minX, y: rect.maxY)
        default: .zero
        }
    }

    /// The mark being dragged out, drawn by the compositor itself in the
    /// composition's marker colour, with the number it's about to get. It used
    /// to be a thin outline in the system accent colour, which meant a red box
    /// was drawn in blue until you let go of it.
    ///
    /// The endpoints go through the same margin clamping as `mouseUp`, so what
    /// you see while dragging is what lands.
    private func drawDragPreview(in context: CGContext) {
        guard let document, let start = dragStart, let current = dragCurrent, document.tool.isDragged,
              let layout = cachedLayout, let palette = cachedPalette
        else { return }

        let from = normalisedAllowingMargin(start, layout: layout)
        let to = normalisedAllowingMargin(current, layout: layout)
        let rect = CGRect(x: min(from.x, to.x), y: min(from.y, to.y),
                          width: abs(to.x - from.x), height: abs(to.y - from.y))
        let number = document.composition.numbered.count + 1

        context.saveGState()
        defer { context.restoreGState() }
        // Into layout space, the same mapping the cached image is drawn with.
        context.translateBy(x: fitRect.minX, y: fitRect.minY)
        context.scaleBy(x: fitScale, y: fitScale)

        switch document.tool {
        case .arrow:
            Compositor.withMarkShadow(in: context) {
                Compositor.drawMark(.arrow(from: from, to: to), number: number,
                                    capture: layout.captureRect, palette: palette, in: context)
            }
        case .box:
            Compositor.withMarkShadow(in: context) {
                Compositor.drawMark(.box(rect), number: number,
                                    capture: layout.captureRect, palette: palette, in: context)
            }
        case .redact:
            // Clipped to the capture, as the export is: a redaction only ever
            // covers the screenshot.
            context.clip(to: layout.captureRect)
            Compositor.drawMark(.redaction(rect), number: 0,
                                capture: layout.captureRect, palette: palette, in: context)
        default:
            break
        }
    }

    // MARK: - Coordinates

    /// View point to composition-canvas point. Both spaces are y-up, so this is
    /// only an offset and a scale.
    private func canvasPoint(_ viewPoint: CGPoint) -> CGPoint {
        guard fitScale > 0 else { return .zero }
        return CGPoint(x: (viewPoint.x - fitRect.minX) / fitScale, y: (viewPoint.y - fitRect.minY) / fitScale)
    }

    private func viewPoint(_ canvasPoint: CGPoint) -> CGPoint {
        CGPoint(x: fitRect.minX + canvasPoint.x * fitScale, y: fitRect.minY + canvasPoint.y * fitScale)
    }

    private func viewRect(_ canvasRect: CGRect) -> CGRect {
        CGRect(
            x: fitRect.minX + canvasRect.minX * fitScale,
            y: fitRect.minY + canvasRect.minY * fitScale,
            width: canvasRect.width * fitScale,
            height: canvasRect.height * fitScale
        )
    }

    /// Normalised position, allowed to fall outside the capture anywhere on the
    /// visible canvas.
    ///
    /// Boxing something in a corner, or starting an arrow out in the background
    /// and pointing it inwards, both mean working in the margin. The layout
    /// grows the canvas to fit whatever lands there. This used to stop at the
    /// composition's own 44pt padding, which left a sliver you had to hit
    /// exactly — the limit is now wherever you can click.
    private func normalisedAllowingMargin(_ viewPoint: CGPoint, layout: CompositionLayout) -> CGPoint {
        let bounds = gestureBounds ?? reachableBounds(layout: layout)
        let point = Compositor.normalise(canvasPoint(viewPoint), in: layout.captureRect)
        return CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    /// The part of the view a mark can be put in, as a normalised rectangle:
    /// everything below the toolbar, and never less than the old padding
    /// allowance, so a window sized tight around the composition doesn't
    /// shrink it.
    private func reachableBounds(layout: CompositionLayout) -> CGRect {
        let area = contentArea
        let a = Compositor.normalise(canvasPoint(CGPoint(x: area.minX, y: area.minY)), in: layout.captureRect)
        let b = Compositor.normalise(canvasPoint(CGPoint(x: area.maxX, y: area.maxY)), in: layout.captureRect)
        let visible = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))

        let padding = CGVector(
            dx: CompositionLayout.padding / max(layout.captureRect.width, 1),
            dy: CompositionLayout.padding / max(layout.captureRect.height, 1)
        )
        let minimum = CGRect(x: -padding.dx, y: -padding.dy, width: 1 + padding.dx * 2, height: 1 + padding.dy * 2)
        return visible.union(minimum)
    }

    /// Normalised position on the capture, or nil if the point isn't on it —
    /// used by the pin tool, which has no reason to drop a number in the
    /// margin with nothing under it.
    private func normalised(_ viewPoint: CGPoint) -> CGPoint? {
        guard let layout = cachedLayout else { return nil }
        let point = canvasPoint(viewPoint)
        guard layout.captureRect.insetBy(dx: -2, dy: -2).contains(point) else { return nil }
        return Compositor.normalise(point, in: layout.captureRect).clampedToUnitSquare()
    }

    private func canvasRect(for annotation: Annotation, layout: CompositionLayout) -> CGRect {
        switch annotation.kind {
        case let .pin(point):
            let centre = Compositor.denormalise(point, in: layout.captureRect)
            let d = CompositionLayout.markerDiameter
            return CGRect(x: centre.x - d / 2, y: centre.y - d / 2, width: d, height: d)
        case let .arrow(from, to):
            let a = Compositor.denormalise(from, in: layout.captureRect)
            let b = Compositor.denormalise(to, in: layout.captureRect)
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
                .insetBy(dx: -CompositionLayout.markerDiameter / 2, dy: -CompositionLayout.markerDiameter / 2)
        case let .box(rect), let .redaction(rect):
            return Compositor.denormalise(rect, in: layout.captureRect)
        }
    }

    // MARK: - Zoom

    /// Pinch to zoom, around the pointer.
    override func magnify(with event: NSEvent) {
        guard let document else { return }
        zoom(to: document.effectiveScale * (1 + event.magnification), keeping: convert(event.locationInWindow, from: nil))
    }

    /// Two-finger double tap: Fit to actual size (or twice fit, if the capture
    /// is small enough that fit already is actual size), and back.
    override func smartMagnify(with event: NSEvent) {
        guard let document else { return }
        if document.magnification == nil {
            let target: CGFloat = document.fitScale < 0.99 ? 1 : document.fitScale * 2
            zoom(to: target, keeping: convert(event.locationInWindow, from: nil))
        } else {
            document.zoomToFit()
            needsDisplay = true
        }
    }

    /// Scrolling pans while zoomed in. With ⌘ held it zooms instead, for a
    /// mouse, which can't pinch.
    override func scrollWheel(with event: NSEvent) {
        guard let document else { return super.scrollWheel(with: event) }

        if event.modifierFlags.contains(.command) {
            let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 300 : event.scrollingDeltaY / 30
            zoom(to: document.effectiveScale * (1 + step), keeping: convert(event.locationInWindow, from: nil))
            return
        }

        guard document.magnification != nil, let centre = panCentre else { return super.scrollWheel(with: event) }
        let lines: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        panCentre = CGPoint(
            x: centre.x - event.scrollingDeltaX * lines / fitScale,
            y: centre.y + event.scrollingDeltaY * lines / fitScale
        )
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    /// Changes the zoom while keeping the canvas point under `viewPoint` where
    /// it is, which is what makes a pinch feel anchored to the fingers.
    private func zoom(to scale: CGFloat, keeping viewPoint: CGPoint) {
        guard let document else { return }
        let anchor = canvasPoint(viewPoint)
        document.setMagnification(scale)

        let newScale = min(max(document.magnification ?? document.fitScale, document.fitScale), EditorDocument.maximumMagnification)
        let area = contentArea
        panCentre = document.magnification == nil ? nil : CGPoint(
            x: anchor.x + (area.midX - viewPoint.x) / newScale,
            y: anchor.y + (area.midY - viewPoint.y) / newScale
        )

        isZooming = true
        zoomSettle?.cancel()
        let settle = DispatchWorkItem { [weak self] in
            guard let self else { return }
            isZooming = false
            needsDisplay = true
        }
        zoomSettle = settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: settle)

        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - Mouse

    override func resetCursorRects() {
        let tool = document?.tool ?? .select
        // Crosshair only where a click would actually draw something. Over the
        // empty canvas it's an open hand, because that's where dragging the
        // window happens.
        if tool == .select {
            addCursorRect(bounds, cursor: .arrow)
            return
        }
        addCursorRect(bounds, cursor: .openHand)
        // The dragged tools can start anywhere below the toolbar; the pin only
        // lands on the composition.
        let drawable = tool.isDragged ? contentArea : fitRect
        if !drawable.isEmpty {
            addCursorRect(drawable, cursor: .crosshair)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let document else { return }
        let point = convert(event.locationInWindow, from: nil)
        gestureBounds = cachedLayout.map { reachableBounds(layout: $0) }

        // Empty canvas drags the window, the way empty space in any Mac window
        // does. The canvas fills the whole content area and runs under the
        // toolbar, so without this there is almost nowhere left to pick the
        // window up by — the title bar is transparent and the content owns it.
        if shouldDragWindow(from: point, tool: document.tool) {
            document.selection = nil
            needsDisplay = true
            window?.performDrag(with: event)
            return
        }

        switch document.tool {
        case .select:
            window?.makeFirstResponder(self)

            // A handle of the current selection wins over hitting whatever is
            // underneath it — the handles sit on the mark's own edge, so any
            // other order makes them impossible to grab.
            if let id = document.selection,
               let layout = cachedLayout,
               let annotation = document.composition.annotations.first(where: { $0.id == id }),
               let grabbed = handles(for: annotation, layout: layout).first(where: {
                   abs($0.1.x - point.x) <= Self.handleSize && abs($0.1.y - point.y) <= Self.handleSize
               }) {
                resizing = (id, grabbed.0, anchor(for: grabbed.0, of: annotation))
                return
            }

            let hit = topmostAnnotation(at: point)
            document.selection = hit?.id
            movingID = hit?.id
            lastMovePoint = point
            needsDisplay = true

        case .pin:
            guard let normalised = normalised(point) else { return }
            document.add(Annotation(kind: .pin(at: normalised)))
            invalidate()

        case .arrow, .box, .redact:
            dragStart = point
            dragCurrent = point
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let document else { return }
        let point = convert(event.locationInWindow, from: nil)

        if let resizing, let layout = cachedLayout {
            let moved = normalisedAllowingMargin(point, layout: layout)
            let kind: Annotation.Kind
            switch resizing.handle {
            case .arrowTail:
                kind = .arrow(from: moved, to: resizing.anchor)
            case .arrowHead:
                kind = .arrow(from: resizing.anchor, to: moved)
            default:
                let rect = CGRect(
                    x: min(moved.x, resizing.anchor.x),
                    y: min(moved.y, resizing.anchor.y),
                    width: abs(moved.x - resizing.anchor.x),
                    height: abs(moved.y - resizing.anchor.y)
                )
                let isRedaction = document.composition.annotations
                    .first { $0.id == resizing.id }
                    .map { !$0.isNumbered } ?? false
                kind = isRedaction ? .redaction(rect.intersection(Self.unitSquare)) : .box(rect)
            }
            document.setKind(kind, for: resizing.id)
            invalidate()
            return
        }

        if let movingID, let last = lastMovePoint, let layout = cachedLayout {
            let delta = CGVector(
                dx: (point.x - last.x) / fitScale / layout.captureRect.width,
                dy: -(point.y - last.y) / fitScale / layout.captureRect.height
            )
            // `move` takes a symmetric margin, so use the larger reach on each
            // axis. At worst a mark can go a little past the view on the
            // narrower side, and the canvas grows to show it.
            let bounds = gestureBounds ?? reachableBounds(layout: layout)
            let margin = CGVector(
                dx: max(-bounds.minX, bounds.maxX - 1, 0),
                dy: max(-bounds.minY, bounds.maxY - 1, 0)
            )
            document.move(movingID, by: delta, within: margin)
            lastMovePoint = point
            invalidate()
            return
        }

        guard document.tool.isDragged else { return }
        dragCurrent = point
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let document else { return }
        defer {
            dragStart = nil
            dragCurrent = nil
            movingID = nil
            lastMovePoint = nil
            resizing = nil
            gestureBounds = nil
            document.endCoalescing()
            // Always redraw, including on the paths that create nothing.
            // Otherwise the half-drawn shape stays painted on the canvas with
            // no annotation behind it, which looks exactly like a box that
            // refused to finish.
            needsDisplay = true
        }

        guard document.tool.isDragged, let start = dragStart, let layout = cachedLayout else { return }
        let end = convert(event.locationInWindow, from: nil)

        // Both ends are clamped onto the capture rather than required to start
        // on it. Boxing something in a corner means starting the drag out in the
        // margin — it's the natural gesture, and it used to produce nothing at
        // all. A drag entirely outside collapses to an empty rect and is
        // rejected by the size check below.
        let from = normalisedAllowingMargin(start, layout: layout)
        let to = normalisedAllowingMargin(end, layout: layout)

        switch document.tool {
        case .arrow:
            // A click rather than a drag would make a zero-length arrow, which
            // draws as nothing at all and is impossible to select afterwards.
            guard hypot(end.x - start.x, end.y - start.y) > 8 else { return }
            document.add(Annotation(kind: .arrow(from: from, to: to)))

        case .box, .redact:
            let rect = CGRect(
                x: min(from.x, to.x),
                y: min(from.y, to.y),
                width: abs(to.x - from.x),
                height: abs(to.y - from.y)
            )
            // A redaction only ever covers the screenshot, and is clipped to it
            // when drawn. Left un-trimmed, the part over the background would
            // still grow the canvas to fit something nobody can see.
            let shape = document.tool == .box ? rect : rect.intersection(Self.unitSquare)
            guard !shape.isNull,
                  shape.width * layout.captureRect.width > 6,
                  shape.height * layout.captureRect.height > 6
            else { return }
            document.add(Annotation(kind: document.tool == .box ? .box(shape) : .redaction(shape)))

        default:
            break
        }
        invalidate()
    }

    /// Whether a click at this point should move the window instead of marking
    /// the screenshot.
    ///
    /// With a drawing tool — arrow, box, redaction — never below the toolbar:
    /// the whole visible canvas is somewhere a drag can start, because an
    /// arrow's number often wants to sit out in the background, well clear of
    /// the thing it points at. Up under the toolbar the window still moves.
    ///
    /// With Select or the pin: outside the composition always, and inside it
    /// only where there's no mark to pick up.
    private func shouldDragWindow(from point: CGPoint, tool: EditorTool) -> Bool {
        if tool.isDragged { return !contentArea.contains(point) }
        guard fitRect.contains(point) else { return true }
        guard tool == .select else { return false }
        return topmostAnnotation(at: point) == nil
    }

    private static let unitSquare = CGRect(x: 0, y: 0, width: 1, height: 1)

    private func topmostAnnotation(at viewPoint: CGPoint) -> Annotation? {
        guard let document, let layout = cachedLayout else { return nil }
        // Last drawn is on top, so search backwards.
        return document.composition.annotations.reversed().first { annotation in
            viewRect(canvasRect(for: annotation, layout: layout)).insetBy(dx: -4, dy: -4).contains(viewPoint)
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard let document else { return super.keyDown(with: event) }

        // 51 is Delete, 117 is Forward Delete.
        if event.keyCode == 51 || event.keyCode == 117, let selection = document.selection {
            document.remove(selection)
            invalidate()
            return
        }

        // Single keys switch tools, so the flow is P, click, type, Escape, A,
        // drag… without going back to the toolbar. Only when the canvas has
        // focus — while a description field has it, these keys type instead.
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        if modifiers.isEmpty,
           let key = event.charactersIgnoringModifiers?.lowercased().first,
           let tool = EditorTool.named(by: key) {
            document.tool = tool
            document.selection = nil
            window?.invalidateCursorRects(for: self)
            invalidate()
            return
        }

        super.keyDown(with: event)
    }
}

/// SwiftUI wrapper. The canvas itself stays AppKit because it needs precise
/// mouse handling and a cursor that changes with the tool.
struct CompositionCanvas: NSViewRepresentable {
    let document: EditorDocument
    /// Bumped by the parent whenever the composition changes, so the canvas
    /// knows to re-render. SwiftUI can't see inside the AppKit view.
    let revision: Int
    /// Bumped when the canvas should take keyboard focus back from the legend.
    let focusRequests: Int
    /// Passed in so a change from the menu or the zoom button is guaranteed to
    /// reach the canvas, the same way `revision` is.
    let magnification: CGFloat?

    func makeNSView(context: Context) -> CompositionCanvasView {
        let view = CompositionCanvasView()
        view.document = document
        return view
    }

    func updateNSView(_ view: CompositionCanvasView, context: Context) {
        view.document = document
        view.window?.invalidateCursorRects(for: view)
        if focusRequests != context.coordinator.lastFocusRequest {
            context.coordinator.lastFocusRequest = focusRequests
            // Next cycle, not this one. Relinquishing SwiftUI's `@FocusState`
            // settles asynchronously, and asking for first responder in the same
            // pass gets quietly overridden when it does.
            DispatchQueue.main.async { [weak view] in
                guard let view else { return }
                view.window?.makeFirstResponder(view)
            }
        }
        // Re-render only when the composition changed. SwiftUI calls this for
        // anything the editor observes — the zoom, the selection — and
        // re-rendering a large capture for each of those made a pinch stutter.
        if revision != context.coordinator.lastRevision {
            context.coordinator.lastRevision = revision
            view.invalidate()
        } else {
            view.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastFocusRequest = 0
        var lastRevision = -1
    }
}

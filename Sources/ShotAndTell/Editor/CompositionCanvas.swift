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
    private var fitRect: CGRect = .zero
    private var fitScale: CGFloat = 1

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var movingID: UUID?
    private var lastMovePoint: CGPoint?

    /// Which handle of the selected mark is being dragged, and the normalised
    /// point that stays put while it moves — the opposite corner of a box, or
    /// the other end of an arrow.
    private var resizing: (id: UUID, handle: Handle, anchor: CGPoint)?

    enum Handle: CaseIterable {
        case bottomLeft, bottomRight, topLeft, topRight
        /// Arrows resize by their ends rather than by a bounding box.
        case arrowTail, arrowHead
    }

    private static let handleSize: CGFloat = 8

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

        let palette = Palette.resolve(background: composition.background, appearance: composition.appearance)
        cachedPalette = palette
        // No legend on the canvas: the panel to the right is the legend, and
        // showing it twice just makes the screenshot smaller.
        let layout = CompositionLayout.solve(composition, palette: palette, includeLegend: false)
        // safeAreaRect, not bounds: the canvas runs underneath the window's
        // toolbar, and the composition shouldn't be fitted into the part of
        // itself that's covered by it.
        let fit = Self.fit(layout.canvasSize, in: safeAreaRect)
        let scaleChanged = abs(fit.width - fitRect.width) > 0.5

        fitRect = fit
        fitScale = layout.canvasSize.width > 0 ? fit.width / layout.canvasSize.width : 1
        cachedLayout = layout

        guard cacheIsStale || scaleChanged || cachedImage == nil else { return }

        // Render only as many pixels as are actually shown. At export time this
        // is done again at 2x; here, matching the screen keeps a drag smooth on
        // a large capture.
        let backing = window?.backingScaleFactor ?? 2
        let renderScale = max(0.5, min(backing, fitScale * backing))

        // Rendered without its background, because the view paints that across
        // its whole area — see draw(_:).
        cachedImage = try? Compositor.render(
            composition,
            scale: renderScale,
            includeLegend: false,
            drawsBackground: false
        ).image
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

        if let cachedImage {
            context.interpolationQuality = .high
            context.draw(cachedImage, in: fitRect)
        }

        drawSelection(in: context)
        drawDragPreview(in: context)
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

    private func drawDragPreview(in context: CGContext) {
        guard let document, let start = dragStart, let current = dragCurrent, document.tool.isDragged else { return }

        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(1.5)

        switch document.tool {
        case .arrow:
            context.move(to: start)
            context.addLine(to: current)
            context.strokePath()
        case .box, .redact:
            context.stroke(CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            ))
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

    /// Normalised position, allowed to fall outside the capture by as much as
    /// the composition's own margin.
    ///
    /// Boxing something in a corner, or starting an arrow out in the background
    /// and pointing it inwards, both mean working in the margin. The layout
    /// grows the canvas to fit whatever lands there; the clamp only stops a mark
    /// being dragged somewhere the canvas would have to become absurd to
    /// contain.
    private func normalisedAllowingMargin(_ viewPoint: CGPoint, layout: CompositionLayout) -> CGPoint {
        let margin = CompositionLayout.padding
        let allowed = layout.captureRect.insetBy(dx: -margin, dy: -margin)
        let point = canvasPoint(viewPoint)
        let clamped = CGPoint(
            x: min(max(point.x, allowed.minX), allowed.maxX),
            y: min(max(point.y, allowed.minY), allowed.maxY)
        )
        return Compositor.normalise(clamped, in: layout.captureRect)
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

    // MARK: - Mouse

    override func resetCursorRects() {
        let cursor: NSCursor = (document?.tool ?? .select) == .select ? .arrow : .crosshair
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        guard let document else { return }
        let point = convert(event.locationInWindow, from: nil)

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
                kind = isRedaction ? .redaction(rect) : .box(rect)
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
            let margin = CGVector(
                dx: CompositionLayout.padding / layout.captureRect.width,
                dy: CompositionLayout.padding / layout.captureRect.height
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
            guard rect.width * layout.captureRect.width > 6,
                  rect.height * layout.captureRect.height > 6
            else { return }
            document.add(Annotation(kind: document.tool == .box ? .box(rect) : .redaction(rect)))

        default:
            break
        }
        invalidate()
    }

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
        view.invalidate()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastFocusRequest = 0
    }
}

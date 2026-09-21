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
    private var cacheIsStale = true

    /// Where the composition is drawn inside the view, and how much it was
    /// scaled to get there. Everything about hit testing follows from these.
    private var fitRect: CGRect = .zero
    private var fitScale: CGFloat = 1

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var movingID: UUID?
    private var lastMovePoint: CGPoint?

    override var isFlipped: Bool { false }
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
        let layout = CompositionLayout.solve(composition, palette: palette)
        let fit = Self.fit(layout.canvasSize, in: bounds.insetBy(dx: 12, dy: 12))
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

        cachedImage = try? Compositor.render(composition, scale: renderScale).image
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

    private func viewRect(_ canvasRect: CGRect) -> CGRect {
        CGRect(
            x: fitRect.minX + canvasRect.minX * fitScale,
            y: fitRect.minY + canvasRect.minY * fitScale,
            width: canvasRect.width * fitScale,
            height: canvasRect.height * fitScale
        )
    }

    /// Normalised position on the capture, or nil if the point isn't on it —
    /// clicking the legend or the margin shouldn't drop a marker.
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
        window?.makeFirstResponder(self)

        switch document.tool {
        case .select:
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

        if let movingID, let last = lastMovePoint, let layout = cachedLayout {
            let delta = CGVector(
                dx: (point.x - last.x) / fitScale / layout.captureRect.width,
                dy: -(point.y - last.y) / fitScale / layout.captureRect.height
            )
            document.move(movingID, by: delta)
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
            document.endCoalescing()
        }

        guard document.tool.isDragged, let start = dragStart else { return }
        let end = convert(event.locationInWindow, from: nil)

        guard let from = normalised(start), let to = normalised(end) else { return }

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
            guard let layout = cachedLayout,
                  rect.width * layout.captureRect.width > 6,
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

    func makeNSView(context: Context) -> CompositionCanvasView {
        let view = CompositionCanvasView()
        view.document = document
        return view
    }

    func updateNSView(_ view: CompositionCanvasView, context: Context) {
        view.document = document
        view.window?.invalidateCursorRects(for: view)
        view.invalidate()
    }
}

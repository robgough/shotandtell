import AppKit

/// One display's worth of selection overlay: the dimming, the crosshair, the
/// selection rectangle and its readout.
///
/// The view's coordinate space is its screen's, so global positions from the
/// session are converted by subtracting the screen's origin. Nothing is flipped:
/// AppKit global and AppKit window coordinates both have y going up.
final class SelectionOverlayView: NSView {
    private let session: SelectionSession
    private let screenOrigin: CGPoint

    private static let dim = NSColor.black.withAlphaComponent(0.35)
    private static let hairline = NSColor.white.withAlphaComponent(0.55)

    /// This screen's own contents, for the magnifier. Nil in the modes that
    /// don't show one, or if that display's screenshot failed.
    private let displayImage: CapturedImage?

    init(session: SelectionSession, screen: NSScreen) {
        self.session = session
        self.screenOrigin = screen.frame.origin
        self.displayImage = ScreenGeometry.displayID(for: screen).flatMap { session.displayImages[$0] }
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        session.register(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Geometry

    private func local(_ global: CGPoint) -> CGPoint {
        CGPoint(x: global.x - screenOrigin.x, y: global.y - screenOrigin.y)
    }

    private func local(_ global: CGRect) -> CGRect {
        global.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        drawFrozenScreen()

        switch session.mode {
        case .region: drawRegion()
        case .window: drawWindowPick()
        case .screen: drawScreenPick()
        }
    }

    /// Paints the screenshot taken just before the overlay appeared, so what's
    /// on screen stops moving while a selection is being made.
    ///
    /// Without this the overlay is transparent and the real screen carries on
    /// updating underneath it — while the magnifier, which can only show the
    /// snapshot, drifts out of date against it. Freezing makes the two agree by
    /// construction, and stops a video or a scrolling log moving out from under
    /// the selection being dragged around it.
    private func drawFrozenScreen() {
        guard let displayImage, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.interpolationQuality = .none
        context.draw(displayImage.image, in: bounds)
        context.restoreGState()
    }

    /// Dims everything except `hole`, in one fill. Punching a hole with an
    /// even-odd path avoids any compositing-mode games on a transparent window,
    /// which behave inconsistently once the window is layer-backed.
    private func dimEverything(except hole: CGRect?) {
        let path = NSBezierPath(rect: bounds)
        if let hole, !hole.isEmpty {
            path.append(NSBezierPath(rect: hole))
            path.windingRule = .evenOdd
        }
        Self.dim.setFill()
        path.fill()
    }

    private func drawRegion() {
        let selection = session.selection.map(local)
        dimEverything(except: selection)

        if let selection, !selection.isEmpty {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1
            border.stroke()
            drawReadout("\(Int(selection.width.rounded())) × \(Int(selection.height.rounded()))", near: selection)
        } else if let pointer = session.pointer.map(local), bounds.contains(pointer) {
            drawCrosshair(at: pointer)
        }

        if let pointer = session.pointer.map(local), bounds.contains(pointer) {
            drawLoupe(at: pointer)
            if session.selection == nil {
                drawHint("Space to pick a window instead", below: pointer)
            }
        }
    }

    // MARK: - Magnifier

    private static let loupeRadius: CGFloat = 54
    private static let loupeZoom: CGFloat = 8

    /// A circular magnifier next to the pointer, showing the screen underneath
    /// it at 8x with a one-pixel crosshair — the difference between "about
    /// there" and landing on an exact edge.
    private func drawLoupe(at point: CGPoint) {
        guard let displayImage, let context = NSGraphicsContext.current?.cgContext else { return }

        let radius = Self.loupeRadius
        let centre = loupeCentre(for: point, radius: radius)
        let circle = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)

        // The captured image is in pixels with a top-left origin; the view is in
        // points with a bottom-left one.
        let scale = displayImage.scale
        let pixel = CGPoint(x: point.x * scale, y: (bounds.height - point.y) * scale)
        let visiblePixels = (radius * 2) / Self.loupeZoom * scale
        let crop = CGRect(
            x: pixel.x - visiblePixels / 2,
            y: pixel.y - visiblePixels / 2,
            width: visiblePixels,
            height: visiblePixels
        )

        context.saveGState()
        context.addEllipse(in: circle)
        context.clip()

        NSColor.black.setFill()
        circle.fill()

        if let cropped = displayImage.image.cropping(to: crop) {
            // Nearest-neighbour: at 8x, smoothing would defeat the purpose of
            // looking closely.
            context.interpolationQuality = .none
            context.draw(cropped, in: circle)
        }

        // Crosshair marking the exact pixel under the pointer.
        NSColor.white.withAlphaComponent(0.8).setStroke()
        let hair = NSBezierPath()
        hair.lineWidth = 1
        hair.move(to: CGPoint(x: circle.minX, y: centre.y))
        hair.line(to: CGPoint(x: circle.maxX, y: centre.y))
        hair.move(to: CGPoint(x: centre.x, y: circle.minY))
        hair.line(to: CGPoint(x: centre.x, y: circle.maxY))
        hair.stroke()
        context.restoreGState()

        NSColor.white.withAlphaComponent(0.9).setStroke()
        let ring = NSBezierPath(ovalIn: circle)
        ring.lineWidth = 2
        ring.stroke()

        // Which point it's magnifying, spelled out. The loupe sits beside the
        // pointer rather than under it, so without this it isn't obvious that
        // it shows the crosshair rather than what's behind the circle.
        let global = CGPoint(x: point.x + screenOrigin.x, y: point.y + screenOrigin.y)
        let cg = ScreenGeometry.cgGlobal(fromCocoa: global)
        drawReadout("\(Int(cg.x)), \(Int(cg.y))", near: circle)
    }

    /// Up and to the right of the pointer, flipping whenever that would put the
    /// loupe off the edge of this screen.
    private func loupeCentre(for point: CGPoint, radius: CGFloat) -> CGPoint {
        let offset = radius + 22
        var centre = CGPoint(x: point.x + offset, y: point.y + offset)
        if centre.x + radius > bounds.maxX - 8 { centre.x = point.x - offset }
        if centre.y + radius > bounds.maxY - 8 { centre.y = point.y - offset }
        centre.x = min(max(centre.x, bounds.minX + radius + 8), bounds.maxX - radius - 8)
        centre.y = min(max(centre.y, bounds.minY + radius + 8), bounds.maxY - radius - 8)
        return centre
    }

    private func drawHighlight(_ rect: CGRect?, label: String?) {
        dimEverything(except: rect)
        guard let rect, !rect.isEmpty else { return }

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: -1, dy: -1))
        border.lineWidth = 2
        border.stroke()

        if let label, !label.isEmpty {
            drawReadout(label, near: rect)
        }
    }

    /// Window mode. The title goes next to the pointer rather than under the
    /// highlighted rectangle: a browser window can fill the whole display, and
    /// a label pinned to its edge then ends up somewhere you'd never look —
    /// which makes the mode look like it did nothing at all.
    private func drawWindowPick() {
        let rect = session.hovered.map { local($0.cocoaFrame) }
        drawHighlight(rect, label: nil)

        guard let pointer = session.pointer.map(local), bounds.contains(pointer) else { return }
        let title = session.hovered?.title ?? "No window here"
        drawReadout(title, near: CGRect(origin: pointer, size: .zero))
        drawHint("Space to drag a region instead", below: pointer)
    }

    /// The thing you can press, said out loud. Space toggling between region and
    /// window is a real macOS convention, but nothing about a crosshair
    /// advertises it.
    private func drawHint(_ text: String, below point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var origin = CGPoint(x: point.x - size.width / 2, y: point.y - 44)
        origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - size.width - 8)
        origin.y = min(max(origin.y, bounds.minY + 8), bounds.maxY - size.height - 8)

        let padded = CGRect(origin: origin, size: size).insetBy(dx: -7, dy: -4)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: padded, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    /// Screen mode: the display under the pointer is the target, the others are
    /// dimmed out.
    ///
    /// The target gets a *faint tint* rather than being left clear, and that is
    /// load-bearing rather than decorative. The overlay is a transparent window;
    /// in the other two modes it paints the frozen screenshot across itself, so
    /// it's opaque everywhere and every click lands. Screen mode takes no
    /// screenshot — it doesn't need one — so punching a hole the size of the
    /// whole display left the window completely transparent, and the window
    /// server routed the click straight through to whatever was underneath. The
    /// highlight followed the pointer between displays and nothing could ever be
    /// clicked, which is precisely how it was reported.
    private func drawScreenPick() {
        let pointerIsHere = session.pointer.map { bounds.contains(local($0)) } ?? false

        guard pointerIsHere else {
            dimEverything(except: nil)
            return
        }

        NSColor.black.withAlphaComponent(0.06).setFill()
        bounds.fill()

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 3, dy: 3))
        border.lineWidth = 6
        border.stroke()

        if let pointer = session.pointer.map(local) {
            drawReadout("\(Int(bounds.width)) × \(Int(bounds.height))", near: CGRect(origin: pointer, size: .zero))
            drawHint("Click to capture this screen", below: pointer)
        }
    }

    private func drawCrosshair(at point: CGPoint) {
        Self.hairline.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: CGPoint(x: bounds.minX, y: point.y.rounded() + 0.5))
        path.line(to: CGPoint(x: bounds.maxX, y: point.y.rounded() + 0.5))
        path.move(to: CGPoint(x: point.x.rounded() + 0.5, y: bounds.minY))
        path.line(to: CGPoint(x: point.x.rounded() + 0.5, y: bounds.maxY))
        path.stroke()
    }

    /// A small dark pill just outside the selection — below it normally, above
    /// when there's no room, and always kept on screen.
    private func drawReadout(_ text: String, near rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding = CGSize(width: 8, height: 4)
        let pill = CGSize(width: size.width + padding.width * 2, height: size.height + padding.height * 2)

        var origin = CGPoint(x: rect.midX - pill.width / 2, y: rect.minY - pill.height - 6)
        if origin.y < bounds.minY + 4 { origin.y = rect.maxY + 6 }
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - pill.width - 4)
        origin.y = min(max(origin.y, bounds.minY + 4), bounds.maxY - pill.height - 4)

        let pillRect = CGRect(origin: origin, size: pill)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: CGPoint(x: pillRect.minX + padding.width, y: pillRect.minY + padding.height),
                                withAttributes: attributes)
    }

    // MARK: - Input

    override var acceptsFirstResponder: Bool { true }

    /// Only the overlay under the pointer is made key. Without this, the first
    /// mouse-down on any *other* display would be swallowed to activate that
    /// window, so the drag would arrive with no anchor and cancel the capture.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: session.mode == .region ? .crosshair : .arrow)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        ))
    }

    private func globalPoint(_ event: NSEvent) -> CGPoint {
        let inView = convert(event.locationInWindow, from: nil)
        return CGPoint(x: inView.x + screenOrigin.x, y: inView.y + screenOrigin.y)
    }

    override func mouseMoved(with event: NSEvent) {
        session.pointerMoved(to: globalPoint(event))
    }

    override func mouseDown(with event: NSEvent) {
        session.dragBegan(at: globalPoint(event))
    }

    override func mouseDragged(with event: NSEvent) {
        session.dragChanged(to: globalPoint(event))
    }

    override func mouseUp(with event: NSEvent) {
        session.dragEnded(at: globalPoint(event))
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            session.cancel()
        case 49: // Space — the same toggle the system screenshot tool uses.
            session.toggleWindowMode()
        default:
            break // Ignored rather than beeping.
        }
    }

    override func cancelOperation(_ sender: Any?) {
        session.cancel()
    }
}

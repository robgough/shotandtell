import AppKit
import ScreenCaptureKit

/// The state of one trip through the selection overlay, shared by every screen's
/// overlay view.
///
/// One session spans all displays rather than one per screen, because a drag
/// that starts on one display and ends on another is a perfectly ordinary thing
/// to do. Positions are therefore kept in AppKit *global* coordinates and each
/// view converts to its own space when drawing.
final class SelectionSession {
    let mode: CaptureMode
    private(set) var windows: [HitTestableWindow] = []

    /// Where the drag started and where the pointer is now, both global. Nil
    /// anchor means no drag is in progress.
    private(set) var anchor: CGPoint?
    private(set) var pointer: CGPoint?
    private(set) var hovered: HitTestableWindow?

    private var views: [SelectionOverlayView] = []
    private var finish: ((SelectionOutcome) -> Void)?

    struct HitTestableWindow {
        let id: CGWindowID
        /// AppKit global coordinates, so it can be compared with the pointer and
        /// drawn without further conversion.
        let cocoaFrame: CGRect
        let title: String?
    }

    init(mode: CaptureMode, content: SCShareableContent, finish: @escaping (SelectionOutcome) -> Void) {
        self.mode = mode
        self.finish = finish
        if mode == .window {
            windows = Self.hitTestableWindows(from: content)
        }
    }

    // MARK: - Current selection

    /// The drag rectangle, normalised so it's valid whichever way the drag went.
    var selection: CGRect? {
        guard let anchor, let pointer else { return nil }
        return CGRect(
            x: min(anchor.x, pointer.x),
            y: min(anchor.y, pointer.y),
            width: abs(pointer.x - anchor.x),
            height: abs(pointer.y - anchor.y)
        )
    }

    // MARK: - Input

    func register(_ view: SelectionOverlayView) {
        views.append(view)
    }

    func pointerMoved(to global: CGPoint) {
        pointer = global
        if mode == .window {
            hovered = topmostWindow(under: global)
        }
        redraw()
    }

    func dragBegan(at global: CGPoint) {
        anchor = global
        pointer = global
        redraw()
    }

    func dragChanged(to global: CGPoint) {
        pointer = global
        redraw()
    }

    func dragEnded(at global: CGPoint) {
        pointer = global

        switch mode {
        case .region:
            guard let selection,
                  selection.width >= CaptureService.minimumRegionSize,
                  selection.height >= CaptureService.minimumRegionSize,
                  let displayID = displayID(containing: selection.origin) ?? displayID(containing: global)
            else {
                // A click rather than a drag: treat it as "I changed my mind".
                complete(.cancelled)
                return
            }
            complete(.region(selection, displayID: displayID))

        case .window:
            if let hovered {
                complete(.window(hovered.id))
            } else {
                complete(.cancelled)
            }

        case .screen:
            if let displayID = displayID(containing: global) {
                complete(.display(displayID))
            } else {
                complete(.cancelled)
            }
        }
    }

    func cancel() {
        complete(.cancelled)
    }

    /// Resumes the caller exactly once — a second Escape, or an Escape racing a
    /// mouse-up, must not resume a continuation twice.
    private func complete(_ outcome: SelectionOutcome) {
        guard let finish else { return }
        self.finish = nil
        finish(outcome)
    }

    private func redraw() {
        for view in views { view.needsDisplay = true }
    }

    // MARK: - Hit testing

    private func displayID(containing global: CGPoint) -> CGDirectDisplayID? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(global) }) else { return nil }
        return ScreenGeometry.displayID(for: screen)
    }

    private func topmostWindow(under global: CGPoint) -> HitTestableWindow? {
        windows.first { $0.cocoaFrame.contains(global) }
    }

    /// Windows in front-to-back order, so the first one containing the pointer
    /// is the one the user can actually see there.
    ///
    /// The ordering comes from `CGWindowListCopyWindowInfo`, which returns them
    /// in that order; `SCShareableContent.windows` makes no such promise, and
    /// picking the wrong one of two overlapping windows is very obvious.
    private static func hitTestableWindows(from content: SCShareableContent) -> [HitTestableWindow] {
        let order = frontToBackWindowIDs()
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let ourPID = ProcessInfo.processInfo.processIdentifier

        return content.windows
            .filter { window in
                window.isOnScreen
                    && window.owningApplication?.processID != ourPID
                    && window.frame.width >= 40 && window.frame.height >= 40
                    && rank[window.windowID] != nil
            }
            .sorted { (rank[$0.windowID] ?? .max) < (rank[$1.windowID] ?? .max) }
            .map {
                HitTestableWindow(
                    id: $0.windowID,
                    cocoaFrame: ScreenGeometry.cocoaGlobal(fromCG: $0.frame),
                    title: CaptureService.describe($0)
                )
            }
    }

    private static func frontToBackWindowIDs() -> [CGWindowID] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return info.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
    }
}

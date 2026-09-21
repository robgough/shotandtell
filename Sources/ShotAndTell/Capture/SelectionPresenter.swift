import AppKit
import ScreenCaptureKit

/// Puts the selection overlay on every display and waits for the user to pick
/// something.
@MainActor
enum SelectionPresenter {
    static func present(
        mode: CaptureMode,
        content: SCShareableContent,
        displayImages: [CGDirectDisplayID: CapturedImage] = [:]
    ) async -> SelectionOutcome {
        // One display and a whole-screen capture: there's nothing to choose
        // between, so don't make the user click to confirm the obvious.
        if mode == .screen, NSScreen.screens.count == 1,
           let screen = NSScreen.screens.first,
           let displayID = ScreenGeometry.displayID(for: screen) {
            return .display(displayID)
        }

        var windows: [SelectionOverlayWindow] = []
        var monitor: Any?
        var screenObserver: (any NSObjectProtocol)?

        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<SelectionOutcome, Never>) in
            let session = SelectionSession(mode: mode, content: content, displayImages: displayImages) { outcome in
                continuation.resume(returning: outcome)
            }

            windows = NSScreen.screens.map { SelectionOverlayWindow(screen: $0, session: session) }

            // Escape has to work whichever display is key, and a key-down that
            // arrives while no overlay is key would otherwise be lost.
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53 else { return event }
                session.cancel()
                return nil
            }

            // Overlays are positioned from the screen layout captured a moment
            // ago, and the displays SCK told us about are equally stale. If that
            // changes mid-selection, abandon rather than draw somewhere wrong.
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { session.cancel() }
            }

            NSApp.activate()
            for window in windows { window.orderFrontRegardless() }
            // Key the overlay under the pointer, so the first Escape lands
            // without needing a click first.
            let pointer = NSEvent.mouseLocation
            let preferred = windows.first { $0.frame.contains(pointer) } ?? windows.first
            preferred?.makeKey()
        }

        if let monitor { NSEvent.removeMonitor(monitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        for window in windows {
            // contentView is cleared explicitly: the window server was still
            // listing these as on-screen after a cancel, and a stranded
            // shielding-level window swallows every click on the display.
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()

        return outcome
    }
}

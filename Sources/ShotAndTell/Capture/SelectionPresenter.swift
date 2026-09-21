import AppKit
import ScreenCaptureKit

/// Puts the selection overlay on every display and waits for the user to pick
/// something.
@MainActor
enum SelectionPresenter {
    static func present(mode: CaptureMode, content: SCShareableContent) async -> SelectionOutcome {
        // One display and a whole-screen capture: there's nothing to choose
        // between, so don't make the user click to confirm the obvious.
        if mode == .screen, NSScreen.screens.count == 1,
           let screen = NSScreen.screens.first,
           let displayID = ScreenGeometry.displayID(for: screen) {
            return .display(displayID)
        }

        var windows: [SelectionOverlayWindow] = []
        var monitor: Any?

        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<SelectionOutcome, Never>) in
            let session = SelectionSession(mode: mode, content: content) { outcome in
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

            NSApp.activate(ignoringOtherApps: true)
            for window in windows { window.orderFrontRegardless() }
            // Key the overlay under the pointer, so the first Escape lands
            // without needing a click first.
            let pointer = NSEvent.mouseLocation
            let preferred = windows.first { $0.frame.contains(pointer) } ?? windows.first
            preferred?.makeKey()
        }

        if let monitor { NSEvent.removeMonitor(monitor) }
        for window in windows {
            window.orderOut(nil)
            window.close()
        }

        return outcome
    }
}

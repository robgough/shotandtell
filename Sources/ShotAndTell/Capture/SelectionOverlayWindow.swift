import AppKit

/// A borderless, transparent window covering exactly one display.
///
/// Sits at the shielding level so it's above everything including full-screen
/// apps, and joins all spaces so switching space mid-selection doesn't strand
/// it. It never appears in the capture: ScreenCaptureKit filters our whole
/// application out rather than us hiding the overlay first and racing the
/// screen's redraw.
final class SelectionOverlayWindow: NSWindow {
    /// Borderless windows refuse key status by default, and without it there's
    /// nowhere for Escape to land.
    override var canBecomeKey: Bool { true }

    init(screen: NSScreen, session: SelectionSession) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        // Out of Mission Control, out of screenshots of *other* apps, and out of
        // the window list generally: this is a transient piece of chrome.
        isExcludedFromWindowsMenu = true

        contentView = SelectionOverlayView(session: session, screen: screen)
        setFrame(screen.frame, display: true)
    }
}

import AppKit
import SwiftUI

/// The Settings window. One instance, reused — opening Settings twice should
/// bring the existing window forward, not stack a second one behind it.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Shot and tell Settings"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SettingsWindow")

        super.init(window: window)

        let hosting = NSHostingController(rootView: SettingsView(settings: .shared))
        window.contentViewController = hosting
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

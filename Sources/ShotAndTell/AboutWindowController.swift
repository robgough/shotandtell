import AppKit
import SwiftUI

/// The About window. One instance, reused — opening About twice should bring the
/// existing window forward rather than stack a second one behind it.
@MainActor
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Shot and Tell"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("AboutWindow")

        super.init(window: window)

        let hosting = NSHostingController(rootView: AboutView())
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 520, height: 620))
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

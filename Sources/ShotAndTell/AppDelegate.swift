import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = CaptureCoordinator()
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Built by hand rather than loaded from a nib: with `@main` on the
        // delegate there's no MainMenu.xib, and an app with a Dock icon and no
        // menu bar of its own looks broken (and can't even be quit with ⌘Q).
        let (mainMenu, windowsMenu) = MainMenu.build()
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowsMenu
        let menuBar = MenuBarController(coordinator: coordinator)
        self.menuBar = menuBar
        coordinator.onCountdown = { [weak menuBar] seconds in
            menuBar?.showCountdown(seconds)
        }

        Log.app.notice("Shot and tell launched")
    }

    /// Clicking the Dock icon starts a capture. This is the whole reason the app
    /// keeps a Dock icon instead of being an `LSUIElement` accessory: it's the
    /// fastest possible path from "I want to point at this" to a crosshair.
    ///
    /// Returns false to stop AppKit from doing its default reopen behaviour
    /// (un-hiding or creating a window), which isn't what we want here.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // If an editor window is already open, the user is mid-edit and almost
        // certainly meant "bring that back", not "throw it away and start again".
        guard !flag else { return true }

        coordinator.beginCapture(.region)
        return false
    }

    /// Quitting when the last window closes would be wrong — the app lives in
    /// the menu bar and the Dock, and closing an editor is a normal thing to do.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

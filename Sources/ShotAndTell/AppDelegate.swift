import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = CaptureCoordinator()
    /// Wired up as the action for every "Settings…" item in the app.
    @objc func openSettings() {
        SettingsWindowController.shared.show()
    }

    /// Ours rather than `orderFrontStandardAboutPanel`, which can only show a
    /// name, a version and a copyright line.
    @objc func openAbout() {
        AboutWindowController.shared.show()
    }

    private var menuBar: MenuBarController?
    private var editors: [EditorWindowController] = []
    /// The last capture whose window was closed, kept so it can be reopened.
    /// Holding one screenshot in memory is cheap next to losing one to a
    /// mistyped Escape.
    private var lastClosedDocument: EditorDocument?

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
        coordinator.onCaptured = { [weak self] capture in
            self?.openEditor(for: capture)
        }

        GlobalHotkey.shared.onFire = { [weak coordinator] in
            coordinator?.beginCapture(CaptureRequest(mode: Settings.shared.dockClickMode))
        }
        Settings.shared.applyHotkey()

        Log.app.notice("Shot and Tell launched")

        if let s = ProcessInfo.processInfo.environment["SHOTANDTELL_DEMO_SETTINGS"] {
            SettingsWindowController.shared.show()
            NSApp.activate(ignoringOtherApps: true)
            let n = s.split(separator: ",").compactMap { Double($0) }
            if let w = NSApp.windows.first(where: { $0.isVisible && $0.title.contains("Settings") }) {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    if n.count >= 2 { w.setFrameOrigin(NSPoint(x: n[0], y: n[1])) }
                    let f = w.frame
                    FileHandle.standardError.write("SETTINGS_FRAME \(f.origin.x),\(f.origin.y),\(f.width),\(f.height) screen \(NSScreen.main?.frame.height ?? 0)\n".data(using: .utf8)!)
                }
            }
        }

        // TEMPORARY — marketing-shot tooling, not shipped.
        if let composition = DemoLoader.load() {
            let document = EditorDocument(capture: composition.capture)
            document.composition = composition
            let controller = EditorWindowController(document: document, onExported: { _ in }, onClose: { _ in })
            editors.append(controller)
            controller.show()
            if let frame = ProcessInfo.processInfo.environment["SHOTANDTELL_DEMO_FRAME"] {
                let n = frame.split(separator: ",").compactMap { Double($0) }
                if n.count == 4 {
                    controller.window?.setFrame(NSRect(x: n[0], y: n[1], width: n[2], height: n[3]), display: true)
                }
            }
            NSApp.activate(ignoringOtherApps: true)
            if let out = ProcessInfo.processInfo.environment["SHOTANDTELL_DEMO_EXPORT"] {
                Task.detached {
                    let rendered = try Compositor.render(composition, scale: 2)
                    try PNGEncoder.encode(rendered.image, scale: 2).write(to: URL(fileURLWithPath: out))
                    print("demo export written")
                }
            }
        }
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

        coordinator.beginCapture(CaptureRequest(mode: Settings.shared.dockClickMode))
        return false
    }

    /// Editors are held here for as long as their windows are open; an
    /// NSWindowController with nothing retaining it goes away immediately.
    /// More than one can be open at once — taking a second screenshot while
    /// still describing the first is a reasonable thing to do.
    private func openEditor(for capture: CapturedImage) {
        let controller = EditorWindowController(
            capture: capture,
            onExported: { [weak self] url in
                self?.menuBar?.lastSavedURL = url
            },
            onClose: { [weak self] controller in
                guard let self else { return }
                lastClosedDocument = controller.capturedDocument
                menuBar?.canReopenCapture = true
                editors.removeAll { $0 === controller }
            }
        )
        editors.append(controller)
        controller.show()
    }

    /// Reopens the last capture with its marks intact — the way back from an
    /// accidental close, and from deciding a shot needed one more note.
    @objc func reopenLastCapture() {
        guard let document = lastClosedDocument else { return }
        let controller = EditorWindowController(
            document: document,
            onExported: { [weak self] url in self?.menuBar?.lastSavedURL = url },
            onClose: { [weak self] controller in
                guard let self else { return }
                lastClosedDocument = controller.capturedDocument
                editors.removeAll { $0 === controller }
            }
        )
        editors.append(controller)
        controller.show()
    }

    /// Quitting when the last window closes would be wrong — the app lives in
    /// the menu bar and the Dock, and closing an editor is a normal thing to do.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

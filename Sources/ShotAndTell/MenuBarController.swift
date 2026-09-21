import AppKit

/// The menu bar item and its menu — the second of the three ways into a capture.
///
/// No key equivalents on the capture items: the shortcut that matters is the
/// *global* hotkey (phase 5), which works whatever app is frontmost. A menu key
/// equivalent would only fire when Shot and Tell already had focus, which is
/// almost never the moment you want to take a screenshot.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let coordinator: CaptureCoordinator
    /// The most recent export, so it can be revealed. Not persisted — a stale
    /// path from three days ago is a worse menu item than none.
    var lastSavedURL: URL?

    init(coordinator: CaptureCoordinator) {
        self.coordinator = coordinator
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "viewfinder",
                accessibilityDescription: "Shot and Tell"
            )
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Rebuilt each time the menu opens rather than once at launch, so a
    /// shortcut or default capture mode changed in Settings shows up here
    /// instead of going stale.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        populate(menu)
    }

    /// Counts a timed capture down in the menu bar. There's nowhere else to put
    /// it — the whole point of the timer is that the app isn't in front.
    func showCountdown(_ seconds: Int?) {
        guard let button = statusItem.button else { return }
        if let seconds {
            button.title = " \(seconds)"
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    private func populate(_ menu: NSMenu) {
        // "New Capture" does whatever the Dock icon does, so the two obvious
        // ways in behave the same; the explicit modes are listed underneath for
        // when you want a different one.
        let new = menu.addItem(withTitle: "New Capture", action: #selector(newCapture), keyEquivalent: "")
        new.target = self
        if let hotkey = Settings.shared.hotkey, hotkey.isUsable {
            // Shown in a tooltip, not bound as a key equivalent: this is the
            // *global* shortcut. A menu key equivalent would only fire when Shot
            // and tell already had focus, which is almost never when you want a
            // screenshot.
            new.toolTip = "Global shortcut: \(hotkey.displayString)"
        }

        for mode in CaptureMode.allCases {
            let item = menu.addItem(withTitle: mode.menuTitle, action: #selector(captureMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.indentationLevel = 1
        }

        menu.addItem(.separator())

        let timed = NSMenu()
        for seconds in [3, 5, 10] {
            let item = timed.addItem(withTitle: "After \(seconds) Seconds", action: #selector(timedCapture(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
        }
        let timedItem = menu.addItem(withTitle: "Timed Capture", action: nil, keyEquivalent: "")
        timedItem.submenu = timed

        if let lastSavedURL {
            menu.addItem(.separator())
            let reveal = menu.addItem(withTitle: "Reveal Last Screenshot in Finder", action: #selector(revealLastSaved), keyEquivalent: "")
            reveal.target = self
            reveal.toolTip = lastSavedURL.path(percentEncoded: false)
        }

        if let problem = Settings.shared.hotkeyProblem {
            menu.addItem(.separator())
            // The failure that matters most happens at launch, before any
            // window exists to report it to — most likely the default shortcut
            // already being taken by something else.
            let warning = menu.addItem(withTitle: "Shortcut unavailable", action: #selector(AppDelegate.openSettings), keyEquivalent: "")
            warning.target = NSApp.delegate
            warning.toolTip = problem
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        }

        menu.addItem(.separator())

        let settings = menu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.openSettings), keyEquivalent: ",")
        settings.target = NSApp.delegate

        menu.addItem(withTitle: "About Shot and Tell", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Shot and Tell", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func newCapture() {
        coordinator.beginCapture(.region)
    }

    @objc private func captureMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = CaptureMode(rawValue: raw) else { return }
        coordinator.beginCapture(CaptureRequest(mode: mode))
    }

    @objc private func revealLastSaved() {
        guard let lastSavedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastSavedURL])
    }

    @objc private func timedCapture(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Int else { return }
        coordinator.beginCapture(CaptureRequest(mode: .region, delay: .seconds(seconds)))
    }
}

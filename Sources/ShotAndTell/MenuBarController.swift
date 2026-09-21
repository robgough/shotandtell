import AppKit

/// The menu bar item and its menu — the second of the three ways into a capture.
///
/// No key equivalents on the capture items: the shortcut that matters is the
/// *global* hotkey (phase 5), which works whatever app is frontmost. A menu key
/// equivalent would only fire when Shot and tell already had focus, which is
/// almost never the moment you want to take a screenshot.
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let coordinator: CaptureCoordinator

    init(coordinator: CaptureCoordinator) {
        self.coordinator = coordinator
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "viewfinder",
                accessibilityDescription: "Shot and tell"
            )
            button.image?.isTemplate = true
        }

        statusItem.menu = buildMenu()
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

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let new = menu.addItem(withTitle: "New Capture", action: #selector(newCapture), keyEquivalent: "")
        new.target = self
        // Shown, not bound: this is the *global* shortcut, which fires whatever
        // app is frontmost. A menu key equivalent would only work when Shot and
        // tell already had focus, which is almost never when you want a
        // screenshot. `isAlternate` is not involved — the attributed title just
        // puts the keys where people look for them.
        if let hotkey = Settings.shared.hotkey, hotkey.isUsable {
            new.title = "New Capture"
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

        menu.addItem(.separator())

        let settings = menu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.openSettings), keyEquivalent: ",")
        settings.target = NSApp.delegate

        menu.addItem(withTitle: "About Shot and tell", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Shot and tell", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        return menu
    }

    @objc private func newCapture() {
        coordinator.beginCapture(.region)
    }

    @objc private func captureMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = CaptureMode(rawValue: raw) else { return }
        coordinator.beginCapture(CaptureRequest(mode: mode))
    }

    @objc private func timedCapture(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Int else { return }
        coordinator.beginCapture(CaptureRequest(mode: .region, delay: .seconds(seconds)))
    }
}

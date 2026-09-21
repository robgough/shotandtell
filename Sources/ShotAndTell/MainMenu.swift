import AppKit

/// The app's main menu bar, built in code.
///
/// Only three menus, and each is here for a reason: the App menu because macOS
/// requires one and it's where Settings and Quit live; Edit because the legend
/// is full of text fields and ⌘Z / ⌘C / ⌘V have to work in them; Window because
/// the editor is a real window and people expect to be able to minimise it.
enum MainMenu {
    /// Returns the menu bar and the Window menu within it. The caller hands the
    /// Window menu to `NSApp.windowsMenu` so AppKit can manage the window list
    /// itself — returned rather than assigned here, so building a menu has no
    /// side effects on the running application.
    static func build() -> (main: NSMenu, windows: NSMenu) {
        let main = NSMenu()
        main.addItem(appMenuItem())
        main.addItem(editMenuItem())

        let window = windowMenuItem()
        main.addItem(window)

        return (main, window.submenu!)
    }

    private static func appMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu()

        menu.addItem(withTitle: "About Shot and tell", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        let settings = menu.addItem(withTitle: "Settings…", action: nil, keyEquivalent: ",")
        settings.isEnabled = false  // TODO(phase 5): the Settings window.

        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Shot and tell", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")

        let hideOthers = menu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]

        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Shot and tell", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.submenu = menu
        return item
    }

    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")

        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        item.submenu = menu
        return item
    }

    private static func windowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Window")

        menu.addItem(withTitle: "Minimise", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")

        item.submenu = menu
        return item
    }
}

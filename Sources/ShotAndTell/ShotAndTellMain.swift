import AppKit

/// The entry point, wired up by hand.
///
/// Not `@main` on AppDelegate: that routes through NSApplicationMain, which
/// expects to find the delegate connected in a MainMenu nib. There isn't one —
/// the menu bar is built in code — so the app launched perfectly happily and
/// then never called a single delegate method. No status item, no Dock-click
/// capture, and no error to explain why.
///
/// Not a top-level `main.swift` either: top-level code in an AppKit target
/// makes the linker try to link SwiftUICore directly, which it refuses to do.
@main
enum ShotAndTellMain {
    /// `NSApplication.delegate` is a weak reference, so the delegate has to be
    /// owned somewhere that outlives `run()`.
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        // Regular, not .accessory: this app has a Dock icon on purpose.
        app.setActivationPolicy(.regular)
        app.run()
    }
}

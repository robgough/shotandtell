import AppKit

/// The entry point, wired up by hand.
///
/// Not `@main` on AppDelegate: AppKit's default implementation of that (see
/// `NSApplicationDelegate.main()` in the AppKit swiftinterface) just calls
/// `NSApplicationMain`, which never instantiates the delegate — it expects to
/// find one connected in a MainMenu nib. There isn't one here, so the app
/// launched perfectly happily and then never called a single delegate method.
/// No status item, no Dock-click capture, and no error explaining why.
///
/// A top-level `main.swift` would also work; this is the same three lines with
/// somewhere obvious to own the delegate.
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

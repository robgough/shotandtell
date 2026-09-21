import AppKit
import CoreGraphics

/// The Screen Recording TCC grant.
///
/// There is no entitlement for this — ScreenCaptureKit works inside the App
/// Sandbox and consent is handled entirely by TCC — and macOS composes the
/// permission alert itself, so there's no Info.plist purpose string either. Any
/// explaining has to happen in our own UI.
///
/// `CGRequestScreenCaptureAccess()` is the only thing that raises the system
/// prompt — asking ScreenCaptureKit for content just fails with "the user
/// declined", even on a bundle ID that has never been asked about. But it also
/// blocks its thread on a synchronous round trip, so it must not be called on
/// the main one: `request()` hops it onto a background queue and awaits the
/// answer.
enum ScreenRecordingPermission {
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Raises the system prompt the first time the app ever asks. Afterwards it
    /// answers from the recorded decision without showing anything, which is why
    /// a false result has to lead somewhere useful rather than just failing.
    static func request() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: CGRequestScreenCaptureAccess())
            }
        }
    }

    /// True if the app may capture. Asks if it hasn't been asked, explains and
    /// offers System Settings if it has been refused.
    static func ensureGranted() async -> Bool {
        if isGranted { return true }

        // The system prompt is raised asynchronously and `request()` answers
        // with the state *now*, so a false on the very first ask means "the
        // prompt is on screen, waiting" rather than "no". Stacking our own
        // explanation on top of it at that moment gives the user two dialogs
        // about the same thing, one of them in front of the one that matters.
        let hasAskedBefore = UserDefaults.standard.bool(forKey: hasAskedKey)
        UserDefaults.standard.set(true, forKey: hasAskedKey)

        if await request() { return true }
        guard hasAskedBefore else { return false }

        explainDenial()
        return false
    }

    private static let hasAskedKey = "hasAskedForScreenRecording"

    /// Shown after ScreenCaptureKit has refused.
    static func explainDenial() {
        let alert = NSAlert()
        alert.messageText = "Shot and Tell needs permission to record the screen"
        alert.informativeText = """
            Taking a screenshot counts as screen recording on macOS, so it's the \
            same permission. Nothing is recorded continuously and nothing leaves \
            your Mac — the app has no network access at all.

            Turn on Shot and Tell under Screen & System Audio Recording, then try \
            again.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            openSystemSettings()
        }
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}

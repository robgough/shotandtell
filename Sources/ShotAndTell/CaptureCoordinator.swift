import Foundation

/// The single funnel every capture goes through, whichever of the three
/// entry points started it: the Dock icon, the menu bar, or the global hotkey.
///
/// Phase 0: this only logs. Phase 1 gives it ScreenCaptureKit, the permission
/// flow and the selection overlays; phase 2 hands the result to the editor.
final class CaptureCoordinator {
    /// Guards against a second capture starting while the picker is already up —
    /// easy to trigger by clicking the Dock icon while the overlay is showing.
    private(set) var isCapturing = false

    func beginCapture(_ request: CaptureRequest) {
        guard !isCapturing else {
            Log.capture.notice("Capture already in progress; ignoring request for \(request.mode.rawValue, privacy: .public)")
            return
        }

        Log.capture.notice(
            "Begin capture: mode=\(request.mode.rawValue, privacy: .public) delay=\(request.delay.components.seconds, privacy: .public)s"
        )
        // TODO(phase 1): permission check → delay → overlay → SCScreenshotManager.
    }
}

import AppKit
import ScreenCaptureKit

/// The single funnel every capture goes through, whichever of the three entry
/// points started it: the Dock icon, the menu bar, or the global hotkey.
///
/// Permission, the timer, the overlay, the ScreenCaptureKit call and what
/// happens to the result all live here, so that "don't start a second capture
/// while the picker is up" and "explain the permission once" are written once.
final class CaptureCoordinator {
    /// Guards against a second capture starting while the picker is already up —
    /// easy to trigger by clicking the Dock icon while the overlay is showing.
    private(set) var isCapturing = false

    /// Set by the app delegate. Counts a timed capture down in the menu bar, and
    /// is called with nil when there's nothing to show.
    var onCountdown: ((Int?) -> Void)?

    /// Where a finished capture goes. Phase 2 points this at the editor; for now
    /// the coordinator puts it on the clipboard itself.
    var onCaptured: ((CapturedImage) -> Void)?

    func beginCapture(_ request: CaptureRequest) {
        guard !isCapturing else {
            Log.capture.notice("Capture already in progress; ignoring request for \(request.mode.rawValue, privacy: .public)")
            return
        }
        isCapturing = true

        Task {
            defer {
                isCapturing = false
                onCountdown?(nil)
            }
            await run(request)
        }
    }

    private func run(_ request: CaptureRequest) async {
        Log.capture.notice(
            "Begin capture: mode=\(request.mode.rawValue, privacy: .public) delay=\(request.delay.components.seconds, privacy: .public)s"
        )

        await countDown(request.delay)

        do {
            guard await ScreenRecordingPermission.ensureGranted() else {
                Log.capture.notice("Screen recording not granted; capture abandoned")
                return
            }

            let content = try await CaptureService.shareableContent()

            // Only region selection shows a magnifier, and only it pays for the
            // screenshots that feed it.
            let displayImages = request.mode == .region
                ? await CaptureService.captureAllDisplays(content)
                : [:]

            let outcome = await SelectionPresenter.present(
                mode: request.mode,
                content: content,
                displayImages: displayImages
            )

            guard let captured = try await capture(outcome, from: content) else {
                Log.capture.notice("Capture cancelled")
                return
            }

            Log.capture.notice(
                "Captured \(captured.image.width, privacy: .public)×\(captured.image.height, privacy: .public)px at \(captured.scale, privacy: .public)x"
            )
            deliver(captured)
        } catch {
            Log.capture.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            presentFailure(error)
        }
    }

    /// Returns nil when the user cancelled — which is an outcome, not an error.
    private func capture(_ outcome: SelectionOutcome, from content: SCShareableContent) async throws -> CapturedImage? {
        switch outcome {
        case .cancelled:
            return nil

        case let .region(rect, displayID):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw CaptureService.Failure.noDisplays
            }
            // The overlay works in AppKit's bottom-left coordinate space;
            // ScreenCaptureKit wants Core Graphics' top-left one.
            let cgRect = ScreenGeometry.cgGlobal(fromCocoa: rect)
            return try await CaptureService.capture(region: cgRect, on: display, content: content)

        case let .window(windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                // The window closed between being picked and being captured.
                return nil
            }
            return try await CaptureService.capture(window: window)

        case let .display(displayID):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw CaptureService.Failure.noDisplays
            }
            return try await CaptureService.capture(display: display, content: content)
        }
    }

    private func deliver(_ captured: CapturedImage) {
        guard let onCaptured else {
            Log.capture.error("Captured an image with nowhere to send it — no editor handler is installed")
            return
        }
        onCaptured(captured)
    }

    private func countDown(_ delay: Duration) async {
        var remaining = Int(delay.components.seconds)
        guard remaining > 0 else { return }

        while remaining > 0 {
            onCountdown?(remaining)
            try? await Task.sleep(for: .seconds(1))
            remaining -= 1
        }
        onCountdown?(nil)
    }

    private func presentFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't take the screenshot"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }
}

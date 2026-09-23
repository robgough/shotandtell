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
            // Whether we could leave ourselves out of this capture's snapshots.
            // When this is false, anything of ours that is on screen is in them.
            let listed = content.applications.contains { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            Log.capture.notice("Shareable content lists us: \(listed, privacy: .public)")

            // Whenever the overlay goes up it shows a frozen snapshot of every
            // display, and region and whole-screen captures are cut from that
            // same snapshot afterwards. The only case with no overlay — and so
            // nothing to snapshot — is taking the whole screen on a Mac with one.
            let showsOverlay = !(request.mode == .screen && NSScreen.screens.count == 1)
            let displayImages = showsOverlay
                ? await CaptureService.captureAllDisplays(content)
                : [:]

            let outcome = await SelectionPresenter.present(
                mode: request.mode,
                content: content,
                displayImages: displayImages
            )

            guard let captured = try await capture(outcome, from: content, snapshots: displayImages) else {
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
    ///
    /// Region and whole-screen captures come from the snapshot the overlay was
    /// showing, not a fresh capture — see `CaptureService.crop`. A fresh one is
    /// only the fallback when there's no snapshot for that display, and then it
    /// asks for the list of apps again, so an overlay window that's still
    /// closing is on it and gets left out.
    private func capture(
        _ outcome: SelectionOutcome,
        from content: SCShareableContent,
        snapshots: [CGDirectDisplayID: CapturedImage]
    ) async throws -> CapturedImage? {
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
            if let snapshot = snapshots[displayID],
               let cropped = CaptureService.crop(snapshot, to: cgRect, on: display) {
                return cropped
            }
            Log.capture.notice("No snapshot for display \(displayID, privacy: .public); capturing live")
            let fresh = try await CaptureService.shareableContent()
            return try await CaptureService.capture(region: cgRect, on: display, content: fresh)

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
            if let snapshot = snapshots[displayID] {
                return snapshot
            }
            // Either there was no overlay (one display) or its snapshot failed.
            // Fresh content either way, for the same reason as above.
            let fresh = try await CaptureService.shareableContent()
            return try await CaptureService.capture(display: display, content: fresh)
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

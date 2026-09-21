import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Everything that talks to ScreenCaptureKit.
nonisolated enum CaptureService {
    enum Failure: LocalizedError {
        case noDisplays
        case captureProducedNoImage
        case regionTooSmall

        var errorDescription: String? {
            switch self {
            case .noDisplays: "No displays are available to capture."
            case .captureProducedNoImage: "The screenshot came back empty."
            case .regionTooSmall: "That selection was too small to capture."
            }
        }
    }

    /// The smallest capture worth taking, in points. Below this it's almost
    /// certainly a stray click rather than a deliberate drag.
    static let minimumRegionSize: CGFloat = 4

    static func shareableContent() async throws -> SCShareableContent {
        // Desktop windows (the wallpaper and its icons) are included so that a
        // region drag over an empty patch of desktop captures the wallpaper
        // rather than black. On-screen windows only — off-screen ones can't be
        // what the user is pointing at.
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    // MARK: - Capturing

    /// `cgGlobalRect` is in Core Graphics global coordinates — top-left origin.
    /// The conversion from AppKit's bottom-left space happens at the call site,
    /// because it needs `NSScreen` and therefore the main actor, and this whole
    /// type is deliberately off it.
    static func capture(region cgGlobalRect: CGRect, on display: SCDisplay, content: SCShareableContent) async throws -> CapturedImage {
        guard cgGlobalRect.width >= minimumRegionSize, cgGlobalRect.height >= minimumRegionSize else {
            throw Failure.regionTooSmall
        }

        let filter = displayFilterExcludingOurselves(display: display, content: content)
        let scale = CGFloat(filter.pointPixelScale)

        // sourceRect is in display-local points with a top-left origin.
        let local = cgGlobalRect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)

        let config = SCScreenshotConfiguration()
        config.sourceRect = local
        config.width = pixels(local.width, scale)
        config.height = pixels(local.height, scale)
        config.showsCursor = false

        return try await run(filter: filter, config: config, scale: scale, description: nil)
    }

    static func capture(window: SCWindow) async throws -> CapturedImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)

        let config = SCScreenshotConfiguration()
        config.width = pixels(filter.contentRect.width, scale)
        config.height = pixels(filter.contentRect.height, scale)
        config.showsCursor = false
        // No system shadow in the pixels. The compositor draws its own, so a
        // window capture and a region capture get framed identically instead of
        // one of them arriving with a shadow baked into a transparent margin.
        config.ignoreShadows = true
        config.includeChildWindows = true

        return try await run(filter: filter, config: config, scale: scale, description: describe(window))
    }

    static func capture(display: SCDisplay, content: SCShareableContent) async throws -> CapturedImage {
        let filter = displayFilterExcludingOurselves(display: display, content: content)
        let scale = CGFloat(filter.pointPixelScale)

        let config = SCScreenshotConfiguration()
        config.width = pixels(filter.contentRect.width, scale)
        config.height = pixels(filter.contentRect.height, scale)
        config.showsCursor = false

        return try await run(filter: filter, config: config, scale: scale, description: nil)
    }

    // MARK: - Plumbing

    private static func run(filter: SCContentFilter, config: SCScreenshotConfiguration, scale: CGFloat, description: String?) async throws -> CapturedImage {
        let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: config)
        guard let image = output.sdrImage else { throw Failure.captureProducedNoImage }
        return CapturedImage(image: image, scale: scale, sourceDescription: description)
    }

    /// A filter over one display that leaves *us* out of it.
    ///
    /// Without this the selection overlay would be in its own screenshot. The
    /// alternative — hide the overlays, wait for the screen to redraw, then
    /// capture — is a race, and a visible flicker when it's lost.
    private static func displayFilterExcludingOurselves(display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
        let ourselves = content.applications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        return SCContentFilter(display: display, excludingApplications: ourselves, exceptingWindows: [])
    }

    private static func pixels(_ points: CGFloat, _ scale: CGFloat) -> Int {
        max(1, Int((points * scale).rounded()))
    }

    /// "Safari — Apple", or just "Safari" when the window has no useful title.
    /// Used only to prefill the legend title.
    static func describe(_ window: SCWindow) -> String? {
        let app = window.owningApplication?.applicationName
        let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines)

        return switch (app, title) {
        case let (app?, title?) where !title.isEmpty && title != app: "\(app) — \(title)"
        case let (app?, _): app
        case let (_, title?) where !title.isEmpty: title
        default: nil
        }
    }
}

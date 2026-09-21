import CoreGraphics

/// A screenshot, straight out of ScreenCaptureKit and before any markup.
///
/// `@unchecked Sendable` because `CGImage` is immutable once created but isn't
/// declared `Sendable` by CoreGraphics. Nothing here is ever mutated after init.
nonisolated struct CapturedImage: @unchecked Sendable {
    /// What was captured. The compositor frames a window differently from a
    /// rectangle of screen: a window arrives with its own rounded corners
    /// already cut out of the alpha, so imposing a second, different radius on
    /// top of them is what produces the dark wedge in the corner.
    nonisolated enum Source: Sendable {
        case region, window, display

        /// True when the image has transparent edges of its own to respect.
        var hasOwnShape: Bool { self == .window }
    }

    let image: CGImage
    var source: Source = .region
    /// Pixels per point — 2 on a Retina display, 1 on an external 1x monitor.
    /// The compositor needs this to lay out at point sizes and render at pixel
    /// sizes, and it's how the exported PNG gets its DPI.
    let scale: CGFloat
    /// What was captured, if we can tell: an app name, or an app and a window
    /// title. Used to prefill the legend's title field, never shown elsewhere.
    let sourceDescription: String?

    var pixelSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }

    var pointSize: CGSize {
        CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }
}

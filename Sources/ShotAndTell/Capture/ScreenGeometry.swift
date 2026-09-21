import AppKit
import CoreGraphics

/// Conversions between the two coordinate spaces this app has to live in.
///
/// AppKit (`NSScreen`, mouse events, windows) puts the origin at the *bottom*
/// left of the primary display with y increasing upwards. Core Graphics and
/// ScreenCaptureKit (`CGDisplayBounds`, `SCDisplay.frame`, `SCWindow.frame`) put
/// it at the *top* left with y increasing downwards. Mixing them up produces a
/// capture that's correct in x and mirrored in y, which is exactly the kind of
/// bug that looks like a ScreenCaptureKit problem for an hour.
enum ScreenGeometry {
    /// The primary display's height in points — the pivot for flipping y. The
    /// primary display is the one whose AppKit frame has its origin at zero;
    /// everything global is measured from its top-left in CG space.
    private static var primaryHeight: CGFloat {
        NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 0
    }

    static func cgGlobal(fromCocoa rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func cocoaGlobal(fromCG rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func cgGlobal(fromCocoa point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// The `NSScreen` a CG-space display id belongs to, for turning a display
    /// back into something AppKit can position a window on.
    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return id == displayID
        }
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

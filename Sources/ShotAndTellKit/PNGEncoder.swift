import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// PNG encoding, shared by the phase 1 clipboard path and the phase 4 exporter.
nonisolated enum PNGEncoder {
    enum Failure: Error {
        case couldNotCreateDestination
        case couldNotFinalise
    }

    /// Encodes at the image's native pixel size, tagging the DPI so that
    /// pasting a 2x capture into something that respects DPI lands at the size
    /// it appeared on screen rather than at twice that.
    static func encode(_ image: CGImage, scale: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw Failure.couldNotCreateDestination
        }

        let dpi = 72.0 * scale
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw Failure.couldNotFinalise
        }
        return data as Data
    }
}

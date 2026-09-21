#!/usr/bin/env swift
//
// Renders Sources/ShotAndTell/Assets.xcassets/AppIcon.appiconset.
//
// The icon is generated rather than drawn by hand so it can be reasoned about
// and adjusted: run `swift scripts/make-icon.swift` from the repo root after
// changing anything here.
//
// The motif is the app in one picture — a screenshot with a numbered marker on
// it. At 16pt all that survives is a dark tile, a pale card and a red dot,
// which is exactly the right amount.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = FileManager.default.currentDirectoryPath
let outputDirectory = "\(root)/Sources/ShotAndTell/Assets.xcassets/AppIcon.appiconset"

func colour(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func drawIcon(size: CGFloat) -> CGImage? {
    let pixels = Int(size)
    guard let context = CGContext(
        data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else { return nil }

    let unit = size / 1024
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // Apple's macOS icon grid: the rounded square is 824 of 1024, leaving room
    // for the shadow the system doesn't draw for us.
    let plate = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let plateRadius = 185 * unit
    let platePath = CGPath(roundedRect: plate, cornerWidth: plateRadius, cornerHeight: plateRadius, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 24 * unit, color: colour(0x000000, 0.28))
    context.addPath(platePath)
    context.setFillColor(colour(0x22222A))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(platePath)
    context.clip()
    if let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [colour(0x33333D), colour(0x17171C)] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: plate.midX, y: plate.maxY),
            end: CGPoint(x: plate.midX, y: plate.minY),
            options: []
        )
    }
    context.restoreGState()

    // The captured screenshot: a pale card, sitting slightly low and left so
    // the marker has somewhere to be.
    let card = CGRect(x: 232 * unit, y: 250 * unit, width: 470 * unit, height: 380 * unit)
    let cardPath = CGPath(roundedRect: card, cornerWidth: 34 * unit, cornerHeight: 34 * unit, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8 * unit), blur: 26 * unit, color: colour(0x000000, 0.45))
    context.addPath(cardPath)
    context.setFillColor(colour(0xF6F6F8))
    context.fillPath()
    context.restoreGState()

    // Three lines of "content". Only legible from 128pt up; at small sizes they
    // blur into a plausible texture rather than turning to mush.
    context.setFillColor(colour(0xC6C6D0))
    let lineX = card.minX + 46 * unit
    for (index, width) in [300, 240, 180].enumerated() {
        let y = card.maxY - (110 + 78 * CGFloat(index)) * unit
        context.addPath(CGPath(
            roundedRect: CGRect(x: lineX, y: y, width: CGFloat(width) * unit, height: 30 * unit),
            cornerWidth: 15 * unit, cornerHeight: 15 * unit, transform: nil
        ))
    }
    context.fillPath()

    // The marker, overlapping the card's corner: the one element that has to
    // survive to 16pt.
    let markerCentre = CGPoint(x: card.maxX - 6 * unit, y: card.maxY - 6 * unit)
    let markerRadius = 128 * unit

    context.setFillColor(colour(0xFFFFFF))
    context.fillEllipse(in: CGRect(
        x: markerCentre.x - markerRadius - 14 * unit,
        y: markerCentre.y - markerRadius - 14 * unit,
        width: (markerRadius + 14 * unit) * 2,
        height: (markerRadius + 14 * unit) * 2
    ))
    context.setFillColor(colour(0xE5484D))
    context.fillEllipse(in: CGRect(
        x: markerCentre.x - markerRadius,
        y: markerCentre.y - markerRadius,
        width: markerRadius * 2,
        height: markerRadius * 2
    ))

    // The numeral, set in the system font. A hand-built glyph was tried first
    // and looked like a hammer; this is a build-time script, so depending on the
    // system font costs nothing at runtime.
    let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 176 * unit, nil)
        ?? CTFontCreateWithName("Helvetica-Bold" as CFString, 176 * unit, nil)
    let numeral = NSAttributedString(string: "1", attributes: [
        kCTFontAttributeName as NSAttributedString.Key: font,
        kCTForegroundColorAttributeName as NSAttributedString.Key: colour(0xFFFFFF),
    ])
    let line = CTLineCreateWithAttributedString(numeral)
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    let glyphWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
    context.textPosition = CGPoint(
        x: markerCentre.x - glyphWidth / 2,
        y: markerCentre.y - (ascent - descent) / 2
    )
    CTLineDraw(line, context)

    return context.makeImage()
}

func write(_ image: CGImage, to name: String) throws {
    let url = URL(fileURLWithPath: "\(outputDirectory)/\(name)")
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "icon", code: 1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "icon", code: 2) }
}

try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

// macOS wants every size drawn at its own scale rather than downsampled from
// one master: hinting a 16pt icon from 1024 turns it to soup.
let sizes: [CGFloat] = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
    guard let image = drawIcon(size: size) else { continue }
    try write(image, to: "icon_\(Int(size)).png")
}

struct Entry: Encodable {
    let filename: String
    let idiom = "mac"
    let scale: String
    let size: String
}

let entries: [Entry] = [
    Entry(filename: "icon_16.png", scale: "1x", size: "16x16"),
    Entry(filename: "icon_32.png", scale: "2x", size: "16x16"),
    Entry(filename: "icon_32.png", scale: "1x", size: "32x32"),
    Entry(filename: "icon_64.png", scale: "2x", size: "32x32"),
    Entry(filename: "icon_128.png", scale: "1x", size: "128x128"),
    Entry(filename: "icon_256.png", scale: "2x", size: "128x128"),
    Entry(filename: "icon_256.png", scale: "1x", size: "256x256"),
    Entry(filename: "icon_512.png", scale: "2x", size: "256x256"),
    Entry(filename: "icon_512.png", scale: "1x", size: "512x512"),
    Entry(filename: "icon_1024.png", scale: "2x", size: "512x512"),
]

struct Catalog: Encodable {
    let images: [Entry]
    let info = ["author": "xcode", "version": 1] as [String: AnyHashable]

    enum CodingKeys: String, CodingKey { case images, info }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(images, forKey: .images)
        var info = container.nestedContainer(keyedBy: InfoKeys.self, forKey: .info)
        try info.encode("xcode", forKey: .author)
        try info.encode(1, forKey: .version)
    }
    enum InfoKeys: String, CodingKey { case author, version }
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(Catalog(images: entries)).write(to: URL(fileURLWithPath: "\(outputDirectory)/Contents.json"))

print("Wrote \(sizes.count) icon sizes to \(outputDirectory)")

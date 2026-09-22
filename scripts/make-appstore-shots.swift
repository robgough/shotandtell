#!/usr/bin/env swift
//
// Builds the App Store screenshots from source captures.
//
//   swift scripts/make-appstore-shots.swift <source-dir> <output-dir>
//
// macOS listings take 2880×1800 or 2560×1600 and nothing else, so the canvas
// is fixed and the source is fitted into it rather than the other way round.
// Every source is a real capture of the real app — the compositions come out
// of Compositor itself, and the window shots are screencaptures of the window.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let W: CGFloat = 2880, H: CGFloat = 1800

func colour(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func load(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fatalError("can't read \(path)") }
    return image
}

func font(_ size: CGFloat, _ weight: CGFloat) -> CTFont {
    let base = CTFontCreateUIFontForLanguage(.system, size, nil)!
    let traits = [kCTFontWeightTrait: weight] as CFDictionary
    let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontTraitsAttribute: traits] as CFDictionary)
    return CTFontCreateCopyWithAttributes(base, size, nil, descriptor)
}

/// One line of text. `align` is -1 leading, 0 centred.
@discardableResult
func draw(_ text: String, _ f: CTFont, _ c: CGColor, x: CGFloat, baseline: CGFloat,
          align: CGFloat = 0, in ctx: CGContext) -> CGFloat {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
        kCTFontAttributeName as NSAttributedString.Key: f,
        kCTForegroundColorAttributeName as NSAttributedString.Key: c,
        kCTKernAttributeName as NSAttributedString.Key: -CTFontGetSize(f) * 0.012,
    ]))
    let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    ctx.textPosition = CGPoint(x: align == 0 ? x - width / 2 : x, y: baseline)
    CTLineDraw(line, ctx)
    return width
}

func newCanvas() -> CGContext {
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                            | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.setShouldSmoothFonts(true)
    ctx.interpolationQuality = .high

    // The same near-black the app's own dark canvas uses, warmed very slightly
    // so the red glow has something to sit in.
    ctx.drawLinearGradient(
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                   colors: [colour(0x2B2B33), colour(0x131317)] as CFArray, locations: [0, 1])!,
        start: CGPoint(x: W / 2, y: H), end: CGPoint(x: W / 2, y: 0), options: [])
    ctx.drawRadialGradient(
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                   colors: [colour(0xE5484D, 0.22), colour(0xE5484D, 0)] as CFArray, locations: [0, 1])!,
        startCenter: CGPoint(x: 560, y: H - 140), startRadius: 0,
        endCenter: CGPoint(x: 560, y: H - 140), endRadius: 1600, options: [])
    return ctx
}

/// Draws a window or composition inside `box`, fitted, with a shadow.
///
/// The corner radius matters: a window screencapture keeps the rounded corners
/// macOS cut out of it, and whatever was on the desktop behind shows through
/// the four corner pixels. Clipping to a slightly *larger* radius than the
/// window's own throws those away.
func place(_ image: CGImage, in box: CGRect, radius: CGFloat, ctx: CGContext) {
    let scale = min(box.width / CGFloat(image.width), box.height / CGFloat(image.height))
    let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    let rect = CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2,
                      width: size.width, height: size.height)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -30), blur: 80, color: colour(0x000000, 0.6))
    ctx.addPath(path)
    ctx.setFillColor(colour(0x000000))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.draw(image, in: rect)
    ctx.restoreGState()

    ctx.addPath(path)
    ctx.setStrokeColor(colour(0xFFFFFF, 0.10))
    ctx.setLineWidth(2)
    ctx.strokePath()
}

func write(_ ctx: CGContext, to path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                               UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("can't write \(path)") }
    print("wrote \(path)")
}

func heading(_ headline: String, _ sub: String, in ctx: CGContext) {
    draw(headline, font(108, 0.36), colour(0xFFFFFF), x: W / 2, baseline: H - 236, in: ctx)
    draw(sub, font(50, 0), colour(0xB4B4BE), x: W / 2, baseline: H - 328, in: ctx)
}

let source = CommandLine.arguments[1]
let out = CommandLine.arguments[2]

/// A wide shot: heading across the top, one image filling the rest.
func wide(_ file: String, _ headline: String, _ sub: String, radius: CGFloat, to name: String) {
    let ctx = newCanvas()
    heading(headline, sub, in: ctx)
    place(load("\(source)/\(file)"), in: CGRect(x: 150, y: 140, width: W - 300, height: 1240),
          radius: radius, ctx: ctx)
    write(ctx, to: "\(out)/\(name)")
}

/// A portrait shot: the window on the left, a short list of claims beside it.
func portrait(_ file: String, _ headline: String, _ sub: String, bullets: [String], to name: String) {
    let ctx = newCanvas()
    heading(headline, sub, in: ctx)
    place(load("\(source)/\(file)"), in: CGRect(x: 280, y: 140, width: 1080, height: 1270),
          radius: 26, ctx: ctx)

    var baseline: CGFloat = 960
    for bullet in bullets {
        ctx.setFillColor(colour(0xE5484D))
        ctx.fillEllipse(in: CGRect(x: 1600, y: baseline + 8, width: 20, height: 20))
        draw(bullet, font(54, 0.1), colour(0xE8E8EE), x: 1664, baseline: baseline, align: -1, in: ctx)
        baseline -= 130
    }
    write(ctx, to: "\(out)/\(name)")
}

// A window screencapture keeps macOS's own corner radius; the compositions are
// square-cornered images and want the frame's radius instead.
wide("win.png",
     "Point at it, then say what you mean",
     "Numbered pins, arrows and boxes — each one with its own line of description.",
     radius: 30, to: "01-editor.png")

wide("export.png",
     "One image, with the words attached",
     "The shot on a background, the legend beside it, on the clipboard and ready to paste.",
     radius: 20, to: "02-result.png")

wide("export2.png",
     "Black out what they don’t need to see",
     "Redactions are drawn into the exported pixels, not laid over them.",
     radius: 20, to: "03-redact.png")

portrait("settings.png",
         "Set it up once",
         "A shortcut that works in any app, and sensible defaults for everything after that.",
         bullets: ["One keystroke, from anywhere",
                   "Never touches the network",
                   "Copies, saves a PNG, or both"],
         to: "04-settings.png")

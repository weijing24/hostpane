#!/usr/bin/env swift
import AppKit
import Foundation

// Baked squircle with transparent corners. This app ships an icns (no
// Assets.car / Icon Composer), and macOS Tahoe leaves that unmasked — a
// full-bleed square therefore shows as a square in the Dock. The ring
// follows the squircle; do not fill the corner pixels.
//
// Asset-catalog icons are masked to an 824×824 squircle: 100px of margin
// on a 1024 canvas. Bake that margin into the icns so the Dock tile
// matches neighboring apps. The README image stays full-bleed.

let canvas = CGFloat(1024)
let bounds = NSRect(x: 0, y: 0, width: canvas, height: canvas)
let systemMargin = CGFloat(100)
let squircleN = CGFloat(5)

let args = Array(CommandLine.arguments.dropFirst())
let readme = args.contains("--readme")
let margin = readme ? CGFloat(0) : systemMargin
let artboard = bounds.insetBy(dx: margin, dy: margin)
let ringWidth = artboard.width * 0.078
let out = args.first(where: { $0 != "--readme" })
    ?? (readme
        ? "Sources/Hostpane/Resources/AppIcon-readme.png"
        : "Sources/Hostpane/Resources/AppIcon-1024.png")

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas),
    pixelsHigh: Int(canvas),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Failed to create bitmap\n", stderr)
    exit(1)
}
bitmap.size = NSSize(width: canvas, height: canvas)
NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Failed to create graphics context\n", stderr)
    exit(1)
}
context.imageInterpolation = .high
NSGraphicsContext.current = context

let pink = NSColor(srgbRed: 1.00, green: 0.28, blue: 0.72, alpha: 1)
let violet = NSColor(srgbRed: 0.62, green: 0.38, blue: 1.00, alpha: 1)
let blue = NSColor(srgbRed: 0.20, green: 0.52, blue: 1.00, alpha: 1)
let cyan = NSColor(srgbRed: 0.22, green: 0.68, blue: 1.00, alpha: 1)
let gradient = NSGradient(colors: [pink, violet, blue, cyan])!

let outer = squirclePath(in: artboard, n: squircleN)
gradient.draw(in: outer, angle: -40)

let plateRect = artboard.insetBy(dx: ringWidth, dy: ringWidth)
let platePath = squirclePath(in: plateRect, n: squircleN)

NSGraphicsContext.current?.saveGraphicsState()
platePath.addClip()
NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1).setFill()
platePath.fill()
NSGradient(
    colors: [
        NSColor(srgbRed: 0.24, green: 0.24, blue: 0.26, alpha: 0.65),
        NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 0)
    ]
)!.draw(
    from: NSPoint(x: plateRect.minX, y: plateRect.maxY),
    to: NSPoint(x: plateRect.midX + plateRect.width * 0.08, y: plateRect.midY),
    options: []
)
NSGraphicsContext.current?.restoreGraphicsState()

let rocket = rocketPath()
let rocketBox = NSRect(x: 0, y: 0, width: 100, height: 160)
let targetHeight = plateRect.width * 0.50
let scale = targetHeight / rocketBox.height
var transform = AffineTransform()
transform.translate(
    x: artboard.midX + artboard.width * (0.445 - 0.5),
    y: artboard.midY + artboard.height * (0.512 - 0.5)
)
transform.rotate(byDegrees: -40)
transform.scale(scale)
transform.translate(x: -rocketBox.midX, y: -rocketBox.midY)
rocket.transform(using: transform)
NSColor.white.setFill()
rocket.fill()

let rocketBounds = rocket.bounds
let dashWidth = plateRect.width * 0.125
let dashHeight = plateRect.width * 0.052
let dashRect = NSRect(
    x: rocketBounds.maxX + plateRect.width * 0.055,
    y: rocketBounds.midY - dashHeight / 2,
    width: dashWidth,
    height: dashHeight
)
NSBezierPath(roundedRect: dashRect, xRadius: dashHeight / 2, yRadius: dashHeight / 2).fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: URL(fileURLWithPath: out).deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")

func squirclePath(in rect: NSRect, n: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let a = rect.width / 2
    let b = rect.height / 2
    let cx = rect.midX
    let cy = rect.midY
    let steps = 360
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let cosT = cos(t)
        let sinT = sin(t)
        let x = cx + a * pow(abs(cosT), 2 / n) * (cosT >= 0 ? 1 : -1)
        let y = cy + b * pow(abs(sinT), 2 / n) * (sinT >= 0 ? 1 : -1)
        if i == 0 {
            path.move(to: NSPoint(x: x, y: y))
        } else {
            path.line(to: NSPoint(x: x, y: y))
        }
    }
    path.close()
    return path
}

func rocketPath() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 50, y: 158))
    path.curve(
        to: NSPoint(x: 69, y: 114),
        controlPoint1: NSPoint(x: 63, y: 151),
        controlPoint2: NSPoint(x: 69, y: 132)
    )
    path.line(to: NSPoint(x: 69, y: 62))
    path.line(to: NSPoint(x: 92, y: 40))
    path.line(to: NSPoint(x: 69, y: 48))
    path.line(to: NSPoint(x: 63, y: 38))
    path.curve(
        to: NSPoint(x: 37, y: 38),
        controlPoint1: NSPoint(x: 57, y: 28),
        controlPoint2: NSPoint(x: 43, y: 28)
    )
    path.line(to: NSPoint(x: 31, y: 48))
    path.line(to: NSPoint(x: 8, y: 40))
    path.line(to: NSPoint(x: 31, y: 62))
    path.line(to: NSPoint(x: 31, y: 114))
    path.curve(
        to: NSPoint(x: 50, y: 158),
        controlPoint1: NSPoint(x: 31, y: 132),
        controlPoint2: NSPoint(x: 37, y: 151)
    )
    path.close()

    let window = NSBezierPath(ovalIn: NSRect(x: 41, y: 98, width: 18, height: 18))
    path.append(window)
    path.windingRule = .evenOdd

    let flame = NSBezierPath()
    flame.move(to: NSPoint(x: 50, y: 4))
    flame.curve(
        to: NSPoint(x: 38, y: 28),
        controlPoint1: NSPoint(x: 40, y: 6),
        controlPoint2: NSPoint(x: 36, y: 18)
    )
    flame.curve(
        to: NSPoint(x: 50, y: 22),
        controlPoint1: NSPoint(x: 40, y: 24),
        controlPoint2: NSPoint(x: 46, y: 22)
    )
    flame.curve(
        to: NSPoint(x: 62, y: 28),
        controlPoint1: NSPoint(x: 54, y: 22),
        controlPoint2: NSPoint(x: 60, y: 24)
    )
    flame.curve(
        to: NSPoint(x: 50, y: 4),
        controlPoint1: NSPoint(x: 64, y: 18),
        controlPoint2: NSPoint(x: 60, y: 6)
    )
    flame.close()
    path.append(flame)
    return path
}

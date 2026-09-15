#!/usr/bin/env swift
import AppKit
import Foundation

// Dark squircle, pink-to-blue ring, white rocket.
// Fill the 1024 canvas. A transparent margin becomes a black square in
// Command-Tab (the switcher does not apply the Dock's icon mask).
let canvas = CGFloat(1024)
let margin = CGFloat(0)
let inner = NSRect(x: margin, y: margin, width: canvas - margin * 2, height: canvas - margin * 2)
let cornerRadius = inner.width * 0.223
let ringWidth = inner.width * 0.078

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

let bounds = NSRect(x: 0, y: 0, width: canvas, height: canvas)
// Opaque fill so Command-Tab does not composite transparent corners as black.
NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1).setFill()
bounds.fill()

let squircle = NSBezierPath(roundedRect: inner, xRadius: cornerRadius, yRadius: cornerRadius)

// No drop shadow: it would clip at the canvas edge and show up in Cmd-Tab.

let pink = NSColor(srgbRed: 1.00, green: 0.28, blue: 0.72, alpha: 1)
let violet = NSColor(srgbRed: 0.62, green: 0.38, blue: 1.00, alpha: 1)
let blue = NSColor(srgbRed: 0.20, green: 0.52, blue: 1.00, alpha: 1)
let cyan = NSColor(srgbRed: 0.22, green: 0.68, blue: 1.00, alpha: 1)
NSGradient(colors: [pink, violet, blue, cyan])!.draw(in: squircle, angle: -40)

let plate = inner.insetBy(dx: ringWidth, dy: ringWidth)
let plateRadius = max(plate.width * 0.223, 1)
let platePath = NSBezierPath(roundedRect: plate, xRadius: plateRadius, yRadius: plateRadius)

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
    from: NSPoint(x: plate.minX, y: plate.maxY),
    to: NSPoint(x: plate.midX + plate.width * 0.08, y: plate.midY),
    options: []
)
NSGraphicsContext.current?.restoreGraphicsState()

let rocket = rocketPath()
let rocketBox = NSRect(x: 0, y: 0, width: 100, height: 160)
let targetHeight = plate.width * 0.50
let scale = targetHeight / rocketBox.height
var transform = AffineTransform()
transform.translate(x: canvas * 0.445, y: canvas * 0.512)
transform.rotate(byDegrees: -40)
transform.scale(scale)
transform.translate(x: -rocketBox.midX, y: -rocketBox.midY)
rocket.transform(using: transform)
NSColor.white.setFill()
rocket.fill()

let rocketBounds = rocket.bounds
let dashWidth = plate.width * 0.125
let dashHeight = plate.width * 0.052
let dashRect = NSRect(
    x: rocketBounds.maxX + plate.width * 0.055,
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

let out = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Sources/Hostpane/Resources/AppIcon-1024.png"
try FileManager.default.createDirectory(
    at: URL(fileURLWithPath: out).deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: URL(fileURLWithPath: out))
print("Wrote \(out), margin \(Int(margin))")

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

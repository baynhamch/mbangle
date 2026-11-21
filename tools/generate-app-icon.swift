#!/usr/bin/env swift
import AppKit

// Original vector artwork for mbangle. All geometry is drawn in a 1024-point
// canvas and rendered directly at each macOS icon resolution. The lid profile
// uses a 104-degree interior angle, matching the app's displayed 76-degree target.
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "mbangle/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func stroke(_ points: [NSPoint], color: NSColor, width: CGFloat) {
    let path = NSBezierPath()
    path.move(to: points[0])
    points.dropFirst().forEach { path.line(to: $0) }
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    color.setStroke()
    path.stroke()
}

func drawIcon(pixels: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
        pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(pixels) / 1024)
    transform.concat()

    let tile = NSBezierPath(roundedRect: NSRect(x: 65, y: 65, width: 894, height: 894),
        xRadius: 192, yRadius: 192)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 27
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.15, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.21, green: 0.26, blue: 0.31, alpha: 1),
        ending: NSColor(calibratedRed: 0.07, green: 0.10, blue: 0.14, alpha: 1))!
        .draw(in: tile, angle: -90)
    let rim = NSBezierPath(roundedRect: NSRect(x: 67, y: 67, width: 890, height: 890),
        xRadius: 190, yRadius: 190)
    rim.lineWidth = 2
    NSColor.white.withAlphaComponent(0.15).setStroke()
    rim.stroke()

    let hinge = NSPoint(x: 340, y: 330)
    let lidAngle = 104.0 * Double.pi / 180
    let top = NSPoint(x: hinge.x + 420 * cos(lidAngle), y: hinge.y + 420 * sin(lidAngle))
    let tip = NSPoint(x: 776, y: hinge.y)
    let compact = pixels <= 32
    let profileWidth: CGFloat = compact ? 58 : 48

    // A restrained lower edge gives the silver profile depth at Dock sizes.
    NSGraphicsContext.saveGraphicsState()
    let profileShadow = NSShadow()
    profileShadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    profileShadow.shadowBlurRadius = 18
    profileShadow.shadowOffset = NSSize(width: 0, height: -12)
    profileShadow.set()
    stroke([top, hinge, tip],
        color: NSColor(calibratedRed: 0.55, green: 0.63, blue: 0.68, alpha: 1),
        width: profileWidth + 6)
    NSGraphicsContext.restoreGraphicsState()
    let face = [top, hinge, tip].map { NSPoint(x: $0.x, y: $0.y + 4) }
    stroke(face, color: NSColor(calibratedRed: 0.88, green: 0.93, blue: 0.95, alpha: 1),
        width: profileWidth)

    let arc = NSBezierPath()
    arc.appendArc(withCenter: hinge, radius: 210, startAngle: 12, endAngle: 92)
    arc.lineWidth = compact ? 33 : 25
    arc.lineCapStyle = .round
    let alignedGreen = NSColor(calibratedRed: 0.40, green: 0.90, blue: 0.64, alpha: 1)
    if pixels >= 128 {
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = alignedGreen.withAlphaComponent(0.18)
        glow.shadowBlurRadius = 20
        glow.shadowOffset = .zero
        glow.set()
        alignedGreen.setStroke()
        arc.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
    alignedGreen.setStroke()
    arc.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try drawIcon(pixels: points * scale).write(to: output.appendingPathComponent(filename))
        images.append(["filename": filename, "idiom": "mac",
                       "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
let manifest: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))
print("Rendered \(images.count) macOS app icon variants.")

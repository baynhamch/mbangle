#!/usr/bin/env swift
import AppKit

// Original vector artwork for mbangle. All geometry is drawn in a 1024-point
// canvas and rendered directly at each macOS icon resolution.
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
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.19)
    shadow.shadowBlurRadius = 27
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(white: 0.88, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.97, green: 0.975, blue: 0.98, alpha: 1),
        ending: NSColor(calibratedRed: 0.82, green: 0.84, blue: 0.85, alpha: 1))!
        .draw(in: tile, angle: -90)
    tile.lineWidth = 2
    NSColor.white.withAlphaComponent(0.76).setStroke()
    tile.stroke()

    let hinge = NSPoint(x: 315, y: 337)
    let top = NSPoint(x: 245, y: 699)
    let tip = NSPoint(x: 762, y: 337)
    let graphite = NSColor(calibratedRed: 0.25, green: 0.29, blue: 0.31, alpha: 1)

    // A quiet inset highlight gives the mark a machined-aluminum edge.
    stroke([NSPoint(x: top.x, y: top.y + 3), NSPoint(x: hinge.x, y: hinge.y + 3),
            NSPoint(x: tip.x, y: tip.y + 3)],
        color: .white.withAlphaComponent(0.7), width: 47)
    stroke([top, hinge, tip], color: graphite, width: pixels <= 32 ? 52 : 44)

    let arc = NSBezierPath()
    arc.appendArc(withCenter: hinge, radius: 189, startAngle: 6, endAngle: 95)
    arc.lineWidth = pixels <= 32 ? 27 : 21
    arc.lineCapStyle = .round
    NSColor(calibratedRed: 0.29, green: 0.49, blue: 0.41, alpha: 1).setStroke()
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

// Renders Resources/AppIcon.icns: a crescent moon over a dark screen.
// Usage: swift scripts/make-icon.swift <output-dir>
import AppKit

let outputDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = s * 0.1
    let body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let squircle = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.10, green: 0.12, blue: 0.22, alpha: 1),
                        NSColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1)])!.draw(in: squircle, angle: -90)

    // Crescent: a bright disc with an offset disc punched out.
    let r = body.width * 0.26
    let center = NSPoint(x: body.midX - r * 0.1, y: body.midY + r * 0.05)
    let moon = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    let bite = NSBezierPath(ovalIn: NSRect(x: center.x - r * 0.35, y: center.y - r * 0.6, width: r * 2, height: r * 2))
    NSGraphicsContext.current?.saveGraphicsState()
    moon.addClip()
    NSColor(red: 1.0, green: 0.86, blue: 0.45, alpha: 1).setFill()
    moon.fill()
    NSGraphicsContext.current?.compositingOperation = .clear
    bite.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // A small green "still working" light.
    let dot = body.width * 0.07
    NSColor(red: 0.30, green: 0.90, blue: 0.55, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: body.maxX - body.width * 0.2, y: body.minY + body.width * 0.13, width: dot, height: dot)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputDir.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)

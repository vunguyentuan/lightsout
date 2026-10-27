// Renders the website's social preview (og-image.png, 1200×630) from the app icon.
// Usage: swift scripts/make-site-images.swift Resources/AppIcon.icns site/public/assets
import AppKit

let args = CommandLine.arguments
let icon = NSImage(contentsOfFile: args[1])!
let outDir = URL(fileURLWithPath: args[2])

let width = 1200, height = 630
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSColor(red: 0.043, green: 0.043, blue: 0.047, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

icon.draw(in: NSRect(x: 96, y: 195, width: 240, height: 240))

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, at point: NSPoint, kern: CGFloat) {
    NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .kern: kern,
    ]).draw(at: point)
}
text("Lights Out", size: 84, weight: .semibold, color: NSColor(white: 0.95, alpha: 1), at: NSPoint(x: 384, y: 330), kern: -3)
text("Screen off. Mac awake.", size: 44, weight: .regular, color: NSColor(white: 0.6, alpha: 1), at: NSPoint(x: 388, y: 262), kern: -1)
text("Agents keep working while the room stays dark.", size: 26, weight: .regular, color: NSColor(white: 0.42, alpha: 1), at: NSPoint(x: 390, y: 208), kern: 0)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent("og-image.png"))

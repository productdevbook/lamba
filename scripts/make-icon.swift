// Renders the Lamba app icon (1024×1024 PNG) — a glowing charging LED on a dark squircle.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824pt squircle centered in a 1024 canvas.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = rgb(0, 0, 0, 0.35)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
rgb(20, 22, 30).setFill()
squircle.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
squircle.addClip()
NSGradient(starting: rgb(38, 42, 56), ending: rgb(12, 13, 18))!.draw(in: tile, angle: -90)

// Soft two-tone glow behind the LED.
NSGradient(colors: [rgb(255, 158, 26, 0.55), rgb(255, 158, 26, 0)])!
    .draw(fromCenter: NSPoint(x: 560, y: 440), radius: 0, toCenter: NSPoint(x: 560, y: 440), radius: 330, options: [])
NSGradient(colors: [rgb(61, 219, 115, 0.45), rgb(61, 219, 115, 0)])!
    .draw(fromCenter: NSPoint(x: 460, y: 500), radius: 0, toCenter: NSPoint(x: 460, y: 500), radius: 300, options: [])

// Cable coming from the left edge into the connector.
let cable = NSBezierPath()
cable.move(to: NSPoint(x: 60, y: 300))
cable.curve(to: NSPoint(x: 300, y: 470), controlPoint1: NSPoint(x: 220, y: 300), controlPoint2: NSPoint(x: 180, y: 470))
cable.lineWidth = 46
cable.lineCapStyle = .round
rgb(225, 228, 236).setStroke()
cable.stroke()

// MagSafe-style connector body.
let plug = NSRect(x: 290, y: 410, width: 420, height: 120)
let plugPath = NSBezierPath(roundedRect: plug, xRadius: 60, yRadius: 60)
NSGradient(starting: rgb(246, 247, 250), ending: rgb(176, 181, 194))!.draw(in: plugPath, angle: -90)
rgb(255, 255, 255, 0.6).setStroke()
plugPath.lineWidth = 3
plugPath.stroke()

// The LED itself.
let ledRect = NSRect(x: 590, y: 446, width: 48, height: 48)
NSGradient(colors: [rgb(255, 210, 120), rgb(255, 158, 26), rgb(255, 120, 0)])!
    .draw(in: NSBezierPath(ovalIn: ledRect), relativeCenterPosition: NSPoint(x: -0.3, y: 0.3))
NSGradient(colors: [rgb(255, 170, 60, 0.75), rgb(255, 170, 60, 0)])!
    .draw(fromCenter: NSPoint(x: 614, y: 470), radius: 0, toCenter: NSPoint(x: 614, y: 470), radius: 120, options: [])

// Lightning bolt above, green → orange.
let bolt = NSBezierPath()
bolt.move(to: NSPoint(x: 540, y: 820))
bolt.line(to: NSPoint(x: 420, y: 640))
bolt.line(to: NSPoint(x: 505, y: 640))
bolt.line(to: NSPoint(x: 470, y: 560))
bolt.line(to: NSPoint(x: 610, y: 710))
bolt.line(to: NSPoint(x: 520, y: 710))
bolt.close()
NSGradient(starting: rgb(61, 219, 115), ending: rgb(255, 158, 26))!.draw(in: bolt, angle: -90)

// Subtle top highlight.
NSGradient(starting: rgb(255, 255, 255, 0), ending: rgb(255, 255, 255, 0.08))!
    .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: 90)
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")

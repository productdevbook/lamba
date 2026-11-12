import AppKit

/// Wallpapers that ship with Lamba, drawn on demand (no image files in the bundle).
/// Stored in a context's look as `builtin:<rawValue>`.
enum BuiltinWallpaper: String, CaseIterable, Identifiable {
    case navy, sand, graphite, forest

    var id: String { rawValue }
    var reference: String { "builtin:\(rawValue)" }

    /// Background, large shape, small shape.
    var colors: (base: NSColor, shapeA: NSColor, shapeB: NSColor) {
        func c(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        switch self {
        case .navy: return (c(0x14203A), c(0x2B4A8A), c(0x1D3463))
        case .sand: return (c(0xF1D9C4), c(0xE3996F), c(0xE9B897))
        case .graphite: return (c(0x26282D), c(0x2C2F35), c(0x2A2C31))
        case .forest: return (c(0x17322A), c(0x2F6B55), c(0x22483C))
        }
    }

    init?(reference: String) {
        guard reference.hasPrefix("builtin:") else { return nil }
        self.init(rawValue: String(reference.dropFirst("builtin:".count)))
    }

    /// Renders the wallpaper for the main screen's pixel size into Application Support and returns
    /// the file. Cached by size, so repeated switches reuse the same PNG.
    func fileURL() -> URL? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let points = NSScreen.main?.frame.size ?? CGSize(width: 1512, height: 982)
        let width = max(Int(points.width * scale), 1), height = max(Int(points.height * scale), 1)

        guard let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Lamba/Wallpapers", isDirectory: true) else { return nil }
        let url = directory.appendingPathComponent("\(rawValue)-\(width)x\(height).png")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        let w = CGFloat(width), h = CGFloat(height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        colors.base.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        // Origin is bottom-left: the large circle sits top-right, the small one bottom-left.
        let large = h * 0.9
        colors.shapeA.setFill()
        NSBezierPath(ovalIn: NSRect(x: w - large * 0.7, y: h - large * 0.6, width: large, height: large)).fill()
        let small = h * 0.55
        colors.shapeB.setFill()
        NSBezierPath(ovalIn: NSRect(x: -small * 0.3, y: -small * 0.35, width: small, height: small)).fill()
        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

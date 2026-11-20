// Renders Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // Standard macOS icon grid: an 824 pt rounded square centered on a 1024 pt canvas.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(srgbRed: 0.36, green: 0.80, blue: 0.98, alpha: 1),
                        NSColor(srgbRed: 0.10, green: 0.45, blue: 0.93, alpha: 1),
                        NSColor(srgbRed: 0.07, green: 0.27, blue: 0.72, alpha: 1)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: path, angle: -90)

    // Soft top highlight.
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(starting: NSColor.white.withAlphaComponent(0.22), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Fan glyph.
    let config = NSImage.SymbolConfiguration(pointSize: 470 * s, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let fan = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let glyphShadow = NSShadow()
        glyphShadow.shadowColor = NSColor(srgbRed: 0.02, green: 0.15, blue: 0.45, alpha: 0.45)
        glyphShadow.shadowBlurRadius = 18 * s
        glyphShadow.shadowOffset = NSSize(width: 0, height: -8 * s)
        NSGraphicsContext.saveGraphicsState()
        glyphShadow.set()
        let rect = NSRect(x: tile.midX - fan.size.width / 2, y: tile.midY - fan.size.height / 2,
                          width: fan.size.width, height: fan.size.height)
        fan.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = render(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent(name))
    }
}
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try render(size: 512).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("assets/icon.png"))
print("Wrote \(output.path)")

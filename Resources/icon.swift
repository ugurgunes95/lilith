// Regenerate the icon: swift Resources/icon.swift && iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

let dir = "/tmp/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
                   (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // Apple icon grid: ~80% body, ~18% corner radius.
    let body = NSBezierPath(roundedRect: NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8),
                            xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(red: 1, green: 0.25, blue: 0.22, alpha: 1),
               ending: NSColor(red: 0.55, green: 0, blue: 0.07, alpha: 1))!.draw(in: body, angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    let moon = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    moon.draw(in: NSRect(x: (s - moon.size.width) / 2, y: (s - moon.size.height) / 2,
                         width: moon.size.width, height: moon.size.height))
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
}

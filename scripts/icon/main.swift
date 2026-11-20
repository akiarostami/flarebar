// Renders Resources/AppIcon.icns from the mark in Sources/Flarebar/BrandIcon.swift.
// Run through scripts/make-icon.sh.
import AppKit

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    let side = CGFloat(pixels)
    // The macOS icon shape: a rounded square inset from the canvas.
    let tile = CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: side * 0.1, dy: side * 0.1)
    let shape = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil)
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let colours = [CGColor(red: 0.984, green: 0.678, blue: 0.255, alpha: 1),
                   CGColor(red: 0.953, green: 0.502, blue: 0.125, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    context.restoreGState()
    let width = tile.width * 0.72
    let mark = CGRect(x: tile.midX - width / 2, y: tile.midY - width * BrandIcon.aspect / 2,
                      width: width, height: width * BrandIcon.aspect)
    BrandIcon.draw(in: mark, colour: .white, context: context)

    // The status dot, as it sits on the menu bar icon: green, on the mark's top right corner,
    // with a ring of the tile's colour to set it apart from the cloud.
    let diameter = tile.width * 0.15
    // Centred on the top right of the mark's smaller lobe.
    let centre = CGPoint(x: mark.minX + mark.width * 0.91, y: mark.minY + mark.height * 0.68)
    let dot = CGRect(x: centre.x - diameter / 2, y: centre.y - diameter / 2, width: diameter, height: diameter)
    context.setFillColor(CGColor(red: 0.965, green: 0.585, blue: 0.185, alpha: 1))
    context.fillEllipse(in: dot.insetBy(dx: -diameter * 0.16, dy: -diameter * 0.16))
    context.setFillColor(CGColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1))
    context.fillEllipse(in: dot)
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

import AppKit
import Foundation

// Run from the repository root: swift scripts/generate-icons.swift
// Native rendering keeps asset regeneration independent of external tools.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Sources/CodexSidecar/Resources/Icons")
let iconset = root.appendingPathComponent("build/Sidecar.iconset")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

// Geometry matches docs/design/brand/sidecar-symbol.svg on a 256-unit grid.
func mark(ink: NSColor, companion: NSColor) {
    let outline = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 144, height: 176),
                               xRadius: 40, yRadius: 40)
    outline.append(NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 80, height: 112),
                                xRadius: 8, yRadius: 8))
    outline.appendRect(NSRect(x: 152, y: 96, width: 32, height: 64))
    outline.windingRule = .evenOdd
    ink.setFill()
    outline.fill()
    companion.setFill()
    NSBezierPath(roundedRect: NSRect(x: 160, y: 114, width: 56, height: 28),
                 xRadius: 14, yRadius: 14).fill()
}

func render(size: Int, menu: Bool, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size,
        pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Cannot create icon bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.cgContext.setShouldAntialias(true)
    if menu {
        context.cgContext.scaleBy(x: CGFloat(size) / 192, y: CGFloat(size) / 192)
        context.cgContext.translateBy(x: -32, y: -32)
        mark(ink: .black, companion: .black)
    } else {
        context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864),
                                xRadius: 192, yRadius: 192)
        color(245, 245, 243).setFill()
        tile.fill()
        color(220, 221, 217).setStroke()
        tile.lineWidth = 2
        tile.stroke()
        context.cgContext.translateBy(x: 102.4, y: 102.4)
        context.cgContext.scaleBy(x: 3.2, y: 3.2)
        mark(ink: color(32, 33, 35), companion: color(2, 133, 255))
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode icon PNG")
    }
    try data.write(to: url)
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try render(size: points * scale, menu: false,
                   to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
try render(size: 18, menu: true, to: resources.appendingPathComponent("MenuBarIcon.png"))
try render(size: 36, menu: true, to: resources.appendingPathComponent("MenuBarIcon@2x.png"))
try render(size: 512, menu: false, to: root.appendingPathComponent("docs/design/brand/dock-preview.png"))
let converter = Process()
converter.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
converter.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try converter.run()
converter.waitUntilExit()
guard converter.terminationStatus == 0 else { fatalError("Icon conversion failed") }
print("Generated Dock ICNS and 18/36 px menu-bar templates.")

// Renders the FlyBy airplane (Resources/icon/flyby-icon.svg, the brand source) as a black template image for Mail's
// Compose toolbar: Resources/FlyByTemplate.png (+@2x). AppKit tints any image named *Template from its alpha only.
// Usage: swift scripts/make-compose-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let svg = root.appendingPathComponent("Resources/icon/flyby-icon.svg")
guard let source = NSImage(contentsOf: svg) else { fatalError("cannot read \(svg.path)") }

func render(points: Int, scale: Int, to name: String) {
    let px = points * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let rect = NSRect(x: 0, y: 0, width: px, height: px)
    source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.black.setFill()
    rect.fill(using: .sourceIn)   // keep the plane's alpha, make every pixel black
    NSGraphicsContext.restoreGraphicsState()
    rep.size = NSSize(width: points, height: points)
    let out = root.appendingPathComponent("Resources/\(name).png")
    try! rep.representation(using: .png, properties: [:])!.write(to: out)
    print("wrote \(out.lastPathComponent) \(px)x\(px)")
}
render(points: 18, scale: 1, to: "FlyByTemplate")
render(points: 18, scale: 2, to: "FlyByTemplate@2x")

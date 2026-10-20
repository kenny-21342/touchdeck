// Run from the repository root: swift scripts/generate-icon.swift
import AppKit

let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
let lime = NSColor(srgbRed: 0.77, green: 0.94, blue: 0.35, alpha: 1)
let dark = NSColor(srgbRed: 0.055, green: 0.075, blue: 0.065, alpha: 1)
dark.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
let deck = NSBezierPath(roundedRect: NSRect(x: 162, y: 174, width: 700, height: 676),
                        xRadius: 100, yRadius: 100)
NSColor(srgbRed: 0.12, green: 0.16, blue: 0.13, alpha: 1).setFill()
deck.fill()
lime.setStroke()
deck.lineWidth = 20
deck.stroke()
// Three touch trails form a distinctive hand/trackpad mark.
for (x, y, height) in [(350.0, 460.0, 205.0), (490.0, 434.0, 292.0), (630.0, 478.0, 205.0)] {
    lime.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 76, height: height),
                 xRadius: 38, yRadius: 38).fill()
}
// A compact keyboard strip anchors the combination of touch and keys.
for row in 0..<2 {
    for column in 0..<6 {
        NSColor(srgbRed: 0.42, green: 0.50, blue: 0.39, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 272 + column * 84, y: 270 + row * 64,
                                        width: 60, height: 38),
                     xRadius: 10, yRadius: 10).fill()
    }
}
NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
let output = URL(fileURLWithPath: "Native/TouchDeck/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try bitmap.representation(using: .png, properties: [:])!.write(to: output)

// Renders the Sono app icon: cream squircle, chunky waveform in lavender.
// Run: swift makeicon.swift [out.png]
//
// Rhythm and colour are the chosen brand: 5 bars, symmetric, outer pair
// collapsing to dots — the shape that stays legible down to 16px.
import AppKit

let size = 1024.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// ---- cream tile
let inset = size * 0.098
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let radius = rect.width * 0.235
let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.035,
              color: color(0x6B6252, 0.28))
ctx.addPath(squircle)
ctx.setFillColor(color(0xFAF8F3))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let tile = CGGradient(colorsSpace: nil,
                      colors: [color(0xFEFDFA), color(0xEFEBE1)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(tile,
                       start: CGPoint(x: rect.minX, y: rect.maxY),
                       end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
ctx.restoreGState()

// A hairline keeps the cream tile from dissolving into white backgrounds.
ctx.addPath(squircle)
ctx.setStrokeColor(color(0xE0DACC))
ctx.setLineWidth(size * 0.006)
ctx.strokePath()

// ---- chunky waveform, symmetric
let heights: [Double] = [0.09, 0.19, 0.32, 0.19, 0.09]
let barWidth = rect.width * 0.082
let gap = rect.width * 0.048
let maxBar = rect.width
let totalWidth = Double(heights.count) * barWidth + Double(heights.count - 1) * gap
var x = size / 2 - totalWidth / 2

for h in heights {
    let barHeight = max(barWidth, maxBar * h)
    let bar = CGRect(x: x, y: size / 2 - barHeight / 2, width: barWidth, height: barHeight)
    let path = CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2,
                      transform: nil)
    ctx.addPath(path)
    // Brand-fixed black; never themed.
    ctx.setFillColor(color(0x1C1917))
    ctx.fillPath()
    x += barWidth + gap
}

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")

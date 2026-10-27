// Draws the app icon, and with a second argument the Mac sizes:
// swift tools/make-icon.swift cfind/Assets.xcassets/AppIcon.appiconset/icon-1024.png cfind/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
// Opaque: the App Store icon may not have alpha.
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!


/// The design, drawn in a 1024 x 1024 space: a magnifier with a terminal prompt
/// in the lens, for finding things in agent sessions.
func drawIcon(_ ctx: CGContext) {
    func rgb(_ hex: Int, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: a)
    }
    func gradient(_ colors: [CGColor]) -> CGGradient {
        CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    }

    // Graphite, lighter at the top, with a soft blue glow behind the lens.
    ctx.drawLinearGradient(gradient([rgb(0x30333B), rgb(0x0C0D10)]),
                           start: CGPoint(x: 0, y: size), end: .zero, options: [])
    let lens = CGPoint(x: 452, y: 578), radius = 262.0
    ctx.drawRadialGradient(gradient([rgb(0x0A84FF, 0.35), rgb(0x0A84FF, 0)]),
                           startCenter: lens, startRadius: 0, endCenter: lens, endRadius: 470, options: [])

    // The handle, then the ring over it, in brushed silver.
    let dir = CGPoint(x: cos(-.pi / 4), y: sin(-.pi / 4))
    let handle = CGMutablePath()
    handle.move(to: CGPoint(x: lens.x + dir.x * (radius + 10), y: lens.y + dir.y * (radius + 10)))
    handle.addLine(to: CGPoint(x: lens.x + dir.x * (radius + 250), y: lens.y + dir.y * (radius + 250)))
    let silver = gradient([rgb(0xFAFBFC), rgb(0xB9BEC7)])
    func fillSilver(_ path: CGPath) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(silver, start: CGPoint(x: 0, y: size), end: .zero, options: [])
        ctx.restoreGState()
    }
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: rgb(0x000000, 0.55))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    fillSilver(handle.copy(strokingWithWidth: 104, lineCap: .round, lineJoin: .round, miterLimit: 10))
    let ring = CGPath(ellipseIn: CGRect(x: lens.x - radius, y: lens.y - radius, width: radius * 2, height: radius * 2),
                      transform: nil)
    fillSilver(ring.copy(strokingWithWidth: 58, lineCap: .round, lineJoin: .round, miterLimit: 10))
    ctx.endTransparencyLayer()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Dark glass inside the ring.
    let glass = radius - 29
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: lens.x - glass, y: lens.y - glass, width: glass * 2, height: glass * 2))
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0x1C1F26), rgb(0x0B0C0F)]),
                           start: CGPoint(x: 0, y: lens.y + glass), end: CGPoint(x: 0, y: lens.y - glass), options: [])

    // The prompt: a chevron and a cursor, in Apple blue to cyan.
    let prompt = CGMutablePath()
    let chevron = CGMutablePath()
    chevron.move(to: CGPoint(x: lens.x - 120, y: lens.y + 82))
    chevron.addLine(to: CGPoint(x: lens.x - 30, y: lens.y))
    chevron.addLine(to: CGPoint(x: lens.x - 120, y: lens.y - 82))
    prompt.addPath(chevron.copy(strokingWithWidth: 48, lineCap: .round, lineJoin: .round, miterLimit: 10))
    prompt.addPath(CGPath(roundedRect: CGRect(x: lens.x + 10, y: lens.y - 106, width: 118, height: 44),
                          cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.setShadow(offset: .zero, blur: 28, color: rgb(0x40C8FF, 0.7))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(prompt)
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0x7FE0FF), rgb(0x0A84FF)]),
                           start: CGPoint(x: 0, y: lens.y + 90), end: CGPoint(x: 0, y: lens.y - 110), options: [])
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

func write(_ image: CGImage, _ path: String) {
    let out = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(out, image, nil)
    precondition(CGImageDestinationFinalize(out))
}

drawIcon(ctx)
write(ctx.makeImage()!, CommandLine.arguments[1])

// macOS does not mask icons: the shape is part of the image. Apple's grid puts an
// 824 x 824 body in the 1024 canvas, with room for a soft shadow.
if CommandLine.arguments.count > 2 {
    let dir = CommandLine.arguments[2]
    func canvas(_ px: Int) -> CGContext {
        let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.interpolationQuality = .high
        return c
    }
    let mac = canvas(1024)
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    mac.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: CGColor(gray: 0, alpha: 0.3))
    mac.setFillColor(CGColor(gray: 0, alpha: 1))
    mac.addPath(shape)
    mac.fillPath()
    mac.setShadow(offset: .zero, blur: 0, color: nil)
    mac.saveGState()
    mac.addPath(shape)
    mac.clip()
    mac.translateBy(x: body.minX, y: body.minY)
    mac.scaleBy(x: body.width / size, y: body.height / size)
    drawIcon(mac)
    mac.restoreGState()
    let master = mac.makeImage()!
    for point in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = point * scale
            let c = canvas(px)
            c.draw(master, in: CGRect(x: 0, y: 0, width: px, height: px))
            write(c.makeImage()!, "\(dir)/mac-\(point)@\(scale)x.png")
        }
    }
}

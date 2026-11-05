// Draws the glass-style app icon. Usage: make_icon out.png
import Cocoa
let n: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(deviceRed: r, green: g, blue: b, alpha: a) }
// Apple-like continuous corners: a superellipse
func squircle(_ r: NSRect, _ e: CGFloat = 5) -> NSBezierPath {
    let p = NSBezierPath(); let a = r.width / 2, b = r.height / 2
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi, c = cos(t), s = sin(t)
        let pt = NSPoint(x: r.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / e),
                         y: r.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / e))
        i == 0 ? p.move(to: pt) : p.line(to: pt)
    }
    p.close(); return p
}
let R = NSRect(x: 100, y: 100, width: 824, height: 824)
let body = squircle(R)
// drop shadow
NSGraphicsContext.saveGraphicsState()
let ds = NSShadow(); ds.shadowBlurRadius = 34; ds.shadowOffset = NSSize(width: 0, height: -16); ds.shadowColor = rgb(0, 0, 0.1, 0.45)
ds.set(); rgb(0.1, 0.2, 0.6).setFill(); body.fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState(); body.addClip()
// base: one flat colour
rgb(0.08, 0.38, 0.96).setFill(); R.fill()
// glass disc behind the glyph
let disc = NSBezierPath(ovalIn: NSRect(x: 212, y: 212, width: 600, height: 600))
NSGraphicsContext.saveGraphicsState()
let s2 = NSShadow(); s2.shadowBlurRadius = 46; s2.shadowOffset = NSSize(width: 0, height: -22); s2.shadowColor = rgb(0, 0.05, 0.35, 0.40)
s2.set(); rgb(1, 1, 1, 0.10).setFill(); disc.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: rgb(1, 1, 1, 0.36), ending: rgb(1, 1, 1, 0.05))!.draw(in: disc, angle: -90)
disc.lineWidth = 5
NSGraphicsContext.saveGraphicsState(); disc.addClip()
NSGradient(starting: rgb(1, 1, 1, 0.25), ending: rgb(1, 1, 1, 0))!.draw(in: NSRect(x: 212, y: 512, width: 600, height: 300), angle: -90)
NSGraphicsContext.restoreGraphicsState()
rgb(1, 1, 1, 0.55).setStroke(); disc.stroke()
// waveform of glass capsules, descending to the right = "to an older version"
let hs: [CGFloat] = [120, 230, 350, 280, 200, 130, 80]
let w: CGFloat = 44, gap: CGFloat = 22
let total = CGFloat(hs.count) * w + CGFloat(hs.count - 1) * gap
for (i, h) in hs.enumerated() {
    let x = (n - total) / 2 + CGFloat(i) * (w + gap)
    let bar = NSBezierPath(roundedRect: NSRect(x: x, y: 512 - h / 2, width: w, height: h), xRadius: w / 2, yRadius: w / 2)
    NSGraphicsContext.saveGraphicsState()
    let bs = NSShadow(); bs.shadowBlurRadius = 20; bs.shadowOffset = NSSize(width: 0, height: -10); bs.shadowColor = rgb(0, 0.08, 0.4, 0.5)
    bs.set(); NSColor.white.setFill(); bar.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: rgb(1, 1, 1, 1), ending: rgb(0.80, 0.90, 1, 1))!.draw(in: bar, angle: -90)
}
NSGraphicsContext.restoreGraphicsState()
// glass rim: bright at the top, faint at the bottom
let rim = squircle(R.insetBy(dx: 5, dy: 5)); rim.lineWidth = 9
NSGraphicsContext.saveGraphicsState()
rgb(1, 1, 1, 0.5).setStroke(); rim.stroke()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

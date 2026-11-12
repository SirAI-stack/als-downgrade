// Draws ProjectFolder.png and AlsDocument.png from scratch (glass style). Usage: make_icons outdir
import Cocoa
let out = CommandLine.arguments[1]
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(deviceRed: r, green: g, blue: b, alpha: a) }
func hex(_ h: UInt32, _ a: CGFloat = 1) -> NSColor { rgb(CGFloat(h >> 16 & 255) / 255, CGFloat(h >> 8 & 255) / 255, CGFloat(h & 255) / 255, a) }
let clipColors: [UInt32] = [0x12C9B0, 0xFF2BD6, 0xFF8FA3, 0x8A5CF6, 0x2BFFA3, 0xC9B3F2, 0xFFC93D]
func canvas(_ draw: () -> Void, _ name: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep); draw(); NSGraphicsContext.current = nil
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out + "/" + name))
}
func shadow(_ blur: CGFloat, _ dy: CGFloat, _ a: CGFloat, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow(); s.shadowBlurRadius = blur; s.shadowOffset = NSSize(width: 0, height: dy); s.shadowColor = rgb(0, 0.02, 0.12, a)
    s.set(); body(); NSGraphicsContext.restoreGraphicsState()
}
func clip(_ p: NSBezierPath, _ body: () -> Void) { NSGraphicsContext.saveGraphicsState(); p.addClip(); body(); NSGraphicsContext.restoreGraphicsState() }
// glass waveform, centred at (cx, cy)
func waveform(_ cx: CGFloat, _ cy: CGFloat, _ scale: CGFloat) {
    let hs: [CGFloat] = [120, 230, 350, 280, 200, 130, 80]
    let w: CGFloat = 44 * scale, gap: CGFloat = 22 * scale
    let total = CGFloat(hs.count) * w + CGFloat(hs.count - 1) * gap
    for (i, h0) in hs.enumerated() {
        let h = h0 * scale, x = cx - total / 2 + CGFloat(i) * (w + gap)
        let bar = NSBezierPath(roundedRect: NSRect(x: x, y: cy - h / 2, width: w, height: h), xRadius: w / 2, yRadius: w / 2)
        shadow(18 * scale, -9 * scale, 0.45) { NSColor.white.setFill(); bar.fill() }
        NSGradient(starting: .white, ending: rgb(0.80, 0.90, 1))!.draw(in: bar, angle: -90)
    }
}
// glass disc
func disc(_ r: NSRect) {
    let d = NSBezierPath(ovalIn: r)
    shadow(40, -20, 0.35) { rgb(1, 1, 1, 0.12).setFill(); d.fill() }
    NSGradient(starting: rgb(1, 1, 1, 0.38), ending: rgb(1, 1, 1, 0.06))!.draw(in: d, angle: -90)
    clip(d) { NSGradient(starting: rgb(1, 1, 1, 0.28), ending: rgb(1, 1, 1, 0))!.draw(in: NSRect(x: r.minX, y: r.midY, width: r.width, height: r.height / 2), angle: -90) }
    d.lineWidth = 5; rgb(1, 1, 1, 0.55).setStroke(); d.stroke()
}

// ---------- Project folder ----------
canvas({
    let back = NSBezierPath()
    back.move(to: NSPoint(x: 70, y: 180)); back.line(to: NSPoint(x: 70, y: 820))
    back.curve(to: NSPoint(x: 130, y: 880), controlPoint1: NSPoint(x: 70, y: 860), controlPoint2: NSPoint(x: 90, y: 880))
    back.line(to: NSPoint(x: 360, y: 880))
    back.curve(to: NSPoint(x: 430, y: 840), controlPoint1: NSPoint(x: 395, y: 880), controlPoint2: NSPoint(x: 410, y: 865))
    back.line(to: NSPoint(x: 460, y: 805))
    back.curve(to: NSPoint(x: 520, y: 780), controlPoint1: NSPoint(x: 475, y: 790), controlPoint2: NSPoint(x: 495, y: 780))
    back.line(to: NSPoint(x: 894, y: 780))
    back.curve(to: NSPoint(x: 954, y: 720), controlPoint1: NSPoint(x: 934, y: 780), controlPoint2: NSPoint(x: 954, y: 760))
    back.line(to: NSPoint(x: 954, y: 180)); back.close()
    shadow(36, -18, 0.5) { rgb(0.1, 0.1, 0.12).setFill(); back.fill() }
    NSGradient(starting: rgb(0.30, 0.31, 0.35), ending: rgb(0.13, 0.13, 0.16))!.draw(in: back, angle: -90)
    // coloured clips peeking out of the folder, like a Live arrangement
    for (i, c) in clipColors.prefix(5).enumerated() {
        let r = NSRect(x: 150 + CGFloat(i) * 148, y: 650 + CGFloat(i % 2) * 34, width: 130, height: 120)
        let p = NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14)
        shadow(10, -4, 0.35) { hex(c).setFill(); p.fill() }
        clip(p) { NSGradient(starting: rgb(1, 1, 1, 0.35), ending: rgb(1, 1, 1, 0))!.draw(in: r, angle: -90) }
    }
    // glass front
    let front = NSBezierPath(roundedRect: NSRect(x: 52, y: 120, width: 920, height: 590), xRadius: 70, yRadius: 70)
    shadow(40, -16, 0.45) { rgb(0.08, 0.36, 0.95).setFill(); front.fill() }
    rgb(0.08, 0.38, 0.96).setFill(); front.fill()
    clip(front) {
        NSGradient(starting: rgb(1, 1, 1, 0.40), ending: rgb(1, 1, 1, 0))!
            .draw(fromCenter: NSPoint(x: 330, y: 760), radius: 0, toCenter: NSPoint(x: 330, y: 760), radius: 620, options: [])
        NSGradient(starting: rgb(1, 1, 1, 0.22), ending: rgb(1, 1, 1, 0))!.draw(in: NSRect(x: 52, y: 560, width: 920, height: 150), angle: -90)
    }
    disc(NSRect(x: 352, y: 255, width: 320, height: 320))
    waveform(512, 415, 0.62)
    // clip strip along the bottom of the front
    for (i, c) in clipColors.enumerated() {
        let r = NSRect(x: 170 + CGFloat(i) * 102, y: 170, width: 84, height: 30)
        let p = NSBezierPath(roundedRect: r, xRadius: 15, yRadius: 15)
        hex(c, 0.95).setFill(); p.fill()
    }
    front.lineWidth = 8; rgb(1, 1, 1, 0.55).setStroke(); front.stroke()
}, "ProjectFolder.png")

// ---------- .als document ----------
canvas({
    let L: CGFloat = 170, Rr: CGFloat = 854, B: CGFloat = 60, T: CGFloat = 980, fold: CGFloat = 200
    let page = NSBezierPath()
    page.move(to: NSPoint(x: L + 40, y: B)); page.line(to: NSPoint(x: Rr - 40, y: B))
    page.curve(to: NSPoint(x: Rr, y: B + 40), controlPoint1: NSPoint(x: Rr - 18, y: B), controlPoint2: NSPoint(x: Rr, y: B + 18))
    page.line(to: NSPoint(x: Rr, y: T - fold)); page.line(to: NSPoint(x: Rr - fold, y: T))
    page.line(to: NSPoint(x: L + 40, y: T))
    page.curve(to: NSPoint(x: L, y: T - 40), controlPoint1: NSPoint(x: L + 18, y: T), controlPoint2: NSPoint(x: L, y: T - 18))
    page.line(to: NSPoint(x: L, y: B + 40))
    page.curve(to: NSPoint(x: L + 40, y: B), controlPoint1: NSPoint(x: L, y: B + 18), controlPoint2: NSPoint(x: L + 18, y: B))
    page.close()
    shadow(34, -14, 0.5) { rgb(0.1, 0.1, 0.12).setFill(); page.fill() }
    NSGradient(starting: rgb(0.20, 0.21, 0.25), ending: rgb(0.07, 0.07, 0.09))!.draw(in: page, angle: -90)
    clip(page) {
        NSGradient(starting: rgb(0.25, 0.45, 1, 0.35), ending: rgb(0.25, 0.45, 1, 0))!
            .draw(fromCenter: NSPoint(x: 512, y: 690), radius: 0, toCenter: NSPoint(x: 512, y: 690), radius: 420, options: [])
    }
    // folded corner
    let f = NSBezierPath(); f.move(to: NSPoint(x: Rr - fold, y: T)); f.line(to: NSPoint(x: Rr - fold, y: T - fold + 26))
    f.curve(to: NSPoint(x: Rr - fold + 26, y: T - fold), controlPoint1: NSPoint(x: Rr - fold, y: T - fold + 10), controlPoint2: NSPoint(x: Rr - fold + 10, y: T - fold))
    f.line(to: NSPoint(x: Rr, y: T - fold)); f.close()
    shadow(18, -6, 0.5) { rgb(0.4, 0.4, 0.45).setFill(); f.fill() }
    NSGradient(starting: rgb(0.52, 0.53, 0.58), ending: rgb(0.32, 0.33, 0.38))!.draw(in: f, angle: -45)
    // glass logo tile
    let tile = NSBezierPath(roundedRect: NSRect(x: 322, y: 530, width: 380, height: 380), xRadius: 92, yRadius: 92)
    shadow(30, -14, 0.5) { rgb(0.08, 0.38, 0.96).setFill(); tile.fill() }
    clip(tile) {
        NSGradient(starting: rgb(1, 1, 1, 0.35), ending: rgb(1, 1, 1, 0))!
            .draw(fromCenter: NSPoint(x: 420, y: 900), radius: 0, toCenter: NSPoint(x: 420, y: 900), radius: 360, options: [])
    }
    disc(NSRect(x: 372, y: 580, width: 280, height: 280))
    waveform(512, 720, 0.52)
    tile.lineWidth = 6; rgb(1, 1, 1, 0.55).setStroke(); tile.stroke()
    // Live arrangement clips
    let rows: [[Int]] = [[0, 0, -1, 1], [-1, 2, 2, 3], [4, -1, 3, 3], [-1, 5, 5, -1]]
    for (ri, row) in rows.enumerated() {
        for (ci, k) in row.enumerated() where k >= 0 {
            let r = NSRect(x: 250 + CGFloat(ci) * 134, y: 410 - CGFloat(ri) * 58, width: 122, height: 40)
            let p = NSBezierPath(roundedRect: r, xRadius: 9, yRadius: 9)
            hex(clipColors[k]).setFill(); p.fill()
            clip(p) { NSGradient(starting: rgb(1, 1, 1, 0.30), ending: rgb(1, 1, 1, 0))!.draw(in: r, angle: -90) }
        }
    }
    // ALS label
    let pill = NSBezierPath(roundedRect: NSRect(x: 412, y: 100, width: 200, height: 64), xRadius: 32, yRadius: 32)
    rgb(1, 1, 1, 0.14).setFill(); pill.fill()
    let txt = NSAttributedString(string: "ALS", attributes: [.font: NSFont.systemFont(ofSize: 44, weight: .heavy),
        .foregroundColor: rgb(1, 1, 1, 0.92), .kern: 6])
    txt.draw(at: NSPoint(x: 512 - txt.size().width / 2 + 3, y: 132 - txt.size().height / 2))
}, "AlsDocument.png")

// Draws Grid's app icon: a dark rounded tile with the screen shape of the layout icons in white.
// Usage: appicon <style> <rows> <pixels> <out.png>     style: dark | light; rows: 22 = 2 + 2, c = coding
import AppKit

let a = CommandLine.arguments
let dark = a[1] == "dark", coding = a[2] == "c", px = Int(a[3])!
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
// Everything is laid out on a 1024 canvas, top-left origin.
let t = NSAffineTransform(); t.translateX(by: 0, yBy: CGFloat(px)); t.scaleX(by: CGFloat(px) / 1024, yBy: -CGFloat(px) / 1024); t.concat()

let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowColor = NSColor(white: 0, alpha: 0.3); shadow.shadowBlurRadius = 24 * CGFloat(px) / 1024
shadow.shadowOffset = NSSize(width: 0, height: -10 * CGFloat(px) / 1024); shadow.set()
NSColor.black.setFill(); tile.fill()
NSGraphicsContext.restoreGraphicsState()
let top = dark ? NSColor(white: 0.27, alpha: 1) : NSColor(white: 1, alpha: 1), bottom = dark ? NSColor(white: 0.11, alpha: 1) : NSColor(white: 0.9, alpha: 1)
NSGradient(starting: top, ending: bottom)!.draw(in: tile, angle: 90)

// The screen shape: 30 : 19 like the menu icons, one rounded shape split by cuts.
let w: CGFloat = 540, h: CGFloat = 342, cut: CGFloat = 22, x0 = (1024 - w) / 2, y0 = (1024 - h) / 2
var tiles: [NSRect] = []
if coding {
    let split = (w * 0.6).rounded(), hh = (h - cut) / 2
    tiles = [NSRect(x: x0, y: y0, width: split, height: h), NSRect(x: x0 + split + cut, y: y0, width: w - split - cut, height: hh),
             NSRect(x: x0 + split + cut, y: y0 + hh + cut, width: w - split - cut, height: hh)]
} else {
    let cw = (w - cut) / 2, ch = (h - cut) / 2
    for r in 0..<2 { for c in 0..<2 { tiles.append(NSRect(x: x0 + CGFloat(c) * (cw + cut), y: y0 + CGFloat(r) * (ch + cut), width: cw, height: ch)) } }
}
NSBezierPath(roundedRect: NSRect(x: x0, y: y0, width: w, height: h), xRadius: 64, yRadius: 64).addClip()
(dark ? NSColor(white: 1, alpha: 0.96) : NSColor(white: 0.1, alpha: 1)).setFill()
for r in tiles { NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill() }
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[4]))

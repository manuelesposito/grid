// The picture that stands in for a window while it zooms. Only the text area scales; the title bar
// (the three buttons, the title) keeps its real size, as it does on the real window.
import AppKit

final class WindowPicture: NSView {
    init(_ image: CGImage, size: CGSize, titleBar: CGFloat) {
        super.init(frame: NSRect(origin: .zero, size: size))
        let scale = CGFloat(image.width) / size.width
        let barPx = Int(titleBar * scale)
        let radius = cornerRadius(image) / scale

        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.masksToBounds = true
        layer?.backgroundColor = pixel(image, x: Int(6 * scale), y: barPx + Int(6 * scale))

        // Text area: stretches with the picture.
        let body = NSView(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height - titleBar))
        body.wantsLayer = true
        body.layer?.contents = image.cropping(to: CGRect(x: 0, y: barPx, width: image.width, height: image.height - barPx))
        body.layer?.contentsGravity = .resize
        body.autoresizingMask = [.width, .height]
        addSubview(body)

        // Title bar: its left part stays put at real size, the rest is its own colour.
        let keep = min(image.width, Int((size.width - radius - 8) * scale))
        let bar = NSView(frame: NSRect(x: 0, y: size.height - titleBar, width: size.width, height: titleBar))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = pixel(image, x: image.width - Int((radius + 4) * scale), y: barPx / 2)
        bar.autoresizingMask = [.width, .minYMargin]
        let left = NSView(frame: NSRect(x: 0, y: 0, width: CGFloat(keep) / scale, height: titleBar))
        left.wantsLayer = true
        left.layer?.contents = image.cropping(to: CGRect(x: 0, y: 0, width: keep, height: barPx))
        left.layer?.contentsGravity = .resize
        bar.addSubview(left)
        addSubview(bar)
    }

    required init?(coder: NSCoder) { nil }
}

// One pixel's colour, in the picture's own colour space so it matches exactly.
func pixel(_ image: CGImage, x: Int, y: Int) -> CGColor {
    let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
    var data = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
    return CGColor(colorSpace: space, components: [CGFloat(data[0]) / 255, CGFloat(data[1]) / 255, CGFloat(data[2]) / 255, 1])!
}

// The window's corner radius in pixels: how far the see-through part reaches along the middle of the top-left corner.
func cornerRadius(_ image: CGImage) -> CGFloat {
    let n = min(80, image.width, image.height)
    var data = [UInt8](repeating: 0, count: n * n * 4)
    let ctx = CGContext(data: &data, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: n - image.height, width: image.width, height: image.height))
    // Along the diagonal from the corner, the first solid pixel sits at r(1 - 1/√2).
    for i in 0..<n where data[(i * n + i) * 4 + 3] > 128 {
        return CGFloat(i) / (1 - 1 / 2.0.squareRoot())
    }
    return 20
}

// A window as the screen shows it, shadow included, taken by ScreenCaptureKit at its real size.
struct Shot {
    let image: CGImage
    let box: CGRect     // the window inside the picture, in pixels from the top left
    let frame: CGRect   // the window on screen, top-left coordinates
    let scale: CGFloat
}

// The window with its shadow. The shadow keeps its size at the edges and stretches along them,
// the window itself is a WindowPicture. At its own size it is exactly the shot.
final class Card: NSView {
    init(_ shot: Shot, titleBar: CGFloat) {
        let s = shot.scale, img = shot.image, b = shot.box
        let size = CGSize(width: CGFloat(img.width) / s, height: CGFloat(img.height) / s)
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        let layer = self.layer!
        layer.contents = img
        layer.contentsScale = s
        layer.contentsGravity = .resize
        // Stretch only the middle of the window; its corners and the shadow around stay as they are.
        let inset: CGFloat = 40 * s
        let w = CGFloat(img.width), h = CGFloat(img.height)
        layer.contentsCenter = CGRect(x: (b.minX + inset) / w, y: (h - b.maxY + inset) / h,
                                      width: (b.width - 2 * inset) / w, height: (b.height - 2 * inset) / h)
        let inner = img.cropping(to: b)!
        let win = WindowPicture(inner, size: shot.frame.size, titleBar: titleBar)
        win.frame = NSRect(x: b.minX / s, y: (h - b.maxY) / s, width: shot.frame.width, height: shot.frame.height)
        win.autoresizingMask = [.width, .height]
        addSubview(win)
    }

    // Where the window sits inside, in points from each side.
    var margins: NSEdgeInsets {
        let win = subviews[0].frame
        return NSEdgeInsets(top: bounds.height - win.maxY, left: win.minX, bottom: win.minY, right: bounds.width - win.maxX)
    }

    required init?(coder: NSCoder) { nil }
}

// The solid window inside a picture with shadow: along the middle row and column.
func solidBox(_ image: CGImage) -> CGRect? {
    let w = image.width, h = image.height
    var d = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &d, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    func solid(_ x: Int, _ y: Int) -> Bool { d[(y * w + x) * 4 + 3] >= 250 }
    let row = h / 3
    guard let x0 = (0..<w).first(where: { solid($0, row) }), let x1 = (0..<w).last(where: { solid($0, row) }) else { return nil }
    let col = (x0 + x1) / 2
    guard let y0 = (0..<h).first(where: { solid(col, $0) }), let y1 = (0..<h).last(where: { solid(col, $0) }) else { return nil }
    return CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
}

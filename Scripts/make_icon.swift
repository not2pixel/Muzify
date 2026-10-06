// Icon Muzify: hình tròn xanh phẳng, 5 cột sóng âm màu đen ghép thành chữ "M".
// Dùng: swift Scripts/make_icon.swift Resources/AppIcon.icns [preview.png]
//       swift Scripts/make_icon.swift --ios Resources/iOS/Icons   (PNG vuông kín nền cho iPhone/iPad)
import AppKit

let iOS = CommandLine.arguments.dropFirst().first == "--ios"
let args = Array(CommandLine.arguments.dropFirst(iOS ? 2 : 1))
let out = args.first ?? "Resources/AppIcon.icns"
let previewPath = args.count > 1 ? args[1] : nil
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Muzify.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let u = s / 1024

    // iOS: nền vuông kín (hệ thống tự bo góc), hình tròn to hơn.
    if iOS {
        rgb(18, 18, 18).setFill()
        NSRect(x: 0, y: 0, width: s, height: s).fill()
    }
    // Nền: hình tròn xanh phẳng, có bóng nhẹ.
    let d: CGFloat = iOS ? 780 : 860
    let circle = NSBezierPath(ovalIn: NSRect(x: (1024 - d) / 2 * u, y: (1024 - d) / 2 * u, width: d * u, height: d * u))
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowColor = NSColor.black.withAlphaComponent(0.3)
    sh.shadowBlurRadius = 20 * u
    sh.shadowOffset = NSSize(width: 0, height: -8 * u)
    sh.set()
    rgb(30, 215, 96).setFill()
    circle.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Ký hiệu: 5 cột sóng âm màu đen, cao ở hai bên, thấp dần vào giữa (treo từ trên) → chữ "M".
    let heights: [CGFloat] = [400, 290, 190, 290, 400]
    let barW: CGFloat = 74, gap: CGFloat = 30
    let total = barW * 5 + gap * 4
    var x = (1024 - total) / 2
    let top: CGFloat = 512 + 400 / 2
    rgb(18, 18, 18).setFill()
    for h in heights {
        let bar = NSRect(x: x * u, y: (top - h) * u, width: barW * u, height: h * u)
        NSBezierPath(roundedRect: bar, xRadius: barW / 2 * u, yRadius: barW / 2 * u).fill()
        x += barW + gap
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

if iOS {
    try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    for (name, px) in [("AppIcon60x60@2x", 120), ("AppIcon60x60@3x", 180), ("AppIcon76x76@2x", 152),
                       ("AppIcon83.5x83.5@2x", 167), ("AppIcon1024", 1024)] {
        try! render(px).write(to: URL(fileURLWithPath: out).appendingPathComponent("\(name).png"))
    }
    print("✓ \(out)")
    exit(0)
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
if let previewPath { try! render(1024).write(to: URL(fileURLWithPath: previewPath)) }

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "✓ \(out)" : "iconutil lỗi")

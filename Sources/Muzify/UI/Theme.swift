import CoreImage
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Bảng màu (giao diện tối kiểu Spotify desktop)

enum MZ {
    static func hex(_ v: UInt32, _ a: Double = 1) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255, opacity: a)
    }
    /// Nền ngoài cùng (giữa các khung).
    static let base = hex(0x000000)
    /// Khung nội dung.
    static let panel = hex(0x121212)
    /// Thẻ, ô tìm kiếm, nút tròn.
    static let elevated = hex(0x1F1F1F)
    static let elevatedHover = hex(0x2A2A2A)
    static let card = hex(0x181818)
    static let text = Color.white
    static let subtext = hex(0xB3B3B3)
    static let divider = Color.white.opacity(0.1)
    /// Nền khi rê chuột / đang chọn.
    static let hover = Color.white.opacity(0.1)
    static let selected = Color.white.opacity(0.16)
    static let barTrack = hex(0x4D4D4D)
}

/// Màu thương hiệu Muzify — đổi ở đây là đổi toàn app.
enum Brand {
    static let accent = MZ.hex(0x1ED760)
    static let accentHover = MZ.hex(0x3BE477)
    /// Ảnh bìa "Bài hát đã thích".
    static let likedTop = MZ.hex(0x450AF5)
    static let likedBottom = MZ.hex(0xC4EFD9)
    /// Nền đầu trang "Bài hát đã thích".
    static let liked = MZ.hex(0x5038A0)

    static let quick = Animation.easeOut(duration: 0.15)
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)
}

// MARK: - Nút

/// Co nhẹ khi bấm.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Brand.quick, value: configuration.isPressed)
    }
}

/// Nút Play tròn màu nhấn: rê chuột phóng to 1.04 + sáng hơn, bấm co lại.
struct PlayButton: View {
    let isPlaying: Bool
    var size: CGFloat = 56
    var loading = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if loading {
                    Spinner(color: .black)
                } else {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: size * 0.4, weight: .bold))
                        .offset(x: isPlaying ? 0 : size * 0.03)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .foregroundStyle(.black)
            .frame(width: size, height: size)
            .background(hovering ? Brand.accentHover : Brand.accent, in: Circle())
            .shadow(color: .black.opacity(0.3), radius: 8, y: 8)
            .scaleEffect(hovering ? 1.04 : 1)
        }
        .buttonStyle(PressScaleStyle())
        .onHover { h in withAnimation(Brand.quick) { hovering = h } }
        .help(isPlaying ? L("Tạm dừng") : L("Phát"))
    }
}

/// Nút điều khiển nhỏ: xám → trắng khi rê chuột; đang bật thì màu nhấn + chấm nhỏ bên dưới.
struct IconButton: View {
    let symbol: String
    var active = false
    var size: CGFloat = 15
    var help = ""
    var dot = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(active ? (hovering ? Brand.accentHover : Brand.accent) : hovering ? MZ.text : MZ.subtext)
                .scaleEffect(hovering ? 1.04 : 1)
                .frame(width: 32, height: 32)
                .overlay(alignment: .bottom) {
                    if active && dot {
                        Circle().fill(Brand.accent).frame(width: 4, height: 4).offset(y: -1)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { h in withAnimation(Brand.quick) { hovering = h } }
        .animation(Brand.quick, value: active)
        .help(help)
    }
}

/// Nút tròn nền xám (Trang chủ, ＋, đóng): rê chuột thì sáng hơn và to nhẹ.
struct HoverCircle: View {
    let symbol: String
    var size: CGFloat = 40
    var filled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(hovering ? MZ.text : MZ.subtext)
                .frame(width: size, height: size)
                .background(filled ? (hovering ? MZ.elevatedHover : MZ.elevated) : (hovering ? MZ.hover : .clear), in: Circle())
                .scaleEffect(hovering ? 1.04 : 1)
        }
        .buttonStyle(PressScaleStyle())
        .onHover { h in withAnimation(Brand.quick) { hovering = h } }
    }
}

/// Viên thuốc lọc (Playlist, Nghệ sĩ…).
struct Chip: View {
    let title: String
    var selected = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? .black : MZ.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? MZ.text : hovering ? MZ.elevatedHover : MZ.elevated, in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
    }
}

/// Nút viền tròn (Theo dõi, Lưu…).
struct OutlineButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(MZ.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .overlay(Capsule().strokeBorder(hovering ? MZ.text : MZ.subtext.opacity(0.6), lineWidth: 1))
                .scaleEffect(hovering ? 1.04 : 1)
        }
        .buttonStyle(PressScaleStyle())
        .onHover { h in withAnimation(Brand.quick) { hovering = h } }
    }
}

// MARK: - Thanh tiến độ / âm lượng

/// Cao 4pt bo tròn, rãnh #4D4D4D, phần đã chạy trắng; rê chuột (hoặc kéo) thì phần đã chạy đổi màu nhấn
/// và hiện núm tròn trắng 12pt. Vùng bắt chuột cao hơn thanh để dễ trúng.
struct ScrubBar: View {
    let value: Double
    var onChanged: (Double) -> Void = { _ in }
    var onCommit: (Double) -> Void
    var fill: Color = .white
    @State private var hovering = false
    @State private var drag: Double?

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let v = min(max(drag ?? value, 0), 1)
            let on = hovering || drag != nil
            ZStack(alignment: .leading) {
                Capsule().fill(MZ.barTrack)
                Capsule()
                    .fill(on ? Brand.accent : fill)
                    .frame(width: max(w * v, v > 0 ? 4 : 0))
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                    .offset(x: min(max(w * v - 6, -6), w - 6))
                    .opacity(on ? 1 : 0)
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let p = min(max(g.location.x / w, 0), 1)
                        drag = p
                        onChanged(p)
                    }
                    .onEnded { g in
                        onCommit(min(max(g.location.x / w, 0), 1))
                        drag = nil
                    }
            )
        }
        .frame(height: 12)
        .onHover { hovering = $0 }
    }
}

/// Cột sóng âm nhảy theo nhạc (bài đang phát).
struct EqualizerBars: View {
    var animating = true
    var color: Color = Brand.accent

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animating)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let speed = [5.1, 7.3, 4.2, 6.4][i]
                    let h = animating ? 0.3 + 0.7 * abs(sin(t * speed + Double(i) * 1.3)) : 0.3
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 2.5, height: 14 * h)
                }
            }
            .frame(width: 16, height: 14, alignment: .bottom)
        }
    }
}

// MARK: - Ảnh bìa

/// Ảnh bìa vuông, không có thì hiện nốt nhạc.
struct ArtworkView: View {
    @ObservedObject private var remote = RemoteArt.shared
    let track: Track?
    var size: CGFloat = 48
    var radius: CGFloat = 4

    var body: some View {
        Group {
            if let img = MusicLibrary.shared.artwork(track) {
                Image(platformImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                MZ.elevated.overlay(Image(systemName: "music.note").font(.system(size: size * 0.36)).foregroundStyle(MZ.subtext))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Ảnh từ link, kèm biểu tượng thay thế.
struct RemoteImage: View {
    @ObservedObject private var remote = RemoteArt.shared
    let url: String?
    var placeholder = "music.note"

    var body: some View {
        if let img = remote.image(url) {
            Image(platformImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            GeometryReader { g in
                MZ.elevatedHover.overlay(Image(systemName: placeholder)
                    .font(.system(size: min(g.size.width, g.size.height) * 0.3)).foregroundStyle(MZ.subtext))
            }
        }
    }
}

/// Ảnh bìa "Bài hát đã thích".
struct LikedCover: View {
    var size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: size > 60 ? 6 : 4, style: .continuous)
            .fill(LinearGradient(colors: [Brand.likedTop, Brand.likedBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Image(systemName: "heart.fill").font(.system(size: size * 0.36)).foregroundStyle(.white))
            .frame(width: size, height: size)
    }
}

/// Ảnh bìa playlist: 4 ảnh ghép (đủ 4 bài) hoặc ảnh bài đầu.
struct PlaylistCover: View {
    @ObservedObject private var lib = MusicLibrary.shared
    let playlist: Playlist
    let size: CGFloat

    var body: some View {
        let tracks = lib.tracks(in: playlist)
        Group {
            if tracks.count >= 4 {
                let half = size / 2
                VStack(spacing: 0) {
                    HStack(spacing: 0) { ArtworkView(track: tracks[0], size: half, radius: 0); ArtworkView(track: tracks[1], size: half, radius: 0) }
                    HStack(spacing: 0) { ArtworkView(track: tracks[2], size: half, radius: 0); ArtworkView(track: tracks[3], size: half, radius: 0) }
                }
            } else if let first = tracks.first {
                ArtworkView(track: first, size: size, radius: 0)
            } else {
                MZ.elevatedHover.overlay(Image(systemName: "music.note.list").font(.system(size: size * 0.36)).foregroundStyle(MZ.subtext))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 60 ? 6 : 4, style: .continuous))
    }
}

/// Ảnh nghệ sĩ (tròn).
struct ArtistAvatar: View {
    let artist: Artist
    let size: CGFloat
    var body: some View {
        RemoteImage(url: artist.art, placeholder: "person.fill")
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}

// MARK: - Màu chủ đạo của ảnh bìa

enum ArtColor {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])
    @MainActor private static var cache: [String: Color] = [:]

    /// Màu trung bình của ảnh, chỉnh cho đủ đậm để chữ trắng đọc được (giống nền đầu trang Spotify).
    @MainActor static func color(for track: Track?) -> Color? {
        guard let t = track, let key = t.artwork ?? t.artworkURL else { return nil }
        if let c = cache[key] { return c }
        guard let img = MusicLibrary.shared.artwork(t) else { return nil }
        return compute(key, img)
    }

    @MainActor static func color(url: String?) -> Color? {
        guard let url else { return nil }
        if let c = cache[url] { return c }
        guard let img = RemoteArt.shared.image(url) else { return nil }
        return compute(url, img)
    }

    @MainActor private static func compute(_ key: String, _ img: PlatformImage) -> Color? {
        guard let cg = img.cgImageValue else { return nil }
        let ci = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent)]),
              let out = filter.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        context.render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        // RGB → HSB (tự tính để chạy được cả Mac lẫn iOS).
        let r = Double(px[0]) / 255, g = Double(px[1]) / 255, bl = Double(px[2]) / 255
        let mx = max(r, g, bl), mn = min(r, g, bl), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - bl) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (bl - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        let s = mx == 0 ? 0 : d / mx, b = mx
        let color = Color(hue: Double(h), saturation: Double(s < 0.12 ? s : min(max(s, 0.45), 0.8)),
                          brightness: Double(min(max(b, 0.38), 0.55)))
        cache[key] = color
        return color
    }
}

// MARK: - Ô nhập không đổi nền khi gõ (Mac)

extension Notification.Name {
    static let focusSearch = Notification.Name("muzify.focusSearch")
}

#if os(macOS)
/// TextField gốc của AppKit, không vẽ nền và không có viền focus.
/// (TextField .plain của SwiftUI hiện nền đen của field editor khi đang gõ.)
struct PlainTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var fontSize: CGFloat = 13
    /// Nhận thông báo này thì tự focus vào ô.
    var focusOn: Notification.Name?
    var onBegin: () -> Void = {}
    var onSubmit: () -> Void = {}
    var onEscape: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField()
        f.isBordered = false
        f.isBezeled = false
        f.drawsBackground = false
        f.backgroundColor = .clear
        f.focusRingType = .none
        f.textColor = .white
        f.font = .systemFont(ofSize: fontSize)
        f.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: NSColor(white: 0.62, alpha: 1), .font: NSFont.systemFont(ofSize: fontSize),
        ])
        f.lineBreakMode = .byTruncatingTail
        f.cell?.usesSingleLineMode = true
        f.cell?.isScrollable = true
        f.delegate = context.coordinator
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        context.coordinator.field = f
        if let name = focusOn {
            context.coordinator.observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak f] _ in
                MainActor.assumeIsolated {
                    guard let f else { return }
                    f.window?.makeFirstResponder(f)
                    f.currentEditor()?.selectAll(nil)
                }
            }
        }
        return f
    }

    func updateNSView(_ f: NSTextField, context: Context) {
        context.coordinator.parent = self
        if f.stringValue != text { f.stringValue = text }
    }

    static func dismantleNSView(_ f: NSTextField, coordinator: Coordinator) {
        if let o = coordinator.observer { NotificationCenter.default.removeObserver(o) }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PlainTextField
        weak var field: NSTextField?
        var observer: NSObjectProtocol?
        init(_ p: PlainTextField) { parent = p }

        func controlTextDidBeginEditing(_ n: Notification) {
            if let editor = n.userInfo?["NSFieldEditor"] as? NSTextView {
                editor.drawsBackground = false
                editor.backgroundColor = .clear
                editor.insertionPointColor = .white
            }
            parent.onBegin()
        }

        func controlTextDidChange(_ n: Notification) {
            if let f = n.object as? NSTextField { parent.text = f.stringValue }
            parent.onBegin()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                parent.text = control.stringValue
                parent.onSubmit()
                return true
            }
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                control.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }
    }
}

// MARK: - Kéo cửa sổ (thanh trên cùng khi ẩn thanh tiêu đề)

struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with e: NSEvent) {
            if e.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: e) }
        }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ v: NSView, context: Context) {}
}
#endif

// MARK: - Vị trí cuộn (hiện thanh tiêu đề dính khi cuộn qua đầu trang)

struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Đặt ở đầu nội dung ScrollView (có `.coordinateSpace(name: "page")`).
struct ScrollOffsetReader: View {
    var body: some View {
        GeometryReader { g in
            Color.clear.preference(key: ScrollOffsetKey.self, value: g.frame(in: .named("page")).minY)
        }
        .frame(height: 0)
    }
}

/// Đo bề rộng một view.
struct WidthReader: View {
    @Binding var width: CGFloat
    var body: some View {
        GeometryReader { g in
            Color.clear
                .onAppear { width = g.size.width }
                .onChange(of: g.size.width) { _, w in width = w }
        }
    }
}

/// Vòng xoay chờ tự vẽ (ProgressView của macOS không đổi màu được nên bị chìm trên nút trắng / xanh).
struct Spinner: View {
    var color: Color = .white
    var size: CGFloat = 14

    var body: some View {
        TimelineView(.animation) { ctx in
            let angle = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360
            Circle()
                .trim(from: 0.15, to: 1)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(angle))
        }
    }
}

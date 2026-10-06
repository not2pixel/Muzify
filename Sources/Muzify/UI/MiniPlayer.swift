import AVKit
import SwiftUI

// MARK: - Nút chọn loa AirPlay

struct AirPlayButton: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.player = MusicPlayer.shared.avPlayer
        v.isRoutePickerButtonBordered = false
        v.setRoutePickerButtonColor(NSColor(white: 0.7, alpha: 1), for: .normal)
        v.setRoutePickerButtonColor(.white, for: .normalHighlighted)
        v.setRoutePickerButtonColor(NSColor(srgbRed: 0x1E / 255, green: 0xD7 / 255, blue: 0x60 / 255, alpha: 1), for: .active)
        v.toolTip = L("Kết nối với thiết bị")
        return v
    }
    func updateNSView(_ v: AVRoutePickerView, context: Context) {}
}

// MARK: - Mini player (thanh menu + cửa sổ nổi)

struct MiniPlayerView: View {
    enum Style { case menuBar, window }
    let style: Style
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var remote = RemoteArt.shared
    @Environment(\.openWindow) private var openWindow
    @State private var hovering = false
    @State private var scrub: Double?

    var body: some View {
        let t = player.current
        VStack(spacing: 0) {
            if style == .window {
                ZStack(alignment: .bottom) {
                    ArtworkView(track: t, size: 300, radius: 0)
                    if hovering {
                        LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                        controls(big: true).padding(.bottom, 14)
                    }
                }
                .frame(width: 300, height: 300)
                .overlay(alignment: .topTrailing) {
                    if hovering {
                        IconButton(symbol: "arrow.up.forward.app", size: 13, help: L("Mở cửa sổ Muzify"), action: openMain)
                            .padding(6)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    if style == .menuBar {
                        ArtworkView(track: t, size: 56)
                            .onTapGesture(perform: openMain)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t?.title ?? L("Chưa phát bài nào"))
                            .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(t?.artist ?? "Muzify").font(.system(size: 12)).foregroundStyle(MZ.subtext).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let t { LikeButton(track: t) }
                }
                progress
                if style == .menuBar {
                    HStack {
                        controls(big: false)
                        Spacer()
                        IconButton(symbol: "pip.enter", size: 14, help: L("Cửa sổ nổi")) {
                            openWindow(id: "mini")
                            NSApp.activate(ignoringOtherApps: true)
                        }
                        IconButton(symbol: "macwindow", size: 14, help: L("Mở cửa sổ Muzify"), action: openMain)
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 300)
        .background(MZ.elevated)
        .environment(\.colorScheme, .dark)
        .onHover { h in withAnimation(Brand.quick) { hovering = h } }
        .background(style == .window ? FloatingWindow() : nil)
    }

    private var progress: some View {
        HStack(spacing: 6) {
            Text(formatTime(scrub ?? player.time)).frame(width: 34, alignment: .leading)
            ScrubBar(value: player.duration > 0 ? (scrub ?? player.time) / player.duration : 0,
                     onChanged: { scrub = $0 * player.duration },
                     onCommit: { player.seek(to: $0 * player.duration); scrub = nil })
            Text(formatTime(player.duration)).frame(width: 34, alignment: .trailing)
        }
        .font(.system(size: 10))
        .monospacedDigit()
        .foregroundStyle(MZ.subtext)
    }

    private func controls(big: Bool) -> some View {
        HStack(spacing: big ? 18 : 8) {
            IconButton(symbol: "shuffle", active: player.shuffle, size: 13, help: L("Phát ngẫu nhiên")) { player.shuffle.toggle() }
            IconButton(symbol: "backward.end.fill", size: 15, help: L("Bài trước")) { player.previous() }
            Button(action: player.toggle) {
                Group {
                    if player.isResolving || (player.isBuffering && player.isPlaying) { Spinner(color: .black) }
                    else { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 14, weight: .bold)) }
                }
                .foregroundStyle(.black)
                .frame(width: 32, height: 32)
                .background(.white, in: Circle())
            }
            .buttonStyle(PressScaleStyle())
            IconButton(symbol: "forward.end.fill", size: 15, help: L("Bài tiếp")) { player.next() }
            IconButton(symbol: player.repeatMode == .one ? "repeat.1" : "repeat", active: player.repeatMode != .off,
                       size: 13, help: L("Lặp lại")) { player.cycleRepeat() }
        }
        .disabled(player.current == nil)
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Biểu tượng trên thanh menu: sóng âm khi đang phát.
struct MenuBarLabel: View {
    @ObservedObject private var player = MusicPlayer.shared
    var body: some View {
        Image(systemName: player.isPlaying ? "waveform" : "music.note")
    }
}

/// Cửa sổ nổi luôn ở trên các app khác, kể cả khi app khác đang toàn màn hình.
private struct FloatingWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.level = .floating
            w.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
            w.isMovableByWindowBackground = true
            w.titlebarAppearsTransparent = true
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true
            w.standardWindowButton(.zoomButton)?.isHidden = true
        }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}

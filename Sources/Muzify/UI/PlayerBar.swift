import SwiftUI

// MARK: - Thanh phát dưới cùng

struct PlayerBar: View {
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var ui = UIState.shared
    @State private var lastVolume: Float = 0.8
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let t = player.current
        HStack(spacing: 16) {
            // Trái: bài đang phát
            HStack(spacing: 14) {
                if let t {
                    ArtworkView(track: t, size: 56)
                        .onTapGesture { ui.toggle(.nowPlaying) }
                        .help(L("Khung đang phát"))
                    VStack(alignment: .leading, spacing: 3) {
                        TitleLink(title: t.title) {
                            if let key = player.contextKey { open(key) }
                        }
                        ArtistLink(name: t.artist, size: 12)
                    }
                    LikeButton(track: t)
                }
            }
            .frame(minWidth: 180, maxWidth: 320, alignment: .leading)

            Spacer(minLength: 0)

            // Giữa: điều khiển + tiến độ
            Controls()
                .frame(maxWidth: 680)

            Spacer(minLength: 0)

            // Phải
            HStack(spacing: 2) {
                IconButton(symbol: "play.rectangle", active: ui.rightPanel == .nowPlaying, size: 15, help: L("Khung đang phát")) {
                    ui.toggle(.nowPlaying)
                }
                IconButton(symbol: "music.mic", active: ui.showLyrics, size: 15, help: L("Lời bài hát")) { ui.toggleLyrics() }
                    .disabled(t == nil)
                IconButton(symbol: "list.bullet", active: ui.rightPanel == .queue, size: 15, help: L("Danh sách chờ")) {
                    ui.toggle(.queue)
                }
                AirPlayButton().frame(width: 28, height: 28)
                IconButton(symbol: volumeSymbol, size: 15, help: player.volume == 0 ? L("Bật tiếng") : L("Tắt tiếng"), action: toggleMute)
                ScrubBar(value: Double(player.volume),
                         onChanged: { player.volume = Float($0) },
                         onCommit: { player.volume = Float($0) })
                    .frame(width: 93)
                IconButton(symbol: "pip.enter", size: 14, help: L("Cửa sổ nổi")) { openWindow(id: "mini") }
                    .disabled(t == nil)
                IconButton(symbol: "arrow.up.left.and.arrow.down.right", size: 14, help: L("Toàn màn hình")) {
                    withAnimation(.easeInOut(duration: 0.3)) { ui.fullScreen = true }
                }
                .disabled(t == nil)
            }
            .frame(minWidth: 180, maxWidth: 320, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 72)
        .background(MZ.base)
    }

    private func open(_ key: String) {
        if key == "liked" { Router.shared.go(.liked) }
        else if key.hasPrefix("playlist:"), let id = UUID(uuidString: String(key.dropFirst(9))) { Router.shared.go(.playlist(id)) }
    }

    private var volumeSymbol: String {
        switch player.volume {
        case 0: "speaker.slash"
        case ..<0.34: "speaker.wave.1"
        case ..<0.67: "speaker.wave.2"
        default: "speaker.wave.3"
        }
    }

    private func toggleMute() {
        if player.volume > 0 { lastVolume = player.volume; player.volume = 0 } else { player.volume = max(lastVolume, 0.2) }
    }
}

private struct TitleLink: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Text(title)
            .font(.system(size: 14))
            .foregroundStyle(MZ.text)
            .underline(hovering)
            .lineLimit(1)
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }
}

/// Trộn · Trước · Phát · Tiếp · Lặp + thanh thời gian (dùng chung cho thanh phát và toàn màn hình).
struct Controls: View {
    @ObservedObject private var player = MusicPlayer.shared
    var big = false
    @State private var scrub: Double?

    var body: some View {
        VStack(spacing: big ? 12 : 4) {
            HStack(spacing: big ? 28 : 16) {
                IconButton(symbol: "shuffle", active: player.shuffle, size: big ? 20 : 15, help: L("Phát ngẫu nhiên")) { player.shuffle.toggle() }
                IconButton(symbol: "backward.end.fill", size: big ? 22 : 16, help: L("Bài trước")) { player.previous() }
                CenterPlayButton(size: big ? 56 : 34)
                IconButton(symbol: "forward.end.fill", size: big ? 22 : 16, help: L("Bài tiếp")) { player.next() }
                IconButton(symbol: player.repeatMode == .one ? "repeat.1" : "repeat",
                           active: player.repeatMode != .off, size: big ? 20 : 15,
                           help: player.repeatMode == .off ? L("Bật lặp lại") : player.repeatMode == .all ? L("Lặp lại một bài") : L("Tắt lặp lại")) {
                    player.cycleRepeat()
                }
            }
            HStack(spacing: 8) {
                Text(formatTime(scrub ?? player.time)).frame(width: 44, alignment: .trailing)
                ScrubBar(value: player.duration > 0 ? (scrub ?? player.time) / player.duration : 0,
                         onChanged: { scrub = $0 * player.duration },
                         onCommit: { player.seek(to: $0 * player.duration); scrub = nil })
                Text(formatTime(player.duration)).frame(width: 44, alignment: .leading)
            }
            .font(.system(size: big ? 13 : 11))
            .monospacedDigit()
            .foregroundStyle(MZ.subtext)
        }
        .disabled(player.current == nil)
    }
}

/// Nút phát tròn trắng: rê chuột phóng to; đang lấy link thì hiện vòng xoay.
struct CenterPlayButton: View {
    @ObservedObject private var player = MusicPlayer.shared
    var size: CGFloat = 34
    @State private var hovering = false

    var body: some View {
        Button(action: player.toggle) {
            Group {
                if player.isResolving || (player.isBuffering && player.isPlaying) {
                    Spinner(color: .black)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: size * 0.44, weight: .bold))
                        .foregroundStyle(.black)
                        .offset(x: player.isPlaying ? 0 : 1)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: size, height: size)
            .background(.white, in: Circle())
            .scaleEffect(hovering ? 1.06 : 1)
        }
        .buttonStyle(PressScaleStyle())
        .onHover { h in withAnimation(Brand.quick) { hovering = h } }
        .help(player.isPlaying ? L("Tạm dừng (Space)") : L("Phát (Space)"))
    }
}

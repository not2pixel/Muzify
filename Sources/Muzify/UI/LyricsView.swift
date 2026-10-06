import SwiftUI

// MARK: - Lời bài hát (toàn khung giữa, nền màu theo ảnh bìa)

struct LyricsView: View {
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var store = LyricsStore.shared
    @ObservedObject private var remote = RemoteArt.shared
    @State private var searching = false
    @State private var query = ""
    @State private var hoverLine: Int?

    /// Màu chữ cố định trên nền màu (giống Spotify).
    private let sung = Color.white
    private let upcoming = Color.black.opacity(0.82)

    var body: some View {
        let track = player.current
        let bg = ArtColor.color(for: track) ?? MZ.hex(0x535353)

        ZStack(alignment: .top) {
            bg.ignoresSafeArea()
            content
            topBar(track)
        }
        .animation(.easeInOut(duration: 0.6), value: track?.id)
        .task(id: track?.id) {
            searching = false
            if let t = track, store.trackID != t.id || store.state == .idle { store.load(t) }
        }
    }

    private func topBar(_ track: Track?) -> some View {
        HStack(spacing: 10) {
            Spacer()
            if searching {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.8))
                    PlainTextField(placeholder: L("Tên bài, ca sĩ…"), text: $query, onSubmit: search, onEscape: { searching = false })
                        .frame(width: 220)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.black.opacity(0.25), in: Capsule())
                pill(L("Tìm"), action: search)
                pill(L("Huỷ")) { searching = false }
            } else {
                pill(L("Sai lời? Tìm lại"), symbol: "magnifyingglass") {
                    if let t = track {
                        let terms = LyricsStore.searchTerms(for: t)
                        query = "\(terms.artist) \(terms.title)".trimmed
                    }
                    withAnimation(Brand.quick) { searching = true }
                }
            }
            Button { UIState.shared.toggleLyrics() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.black.opacity(0.25), in: Circle())
            }
            .buttonStyle(PressScaleStyle())
            .help(L("Đóng lời bài hát"))
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private func pill(_ title: String, symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.black.opacity(0.25), in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
    }

    private func search() {
        guard let t = player.current, !query.trimmed.isEmpty else { return }
        store.load(t, query: query.trimmed)
        searching = false
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle, .loading:
            ProgressView().controlSize(.large).tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .instrumental:
            message(L("Bài này là nhạc không lời"), detail: nil)
        case .notFound:
            message(L("Rất tiếc, chưa có lời cho bài hát này"), detail: L("Thử “Sai lời? Tìm lại” với tên chính xác hơn."))
        case .failed(let e):
            message(L("Không tải được lời bài hát"), detail: e)
        case .found(let lines, let synced, let match):
            lyrics(lines, synced: synced, match: match)
        }
    }

    private func message(_ title: String, detail: String?) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 28, weight: .bold)).foregroundStyle(sung)
            if let detail { Text(detail).font(.system(size: 14, weight: .medium)).foregroundStyle(upcoming) }
        }
        .multilineTextAlignment(.center)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lyrics(_ lines: [LyricLine], synced: Bool, match: String) -> some View {
        let current = store.currentLine(at: player.time)

        return GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if !synced {
                            Text(L("Lời bài hát này chưa được đồng bộ với bài hát."))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(sung.opacity(0.85))
                                .padding(.bottom, 24)
                        }
                        ForEach(lines) { line in
                            lineView(line, current: current, synced: synced).id(line.id)
                        }
                        Text(match)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(upcoming.opacity(0.7))
                            .padding(.top, 48)
                    }
                    .padding(.horizontal, 64)
                    // Chừa khoảng trống để dòng đầu/cuối cũng cuộn được vào vị trí đọc.
                    .padding(.top, geo.size.height * 0.3)
                    .padding(.bottom, geo.size.height * 0.5)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onAppear {
                    if let c = current { proxy.scrollTo(c, anchor: UnitPoint(x: 0.5, y: 0.33)) }
                }
                .onChange(of: current) {
                    guard let c = current else { return }
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) {
                        proxy.scrollTo(c, anchor: UnitPoint(x: 0.5, y: 0.33))
                    }
                }
            }
        }
    }

    private func lineView(_ line: LyricLine, current: Int?, synced: Bool) -> some View {
        let isCurrent = line.id == current
        let isSung = synced && current.map { line.id < $0 } ?? false
        let hovered = hoverLine == line.id && synced
        let color: Color = isCurrent ? sung
            : hovered ? sung.opacity(0.9)
            : isSung ? sung.opacity(0.62)
            : synced ? upcoming : sung

        return Text(line.text.isEmpty ? "♪" : line.text)
            .font(.system(size: 30, weight: .bold))
            .tracking(-0.4)
            .lineSpacing(4)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .onHover { h in
                withAnimation(Brand.quick) { hoverLine = h ? line.id : (hoverLine == line.id ? nil : hoverLine) }
            }
            .onTapGesture {
                if let t = store.seekTime(for: line) { player.seek(to: t) }
            }
            .animation(.easeInOut(duration: 0.3), value: isCurrent)
            .animation(.easeInOut(duration: 0.3), value: isSung)
    }
}

// MARK: - Toàn màn hình

struct FullScreenPlayer: View {
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var remote = RemoteArt.shared
    @ObservedObject private var lyrics = LyricsStore.shared
    @State private var enteredFullScreen = false

    var body: some View {
        let t = player.current
        ZStack {
            Color.black
            ArtworkView(track: t, size: 1400, radius: 0)
                .blur(radius: 60)
                .opacity(0.55)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            LinearGradient(colors: [.black.opacity(0.4), .clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform").foregroundStyle(Brand.accent)
                        Text(player.contextTitle.map { L("Đang phát từ \($0)") } ?? "Muzify")
                    }
                    .font(.system(size: 14, weight: .bold))
                    Spacer()
                    IconButton(symbol: "arrow.down.right.and.arrow.up.left", size: 16, help: L("Thoát toàn màn hình (Esc)"), action: close)
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                HStack(alignment: .bottom, spacing: 28) {
                    ArtworkView(track: t, size: 260, radius: 8)
                        .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
                    VStack(alignment: .leading, spacing: 10) {
                        if let line = currentLyric {
                            Text(line).font(.system(size: 20, weight: .bold)).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                                .animation(.easeInOut, value: line)
                        }
                        Text(t?.title ?? "").font(.system(size: 56, weight: .heavy)).lineLimit(2).minimumScaleFactor(0.5)
                        Text(t?.artist ?? "").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                    if let t { LikeButton(track: t, size: 26) }
                }
                Controls(big: true)
                    .padding(.top, 36)
            }
            .padding(48)
        }
        .foregroundStyle(.white)
        .onAppear {
            if let w = NSApp.keyWindow, !w.styleMask.contains(.fullScreen) {
                w.toggleFullScreen(nil)
                enteredFullScreen = true
            }
        }
        .task(id: t?.id) { if let t, lyrics.trackID != t.id { lyrics.load(t) } }
    }

    private var currentLyric: String? {
        guard case .found(let lines, true, _) = lyrics.state, lyrics.trackID == player.current?.id,
              let i = lyrics.currentLine(at: player.time) else { return nil }
        return lines[i].text.nilIfEmpty
    }

    private func close() {
        if enteredFullScreen, let w = NSApp.keyWindow, w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }
        withAnimation(.easeInOut(duration: 0.3)) { UIState.shared.fullScreen = false }
    }
}

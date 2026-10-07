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

// MARK: - Toàn màn hình (bố cục giống Spotify)

struct FullScreenPlayer: View {
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var remote = RemoteArt.shared
    @ObservedObject private var lyrics = LyricsStore.shared
    @State private var enteredFullScreen = false
    @State private var showLyrics = false
    @State private var idle = false
    @State private var lastMove = Date()
    @State private var scrub: Double?
    @State private var lastVolume: Float = 0.8

    var body: some View {
        let t = player.current
        GeometryReader { geo in
            let art = min(geo.size.height * 0.36, geo.size.width * 0.28, 360)
            ZStack(alignment: .topLeading) {
                backdrop(t, size: geo.size)

                VStack(alignment: .leading, spacing: 0) {
                    header.opacity(idle ? 0 : 1).allowsHitTesting(!idle)
                    if showLyrics { lyricLines.frame(maxWidth: .infinity, maxHeight: .infinity) } else { Spacer(minLength: 0) }
                    HStack(alignment: .bottom, spacing: 32) {
                        ArtworkView(track: t, size: art, radius: 8)
                            .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(t?.title ?? "")
                                .font(.system(size: min(art * 0.24, 72), weight: .heavy))
                                .tracking(-1)
                                .lineLimit(2)
                                .minimumScaleFactor(0.5)
                            Text(t?.artist ?? "")
                                .font(.system(size: min(art * 0.09, 26), weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 28)
                    bottomBar.opacity(idle ? 0 : 1).allowsHitTesting(!idle)
                }
                .padding(.horizontal, 56)
                .padding(.top, 40)
                .padding(.bottom, 40)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .foregroundStyle(.white)
        .background(Color.black)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: idle)
        .animation(.easeInOut(duration: 0.3), value: showLyrics)
        .onContinuousHover { _ in wake() }
        .onTapGesture { wake() }
        .onExitCommand(perform: close)
        .task {
            // Đứng yên chuột 3 giây (khi đang phát) → ẩn nút điều khiển và con trỏ.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !idle, player.isPlaying, Date().timeIntervalSince(lastMove) > 3 {
                    idle = true
                    NSCursor.setHiddenUntilMouseMoves(true)
                }
            }
        }
        .task(id: t?.id) { if let t, lyrics.trackID != t.id { lyrics.load(t) } }
        .onAppear {
            if let w = NSApp.keyWindow, !w.styleMask.contains(.fullScreen) {
                w.toggleFullScreen(nil)
                enteredFullScreen = true
            }
        }
        // Thoát bằng nút xanh / Esc của macOS → đóng luôn chế độ này.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in
            enteredFullScreen = false
            close()
        }
    }

    private func wake() {
        lastMove = .now
        if idle { idle = false }
    }

    /// Ảnh bìa phóng to làm mờ, luôn vừa khít khung.
    private func backdrop(_ t: Track?, size: CGSize) -> some View {
        ZStack {
            if let img = MusicLibrary.shared.artwork(t) {
                Image(platformImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .blur(radius: 70)
                    .opacity(0.6)
            }
            LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.25), .black.opacity(0.9)],
                           startPoint: .top, endPoint: .bottom)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill").font(.system(size: 30)).foregroundStyle(Brand.accent)
            if let ctx = player.contextTitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Đang phát từ")).font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                    Text(ctx).font(.system(size: 15, weight: .bold)).lineLimit(1)
                }
            }
            Spacer()
        }
    }

    /// Dòng trước (mờ) · dòng đang hát (to) · dòng sau (mờ).
    @ViewBuilder
    private var lyricLines: some View {
        if case .found(let lines, true, _) = lyrics.state, lyrics.trackID == player.current?.id {
            let i = lyrics.currentLine(at: player.time) ?? -1
            VStack(alignment: .leading, spacing: 18) {
                ForEach(max(i - 1, 0)...min(max(i, 0) + 2, lines.count - 1), id: \.self) { k in
                    Text(lines[k].text.isEmpty ? "♪" : lines[k].text)
                        .font(.system(size: k == i ? 44 : 32, weight: .bold))
                        .foregroundStyle(.white.opacity(k == i ? 1 : 0.4))
                        .lineLimit(2)
                        .onTapGesture { if let s = lyrics.seekTime(for: lines[k]) { player.seek(to: s) } }
                }
            }
            .animation(.easeInOut(duration: 0.35), value: i)
            .padding(.vertical, 24)
        } else {
            Text(lyrics.state == .loading ? L("Đang tải…") : L("Rất tiếc, chưa có lời cho bài hát này"))
                .font(.system(size: 28, weight: .bold)).foregroundStyle(.white.opacity(0.6))
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Text(formatTime(scrub ?? player.time)).frame(width: 48, alignment: .trailing)
                ScrubBar(value: player.duration > 0 ? (scrub ?? player.time) / player.duration : 0,
                         onChanged: { scrub = $0 * player.duration },
                         onCommit: { player.seek(to: $0 * player.duration); scrub = nil })
                Text(formatTime(player.duration)).frame(width: 48, alignment: .leading)
            }
            .font(.system(size: 12)).monospacedDigit().foregroundStyle(.white.opacity(0.7))

            // ⊕ bên trái · điều khiển ở giữa · lời bài hát, âm lượng, thoát bên phải.
            ZStack {
                HStack(spacing: 6) {
                    if let t = player.current { LikeButton(track: t, size: 22) }
                    Spacer()
                    IconButton(symbol: "music.mic", active: showLyrics, size: 17, help: L("Lời bài hát")) { showLyrics.toggle() }
                    IconButton(symbol: volumeSymbol, size: 17, help: player.volume == 0 ? L("Bật tiếng") : L("Tắt tiếng")) {
                        if player.volume > 0 { lastVolume = player.volume; player.volume = 0 } else { player.volume = max(lastVolume, 0.2) }
                    }
                    ScrubBar(value: Double(player.volume), onChanged: { player.volume = Float($0) }, onCommit: { player.volume = Float($0) })
                        .frame(width: 110)
                    IconButton(symbol: "arrow.down.right.and.arrow.up.left", size: 17, help: L("Thoát toàn màn hình (Esc)"), action: close)
                        .padding(.leading, 6)
                }
                HStack(spacing: 30) {
                    IconButton(symbol: "shuffle", active: player.shuffle, size: 20, help: L("Phát ngẫu nhiên")) { player.shuffle.toggle() }
                    IconButton(symbol: "backward.end.fill", size: 24, help: L("Bài trước")) { player.previous() }
                    CenterPlayButton(size: 60)
                    IconButton(symbol: "forward.end.fill", size: 24, help: L("Bài tiếp")) { player.next() }
                    IconButton(symbol: player.repeatMode == .one ? "repeat.1" : "repeat", active: player.repeatMode != .off,
                               size: 20, help: L("Lặp lại")) { player.cycleRepeat() }
                }
            }
        }
    }

    private var volumeSymbol: String {
        switch player.volume {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    private func close() {
        NSCursor.unhide()
        if enteredFullScreen, let w = NSApp.keyWindow ?? NSApp.mainWindow, w.styleMask.contains(.fullScreen) {
            enteredFullScreen = false
            w.toggleFullScreen(nil)
        }
        withAnimation(.easeInOut(duration: 0.3)) { UIState.shared.fullScreen = false }
    }
}

import SwiftUI

// MARK: - Đang phát (toàn màn hình, vuốt xuống để đóng)

struct NowPlayingScreen: View {
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var lyrics = LyricsStore.shared
    @ObservedObject private var remote = RemoteArt.shared
    @Environment(\.dismiss) private var dismiss
    @State private var scrub: Double?
    @State private var sheet: Sheet?
    @State private var dragY: CGFloat = 0

    enum Sheet: String, Identifiable { case lyrics, queue; var id: String { rawValue } }

    var body: some View {
        let t = player.current
        let tint = ArtColor.color(for: t) ?? MZ.hex(0x404040)
        GeometryReader { geo in
            let art = min(geo.size.width - 48, geo.size.height * 0.42, 520)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    header
                    ArtworkView(track: t, size: art, radius: 8)
                        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                        .scaleEffect(player.isPlaying ? 1 : 0.92)
                        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: player.isPlaying)
                        .padding(.top, 8)
                    titleRow(t)
                    progress
                    controls
                    bottomRow
                    if let t { lyricsCard(t, tint: tint) }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
                .frame(minHeight: geo.size.height)
            }
        }
        .foregroundStyle(.white)
        .background(LinearGradient(colors: [tint, tint.opacity(0.55), MZ.base], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .offset(y: dragY)
        .gesture(DragGesture().onChanged { g in dragY = max(g.translation.height, 0) }
            .onEnded { g in
                if g.translation.height > 140 { dismiss() }
                withAnimation(.spring) { dragY = 0 }
            })
        .sheet(item: $sheet) { s in
            switch s {
            case .lyrics: MobileLyrics()
            case .queue: MobileQueue()
            }
        }
        .task(id: t?.id) { if let t, lyrics.trackID != t.id { lyrics.load(t) } }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "chevron.down").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44) }
            Spacer()
            VStack(spacing: 2) {
                Text(L("Đang phát")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                Text(player.contextTitle ?? "Muzify").font(.system(size: 13, weight: .bold)).lineLimit(1)
            }
            Spacer()
            if let t = player.current {
                Menu { TrackMenu(track: t, queue: [t]) } label: {
                    Image(systemName: "ellipsis").font(.system(size: 20, weight: .bold)).frame(width: 44, height: 44)
                }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .buttonStyle(.plain)
    }

    private func titleRow(_ t: Track?) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t?.title ?? L("Chưa phát bài nào")).font(.system(size: 22, weight: .bold)).lineLimit(1)
                Text(t?.artist ?? "").font(.system(size: 16)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    .onTapGesture {
                        if let a = t?.artist {
                            dismiss()
                            UIState.shared.openArtist(LyricsStore.searchTerms(for: Track(title: "", artist: a, file: "")).artist)
                        }
                    }
            }
            Spacer()
            if let t { LikeButton(track: t, size: 26) }
        }
    }

    private var progress: some View {
        VStack(spacing: 6) {
            ScrubBar(value: player.duration > 0 ? (scrub ?? player.time) / player.duration : 0,
                     onChanged: { scrub = $0 * player.duration },
                     onCommit: { player.seek(to: $0 * player.duration); scrub = nil })
            HStack {
                Text(formatTime(scrub ?? player.time))
                Spacer()
                Text("-" + formatTime(max(player.duration - (scrub ?? player.time), 0)))
            }
            .font(.system(size: 11)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
        }
    }

    private var controls: some View {
        HStack {
            Button { player.shuffle.toggle() } label: {
                Image(systemName: "shuffle").font(.system(size: 22)).foregroundStyle(player.shuffle ? Brand.accent : .white)
            }
            Spacer()
            Button { haptic(); player.previous() } label: { Image(systemName: "backward.end.fill").font(.system(size: 30)) }
            Spacer()
            Button { haptic(); player.toggle() } label: {
                Group {
                    if player.isResolving || (player.isBuffering && player.isPlaying) { Spinner(color: .black, size: 26) }
                    else { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 30)).offset(x: player.isPlaying ? 0 : 2) }
                }
                .foregroundStyle(.black)
                .frame(width: 70, height: 70)
                .background(.white, in: Circle())
            }
            Spacer()
            Button { haptic(); player.next() } label: { Image(systemName: "forward.end.fill").font(.system(size: 30)) }
            Spacer()
            Button { player.cycleRepeat() } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat").font(.system(size: 22))
                    .foregroundStyle(player.repeatMode == .off ? .white : Brand.accent)
            }
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
        .disabled(player.current == nil)
    }

    private var bottomRow: some View {
        HStack {
            AirPlayRouteButton().frame(width: 32, height: 32)
            Spacer()
            Button { sheet = .lyrics } label: { Image(systemName: "quote.bubble").font(.system(size: 20)) }
                .accessibilityLabel(L("Lời bài hát"))
            Spacer().frame(width: 28)
            Button { sheet = .queue } label: { Image(systemName: "list.bullet").font(.system(size: 20)) }
                .accessibilityLabel(L("Danh sách chờ"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.85))
    }

    @ViewBuilder
    private func lyricsCard(_ t: Track, tint: Color) -> some View {
        if case .found(let lines, let synced, _) = lyrics.state, lyrics.trackID == t.id, !lines.isEmpty {
            let cur = synced ? lyrics.currentLine(at: player.time) ?? 0 : 0
            Button { sheet = .lyrics } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Xem trước lời bài hát")).font(.system(size: 15, weight: .bold))
                    ForEach(Array(lines[cur..<min(cur + 4, lines.count)])) { line in
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(line.id == lines[cur].id ? Color.white : Color.black.opacity(0.65))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(2)
                    }
                }
                .padding(16)
                .background(tint.opacity(0.95), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .animation(.easeInOut(duration: 0.3), value: cur)
            }
            .buttonStyle(PressScaleStyle(scale: 0.98))
        }
    }
}

// MARK: - Lời bài hát

struct MobileLyrics: View {
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var store = LyricsStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let bg = ArtColor.color(for: player.current) ?? MZ.hex(0x535353)
        NavigationStack {
            Group {
                switch store.state {
                case .idle, .loading:
                    ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                case .instrumental:
                    message(L("Bài này là nhạc không lời"))
                case .notFound:
                    message(L("Rất tiếc, chưa có lời cho bài hát này"))
                case .failed(let e):
                    message(L("Không tải được lời bài hát") + "\n" + e)
                case .found(let lines, let synced, let match):
                    lyrics(lines, synced: synced, match: match)
                }
            }
            .background(bg.ignoresSafeArea())
            .navigationTitle(player.current?.title ?? "")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.system(size: 22, weight: .bold)).multilineTextAlignment(.center).padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lyrics(_ lines: [LyricLine], synced: Bool, match: String) -> some View {
        let current = store.currentLine(at: player.time)
        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(lines) { line in
                        let isCur = line.id == current
                        let sung = synced && current.map { line.id < $0 } ?? false
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(isCur ? Color.white : sung ? Color.white.opacity(0.6) : synced ? Color.black.opacity(0.75) : .white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                            .onTapGesture { if let t = store.seekTime(for: line) { player.seek(to: t) } }
                            .animation(.easeInOut(duration: 0.3), value: isCur)
                    }
                    Text(match).font(.system(size: 12, weight: .semibold)).foregroundStyle(.black.opacity(0.6)).padding(.top, 30)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
            }
            .onChange(of: current) {
                guard let c = current else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) { proxy.scrollTo(c, anchor: UnitPoint(x: 0.5, y: 0.35)) }
            }
        }
    }
}

// MARK: - Danh sách chờ

struct MobileQueue: View {
    @ObservedObject private var player = MusicPlayer.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let cur = player.current {
                    Section(L("Đang phát")) { queueRow(cur, highlight: true) }
                }
                let next = player.upNext
                if !next.isEmpty {
                    Section {
                        ForEach(next, id: \.index) { item in
                            queueRow(item.track)
                                .onTapGesture { player.playQueueItem(at: item.index) }
                                .swipeActions { Button(L("Xoá"), role: .destructive) { player.removeUpcoming(at: item.index) } }
                        }
                    } header: {
                        HStack {
                            Text(player.contextTitle.map { L("Tiếp theo từ: \($0)") } ?? L("Tiếp theo")).lineLimit(1)
                            Spacer()
                            Button(L("Xoá danh sách chờ")) { player.clearUpcoming() }.font(.caption.bold())
                        }
                    }
                }
                Section(L("Đã phát gần đây")) {
                    ForEach(player.history.prefix(20)) { t in
                        queueRow(t).onTapGesture { player.play([t]) }
                    }
                }
            }
            .navigationTitle(L("Danh sách chờ"))
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "chevron.down") } }
            }
        }
    }

    private func queueRow(_ t: Track, highlight: Bool = false) -> some View {
        HStack(spacing: 12) {
            ArtworkView(track: t, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).foregroundStyle(highlight ? Brand.accent : MZ.text).lineLimit(1)
                Text(t.artist).font(.caption).foregroundStyle(MZ.subtext).lineLimit(1)
            }
            Spacer()
            if highlight && player.isPlaying { EqualizerBars() }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Cài đặt

struct MobileSettings: View {
    @ObservedObject private var settings = MusicSettings.shared
    @ObservedObject private var audio = AudioSettings.shared
    @ObservedObject private var lib = MusicLibrary.shared
    @Environment(\.dismiss) private var dismiss
    @State private var language = AppLanguage.selected

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L("Ngôn ngữ"), selection: $language) {
                        ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                    }
                    .onChange(of: language) { _, v in AppLanguage.selected = v }
                } footer: {
                    if language != AppLanguage.selected || language != .system {
                        Text(L("Mở lại Muzify để đổi ngôn ngữ."))
                    }
                }
                Section(L("Tìm kiếm & nghe online")) {
                    Picker(L("Kho nhạc"), selection: $settings.provider) {
                        ForEach(CatalogProvider.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle(L("Tự động phát"), isOn: $settings.autoplay)
                }
                Section(L("Âm thanh")) {
                    Toggle(L("Bộ chỉnh âm (EQ)"), isOn: $audio.eqEnabled)
                    Picker(L("Kiểu"), selection: Binding(get: { audio.preset }, set: { if let p = $0 { audio.apply(p) } })) {
                        ForEach(AudioSettings.Preset.allCases) { Text($0.title).tag(Optional($0)) }
                        if audio.preset == nil { Text(L("Tuỳ chỉnh")).tag(AudioSettings.Preset?.none) }
                    }
                    .disabled(!audio.eqEnabled)
                    Toggle(L("Tự cân âm lượng"), isOn: $audio.normalize)
                    Toggle(L("Bỏ qua đoạn không phải nhạc"), isOn: $audio.skipNonMusic)
                }
                Section(L("Thư viện")) {
                    LabeledContent(L("Bài hát đã thích"), value: "\(lib.liked.count)")
                    LabeledContent(L("Đã tải xuống"), value: "\(lib.downloaded.count)")
                    LabeledContent(L("Playlist"), value: "\(lib.playlists.count)")
                }
            }
            .navigationTitle(L("Cài đặt"))
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Xong")) { dismiss() } }
            }
        }
    }
}

import SwiftUI

// MARK: - Khung bên phải: Đang phát / Danh sách chờ

struct RightPanelView: View {
    @ObservedObject private var ui = UIState.shared

    var body: some View {
        Group {
            switch ui.rightPanel {
            case .queue: QueuePanel()
            default: NowPlayingPanel()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MZ.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Tiêu đề khung: [ẩn khung] Tên · … · ⤢ (giống Spotify).
private struct PanelHeader: View {
    let title: String
    var onTitle: (() -> Void)?
    var showExpand = false
    @State private var hoverTitle = false

    var body: some View {
        HStack(spacing: 8) {
            IconButton(symbol: "sidebar.right", size: 15, help: L("Ẩn khung")) {
                withAnimation(Brand.spring) { UIState.shared.rightPanel = .none }
            }
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .lineLimit(1)
                .underline(hoverTitle && onTitle != nil)
                .onHover { hoverTitle = $0 }
                .onTapGesture { onTitle?() }
            Spacer()
            if showExpand {
                IconButton(symbol: "arrow.up.left.and.arrow.down.right", size: 13, help: L("Toàn màn hình")) {
                    withAnimation(.easeInOut(duration: 0.3)) { UIState.shared.fullScreen = true }
                }
            }
        }
        .padding(.leading, -6)
    }
}

// MARK: Đang phát

private struct NowPlayingPanel: View {
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var lyrics = LyricsStore.shared
    @ObservedObject private var lib = MusicLibrary.shared
    @ObservedObject private var remote = RemoteArt.shared
    @ObservedObject private var artists = ArtistInfoStore.shared

    var body: some View {
        let t = player.current
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                PanelHeader(title: player.contextTitle ?? t?.title ?? "", onTitle: openContext, showExpand: t != nil)

                if let t {
                    ArtworkView(track: t, size: 288, radius: 8)
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                        .frame(maxWidth: .infinity)

                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.title).font(.system(size: 24, weight: .bold)).lineLimit(2)
                            ArtistLink(name: t.artist, size: 16)
                        }
                        Spacer()
                        if let link = t.source {
                            IconButton(symbol: "square.and.arrow.up", size: 16, help: L("Sao chép link bài hát")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(link, forType: .string)
                                UIState.shared.show(toast: L("Đã sao chép link"))
                            }
                        }
                        LikeButton(track: t, size: 20)
                    }

                    lyricsCard(t)
                    artistCard(t)
                    queueCard
                } else {
                    Text(L("Chưa phát bài nào")).foregroundStyle(MZ.subtext).padding(.top, 40).frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
        .task(id: t?.id) {
            if let t, lyrics.trackID != t.id { lyrics.load(t) }
        }
    }

    private func openContext() {
        guard let key = player.contextKey else { return }
        if key == "liked" { Router.shared.go(.liked) }
        else if key.hasPrefix("playlist:"), let id = UUID(uuidString: String(key.dropFirst(9))) { Router.shared.go(.playlist(id)) }
    }

    @ViewBuilder
    private func lyricsCard(_ t: Track) -> some View {
        let bg = ArtColor.color(for: t) ?? MZ.hex(0x535353)
        if case .found(let lines, let synced, _) = lyrics.state, lyrics.trackID == t.id, !lines.isEmpty {
            let cur = synced ? lyrics.currentLine(at: player.time) ?? 0 : 0
            let preview = Array(lines[cur..<min(cur + 4, lines.count)])
            Button { UIState.shared.toggleLyrics() } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Xem trước lời bài hát")).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(preview) { line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(line.id == lines[cur].id ? Color.white : Color.black.opacity(0.7))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .animation(.easeInOut(duration: 0.35), value: cur)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.98))
        }
    }

    /// "Giới thiệu về nghệ sĩ".
    private func artistCard(_ t: Track) -> some View {
        let name = LyricsStore.searchTerms(for: t).artist.components(separatedBy: CharacterSet(charactersIn: ",&")).first?
            .trimmed ?? t.artist
        let following = lib.isFollowing(name)
        let info = artists.info(name)
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let pic = info?.picture { RemoteImage(url: pic, placeholder: "person.fill") }
                    else { ArtworkView(track: t, size: 288, radius: 0) }
                }
                .frame(maxWidth: .infinity, maxHeight: 200)
                .clipped()
                .overlay(LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .center))
                Text(L("Giới thiệu về nghệ sĩ")).font(.system(size: 16, weight: .bold)).padding(16)
            }
            .frame(height: 200)
            .clipped()
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(.system(size: 16, weight: .bold)).lineLimit(1)
                            .onTapGesture { UIState.shared.openArtist(name) }
                        if let fans = info?.fans, fans > 0 {
                            Text(L("\(fans.formatted(.number.locale(.app))) người hâm mộ"))
                                .font(.system(size: 13)).foregroundStyle(MZ.subtext)
                        }
                    }
                    Spacer()
                    OutlineButton(title: following ? L("Đang theo dõi") : L("Theo dõi")) {
                        lib.toggleFollow(name, art: info?.picture ?? t.artworkURL)
                    }
                }
                if let bio = info?.bio {
                    Text(bio).font(.system(size: 13)).foregroundStyle(MZ.subtext).lineLimit(4)
                    if let w = info?.wikiURL, let u = URL(string: w) {
                        Link(L("Đọc thêm trên Wikipedia"), destination: u).font(.system(size: 12, weight: .semibold))
                    }
                }
            }
            .padding(16)
        }
        .background(MZ.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var queueCard: some View {
        let next = Array(player.upNext.prefix(5))
        if !next.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("Tiếp theo trong danh sách chờ")).font(.system(size: 16, weight: .bold))
                    Spacer()
                    ShowAllButton(expanded: false) { UIState.shared.rightPanel = .queue }
                }
                ForEach(next, id: \.index) { item in
                    QueueRow(track: item.track) { player.playQueueItem(at: item.index) }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MZ.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

// MARK: Danh sách chờ

private struct QueuePanel: View {
    @ObservedObject private var player = MusicPlayer.shared
    @State private var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(title: tab == 0 ? L("Danh sách chờ") : L("Đã phát gần đây"))
            HStack(spacing: 8) {
                Chip(title: L("Danh sách chờ"), selected: tab == 0) { tab = 0 }
                Chip(title: L("Đã phát gần đây"), selected: tab == 1) { tab = 1 }
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    if tab == 0 { queue } else { recent }
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var queue: some View {
        if let cur = player.current {
            Text(L("Đang phát")).font(.system(size: 16, weight: .bold)).padding(.top, 4)
            QueueRow(track: cur, highlight: true) { player.toggle() }
            let next = player.upNext
            if !next.isEmpty {
                HStack {
                    Text(player.contextTitle.map { L("Tiếp theo từ: \($0)") } ?? L("Tiếp theo"))
                        .font(.system(size: 16, weight: .bold)).lineLimit(1)
                    Spacer()
                    Button(L("Xoá danh sách chờ")) { player.clearUpcoming() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(MZ.subtext)
                }
                .padding(.top, 16)
                ForEach(next, id: \.index) { item in
                    QueueRow(track: item.track, onRemove: { player.removeUpcoming(at: item.index) }) {
                        player.playQueueItem(at: item.index)
                    }
                }
            } else {
                Text(MusicSettings.shared.autoplay ? L("Hết danh sách — Muzify sẽ tự phát tiếp bài tương tự.") : L("Không còn bài nào tiếp theo."))
                    .font(.system(size: 13)).foregroundStyle(MZ.subtext).padding(.top, 16)
            }
        } else {
            Text(L("Danh sách chờ trống")).foregroundStyle(MZ.subtext).padding(.top, 40).frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var recent: some View {
        ForEach(player.history) { t in
            QueueRow(track: t) { player.play([t]) }
        }
    }
}

struct QueueRow: View {
    @ObservedObject private var player = MusicPlayer.shared
    let track: Track
    var highlight = false
    var onRemove: (() -> Void)?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ArtworkView(track: track, size: 44)
                if hovering {
                    Color.black.opacity(0.45).clipShape(RoundedRectangle(cornerRadius: 4))
                    Image(systemName: highlight && player.isPlaying ? "pause.fill" : "play.fill").foregroundStyle(.white)
                }
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.system(size: 14)).foregroundStyle(highlight ? Brand.accent : MZ.text).lineLimit(1)
                Text(track.artist).font(.system(size: 12)).foregroundStyle(MZ.subtext).lineLimit(1)
            }
            Spacer(minLength: 0)
            if hovering, let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle").font(.system(size: 15)).foregroundStyle(MZ.subtext)
                }
                .buttonStyle(.plain)
                .help(L("Xoá khỏi danh sách chờ"))
            }
        }
        .padding(4)
        .background(hovering ? MZ.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .contextMenu { TrackMenu(track: track, queue: [track]) }
    }
}

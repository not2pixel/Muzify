import SwiftUI

// MARK: - Trang chủ

struct HomeView: View {
    @ObservedObject private var home = MusicHome.shared
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var lib = MusicLibrary.shared
    @ObservedObject private var settings = MusicSettings.shared
    @ObservedObject private var remote = RemoteArt.shared
    @State private var hoverTint: Color?
    @State private var tab: Tab = .all
    @State private var width: CGFloat = 1000

    enum Tab: CaseIterable {
        case all, music, artists
        var title: String {
            switch self {
            case .all: L("Tất cả")
            case .music: L("Nhạc")
            case .artists: L("Nghệ sĩ")
            }
        }
    }

    private var shelves: [HomeShelf] {
        switch tab {
        case .all: home.shelves
        case .music: home.shelves.filter { !($0.items.first?.round ?? false) }
        case .artists: home.shelves.filter { $0.items.first?.round ?? false }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                HStack(spacing: 8) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Chip(title: t.title, selected: tab == t) { withAnimation(Brand.quick) { tab = t } }
                    }
                    Spacer()
                    if home.loading { ProgressView().controlSize(.small) }
                    Button { home.load(force: true) } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain)
                        .foregroundStyle(MZ.subtext)
                        .help(L("Làm mới gợi ý"))
                }

                if tab != .artists { quickGrid }

                if settings.provider == .off {
                    Text(L("Bật YouTube Music trong Cài đặt để xem gợi ý và bảng xếp hạng."))
                        .foregroundStyle(MZ.subtext)
                } else {
                    if let e = home.error, home.shelves.isEmpty { Text(e).foregroundStyle(MZ.subtext) }
                    ForEach(shelves) { ShelfView(shelf: $0) }
                    if home.loading && home.shelves.isEmpty { placeholder }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 48)
            .background(WidthReader(width: $width))
        }
        .background(alignment: .top) {
            LinearGradient(colors: [(hoverTint ?? defaultTint).opacity(0.45), MZ.panel], startPoint: .top, endPoint: .bottom)
                .frame(height: 340)
                .animation(.easeInOut(duration: 0.6), value: hoverTint)
        }
        .background(MZ.panel)
        .onAppear { if settings.provider != .off { home.load() } }
    }

    private var defaultTint: Color {
        ArtColor.color(for: player.history.first) ?? MZ.hex(0x404040)
    }

    /// 8 ô truy cập nhanh đầu trang (Bài hát đã thích, playlist, nghe gần đây).
    private var quickGrid: some View {
        let lists = Array(lib.playlists.prefix(3))
        let recent = Array(player.history.prefix(7 - lists.count))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: width > 820 ? 4 : 2), spacing: 8) {
            QuickTile(title: L("Bài hát đã thích"), playing: player.isPlaying && player.contextKey == "liked",
                      onHover: { hoverTint = $0 ? Brand.liked : nil },
                      onOpen: { Router.shared.go(.liked) },
                      onPlay: { player.play(lib.liked, context: ("liked", L("Bài hát đã thích"))) }) {
                LikedCover(size: 56)
            }
            ForEach(lists) { p in
                QuickTile(title: p.name, playing: player.isPlaying && player.contextKey == "playlist:\(p.id)",
                          onHover: { hoverTint = $0 ? ArtColor.color(for: lib.tracks(in: p).first) : nil },
                          onOpen: { Router.shared.go(.playlist(p.id)) },
                          onPlay: { player.play(lib.tracks(in: p), context: ("playlist:\(p.id)", p.name)) }) {
                    PlaylistCover(playlist: p, size: 56)
                }
            }
            ForEach(recent) { t in
                QuickTile(title: t.title, playing: player.isCurrent(t) && player.isPlaying,
                          onHover: { hoverTint = $0 ? ArtColor.color(for: t) : nil },
                          onOpen: { Router.shared.go(.remote(.mix(t))) },
                          onPlay: { player.isCurrent(t) ? player.toggle() : player.play([t]) }) {
                    ArtworkView(track: t, size: 56, radius: 0)
                }
            }
        }
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 4).fill(MZ.elevated).frame(width: 220, height: 24)
            HStack(spacing: 16) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6).fill(MZ.elevated).frame(width: 164, height: 210)
                }
            }
        }
    }
}

/// Thông báo cài yt-dlp (cần để phát nhạc online).
struct ToolBanner: View {
    @ObservedObject private var lib = MusicLibrary.shared

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 28)).foregroundStyle(Brand.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Cài trình phát online (1 lần)")).font(.system(size: 15, weight: .bold))
                Text(L("Muzify cần công cụ mã nguồn mở yt-dlp (~30 MB) để phát và tải nhạc từ YouTube Music, SoundCloud."))
                    .font(.system(size: 13))
                    .foregroundStyle(MZ.subtext)
            }
            Spacer()
            if case .installing = lib.toolState {
                ProgressView().controlSize(.small)
            } else {
                Button(action: lib.installTool) {
                    Text(L("Cài đặt")).font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 18).padding(.vertical, 8).background(Brand.accent, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
            }
        }
        .padding(16)
        .background(MZ.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct QuickTile<Cover: View>: View {
    let title: String
    let playing: Bool
    let onHover: (Bool) -> Void
    let onOpen: () -> Void
    let onPlay: () -> Void
    @ViewBuilder let cover: Cover
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            cover.frame(width: 56, height: 56).clipped()
            Text(title).font(.system(size: 14, weight: .bold)).lineLimit(2)
            Spacer(minLength: 4)
            if hovering || playing {
                PlayButton(isPlaying: playing, size: 32, action: onPlay)
                    .padding(.trailing, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(height: 56)
        .background(hovering ? Color.white.opacity(0.17) : Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .contentShape(Rectangle())
        .onHover { h in
            withAnimation(Brand.quick) { hovering = h }
            onHover(h)
        }
        .onTapGesture(perform: onOpen)
    }
}

// MARK: - Kệ ngang

private struct ShelfView: View {
    @ObservedObject private var player = MusicPlayer.shared
    let shelf: HomeShelf
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    if let s = shelf.subtitle { Text(s).font(.system(size: 13)).foregroundStyle(MZ.subtext) }
                    Text(shelf.title).font(.system(size: 24, weight: .bold))
                }
                Spacer()
                if shelf.style == .cards && shelf.items.count > 5 {
                    ShowAllButton(expanded: expanded) { withAnimation(Brand.spring) { expanded.toggle() } }
                }
            }
            switch shelf.style {
            case .cards:
                if expanded {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 176), spacing: 0, alignment: .top)], alignment: .leading, spacing: 8) {
                        cards
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 0) { cards }
                    }
                    .padding(.horizontal, -10)
                }
            case .songs:
                let songs = shelf.items.compactMap { if case .song(let t) = $0.kind { t } else { nil } }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 8)], spacing: 2) {
                    ForEach(songs) { t in SongTile(track: t, queue: songs, context: ("shelf:\(shelf.title)", shelf.title)) }
                }
            }
        }
    }

    private var cards: some View {
        ForEach(shelf.items) { HomeCard(item: $0, siblings: shelf.items, shelfTitle: shelf.title) }
    }
}

struct ShowAllButton: View {
    let expanded: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(expanded ? L("Ẩn bớt") : L("Hiện tất cả"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(MZ.subtext)
                .underline(hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct HomeCard: View {
    @ObservedObject private var player = MusicPlayer.shared
    let item: HomeItem
    let siblings: [HomeItem]
    let shelfTitle: String
    @State private var loading = false

    private var song: Track? { if case .song(let t) = item.kind { t } else { nil } }
    private var target: HomeTarget? { if case .open(let t) = item.kind { t } else { nil } }

    var body: some View {
        let playing: Bool = {
            if let s = song { return player.isCurrent(s) && player.isPlaying }
            if let t = target { return player.isPlaying && player.contextKey == t.key }
            return false
        }()
        MediaCard(title: item.title, subtitle: item.subtitle, round: item.round, playing: playing) {
            if let t = item.localArt, MusicLibrary.shared.artwork(t) != nil {
                ArtworkView(track: t, size: 156, radius: 0)
            } else {
                RemoteImage(url: item.art, placeholder: item.round ? "person.fill" : "music.note.list")
            }
        } onOpen: {
            open()
        } onPlay: {
            playing ? player.toggle() : play()
        }
    }

    private var songs: [Track] { siblings.compactMap { if case .song(let s) = $0.kind { s } else { nil } } }

    private func open() {
        switch item.kind {
        case .song(let t): player.play(songs, startAt: t.id, context: ("shelf:\(shelfTitle)", shelfTitle))
        case .open(let target): Router.shared.go(.remote(target))
        }
    }

    private func play() {
        switch item.kind {
        case .song: open()
        case .open(let target):
            guard !loading else { return }
            loading = true
            Task {
                let tracks = (try? await target.page().tracks) ?? []
                loading = false
                player.play(tracks, context: (target.key, target.title))
            }
        }
    }
}

import SwiftUI

// MARK: - Tìm kiếm: Duyệt tìm (khi chưa gõ) / Kết quả

struct SearchView: View {
    @ObservedObject private var search = SearchModel.shared

    var body: some View {
        Group {
            if search.query.trimmed.isEmpty || Catalog.looksLikeLink(search.query) {
                BrowseView()
            } else {
                SearchResultsView()
            }
        }
        .background(MZ.panel)
    }
}

// MARK: Duyệt tìm tất cả

private struct BrowseView: View {
    @ObservedObject private var search = SearchModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if !search.recent.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Tìm kiếm gần đây")).font(.system(size: 24, weight: .bold))
                        FlowChips(items: search.recent)
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text(L("Duyệt tìm tất cả")).font(.system(size: 24, weight: .bold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 20)], spacing: 20) {
                        ForEach(Genre.all) { GenreCard(genre: $0) }
                    }
                }
            }
            .padding(24)
        }
    }
}

private struct FlowChips: View {
    @ObservedObject private var search = SearchModel.shared
    let items: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { q in
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 12)).foregroundStyle(MZ.subtext)
                        Text(q).font(.system(size: 14, weight: .medium))
                        Button { search.forget(q) } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(MZ.subtext)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(MZ.elevated, in: Capsule())
                    .contentShape(Capsule())
                    .onTapGesture { search.search(q) }
                }
            }
        }
    }
}

private struct GenreCard: View {
    let genre: Genre
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            MZ.hex(genre.color)
            Text(genre.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(16)
            Image(systemName: genre.symbol)
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 96, height: 96)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
                .rotationEffect(.degrees(25))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: 18, y: 6)
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .scaleEffect(hovering ? 1.02 : 1)
        .brightness(hovering ? 0.05 : 0)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Brand.quick) { hovering = h } }
        .onTapGesture { Router.shared.go(.remote(.genre(title: genre.title, query: genre.query))) }
    }
}

// MARK: Kết quả

private struct SearchResultsView: View {
    enum Tab: CaseIterable {
        case all, songs, artists
        var title: String {
            switch self {
            case .all: L("Tất cả")
            case .songs: L("Bài hát")
            case .artists: L("Nghệ sĩ")
            }
        }
    }

    @ObservedObject private var search = SearchModel.shared
    @ObservedObject private var lib = MusicLibrary.shared
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var settings = MusicSettings.shared
    @State private var tab: Tab = .all

    private var context: (key: String, title: String) { ("search:\(search.lastQuery)", L("Tìm “\(search.lastQuery)”")) }

    /// Nghệ sĩ rút ra từ kết quả (mỗi người một thẻ, ảnh = bài đầu tiên).
    private var artists: [Artist] {
        var seen = Set<String>()
        return search.results.compactMap { t in
            let name = LyricsStore.searchTerms(for: t).artist
            guard !name.isEmpty, name != L("Không rõ"), seen.insert(name.lowercased()).inserted else { return nil }
            return Artist(name: name, art: t.artworkURL)
        }
    }

    private var local: [Track] {
        let q = search.query.trimmed
        return lib.liked.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.artist.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 8) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Chip(title: t.title, selected: tab == t) { tab = t }
                    }
                    Spacer()
                    if search.searching { ProgressView().controlSize(.small) }
                    Text(settings.provider.title).font(.system(size: 12)).foregroundStyle(MZ.subtext)
                }

                if let error = search.error {
                    message(L("Không tìm được"), error)
                } else if search.results.isEmpty && !search.searching && !search.lastQuery.isEmpty {
                    message(L("Không tìm thấy kết quả nào cho “\(search.lastQuery)”"),
                            L("Hãy đảm bảo viết đúng chính tả, hoặc dùng ít từ khoá hơn."))
                } else {
                    switch tab {
                    case .all: allTab
                    case .songs: songsTab
                    case .artists: artistsTab
                    }
                }
            }
            .padding(24)
            .animation(Brand.quick, value: search.results.map(\.id))
        }
    }

    @ViewBuilder
    private var allTab: some View {
        if let top = search.results.first {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Kết quả hàng đầu")).font(.system(size: 24, weight: .bold))
                    TopResultCard(track: top) {
                        search.remember(search.lastQuery)
                        player.play(search.results, startAt: top.id, context: context)
                    }
                }
                .frame(minWidth: 300, maxWidth: 440)

                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Bài hát")).font(.system(size: 24, weight: .bold))
                    VStack(spacing: 0) {
                        ForEach(search.results.prefix(4)) { t in
                            TrackRow(number: nil, track: t, queue: search.results, context: context,
                                     showBadge: settings.provider == .all, onPlay: { search.remember(search.lastQuery) })
                        }
                    }
                }
            }
        }
        if !artists.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Nghệ sĩ")).font(.system(size: 24, weight: .bold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(artists.prefix(8)) { a in artistCard(a) }
                    }
                }
                .padding(.horizontal, -10)
            }
        }
        if !local.isEmpty && settings.provider != .all {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Trong Bài hát đã thích")).font(.system(size: 24, weight: .bold))
                VStack(spacing: 0) {
                    ForEach(local.prefix(5)) { t in
                        TrackRow(number: nil, track: t, queue: local, context: ("liked", L("Bài hát đã thích")))
                    }
                }
            }
        }
        if search.results.count > 4 {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Thêm bài hát")).font(.system(size: 24, weight: .bold))
                VStack(spacing: 0) {
                    ForEach(search.results.dropFirst(4)) { t in
                        TrackRow(number: nil, track: t, queue: search.results, context: context,
                                 showBadge: settings.provider == .all, onPlay: { search.remember(search.lastQuery) })
                    }
                }
            }
        }
    }

    private var songsTab: some View {
        VStack(spacing: 0) {
            TrackTableHeader(showSource: true, sourceTitle: L("Kho nhạc"))
            ForEach(Array(search.results.enumerated()), id: \.element.id) { i, t in
                TrackRow(number: i + 1, track: t, queue: search.results, context: context, showSource: true,
                         showBadge: settings.provider == .all, onPlay: { search.remember(search.lastQuery) })
            }
        }
    }

    private var artistsTab: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 176), spacing: 0, alignment: .top)], alignment: .leading, spacing: 8) {
            ForEach(artists) { a in artistCard(a) }
        }
        .padding(.horizontal, -10)
    }

    private func artistCard(_ a: Artist) -> some View {
        MediaCard(title: a.name, subtitle: L("Nghệ sĩ##một người"), round: true) {
            RemoteImage(url: a.art, placeholder: "person.fill")
        } onOpen: {
            search.remember(search.lastQuery)
            Router.shared.go(.remote(.artist(a.name)))
        }
    }

    private func message(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 22, weight: .bold)).multilineTextAlignment(.center)
            Text(detail).font(.system(size: 14)).foregroundStyle(MZ.subtext).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

private struct TopResultCard: View {
    @ObservedObject private var player = MusicPlayer.shared
    let track: Track
    let onPlay: () -> Void
    @State private var hovering = false

    var body: some View {
        let isCurrent = player.isCurrent(track)
        VStack(alignment: .leading, spacing: 16) {
            ArtworkView(track: track, size: 96, radius: 6)
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(track.title).font(.system(size: 30, weight: .bold)).lineLimit(2)
                    .foregroundStyle(isCurrent ? Brand.accent : MZ.text)
                HStack(spacing: 6) {
                    Text(L("Bài hát##một bài")).foregroundStyle(MZ.subtext)
                    Text("•").foregroundStyle(MZ.subtext)
                    ArtistLink(name: track.artist, hovering: true, size: 14)
                }
                .font(.system(size: 14))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? MZ.elevatedHover : MZ.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            PlayButton(isPlaying: isCurrent && player.isPlaying, size: 48) {
                if isCurrent { player.toggle() } else { onPlay() }
            }
            .padding(20)
            .opacity(hovering || isCurrent ? 1 : 0)
            .offset(y: hovering || isCurrent ? 0 : 8)
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { hovering = h } }
        .onTapGesture(count: 2, perform: onPlay)
        .contextMenu { TrackMenu(track: track, queue: [track]) }
    }
}

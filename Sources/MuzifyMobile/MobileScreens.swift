import SwiftUI
import UniformTypeIdentifiers

// MARK: - Hàng bài hát (iPhone / iPad)

struct MobileTrackRow: View {
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var lib = MusicLibrary.shared
    let track: Track
    let queue: [Track]
    var number: Int?
    var context: (key: String, title: String)?
    var playlistID: UUID?

    var body: some View {
        let isCurrent = player.isCurrent(track)
        HStack(spacing: 12) {
            if let number {
                Group {
                    if isCurrent && player.isPlaying { EqualizerBars() }
                    else { Text("\(number)").font(.system(size: 15)).monospacedDigit().foregroundStyle(isCurrent ? Brand.accent : MZ.subtext) }
                }
                .frame(width: 22)
            }
            ArtworkView(track: track, size: 48, radius: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 16))
                    .foregroundStyle(isCurrent ? Brand.accent : MZ.text)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    DownloadBadge(track: track)
                    Text(track.artist).font(.system(size: 13)).foregroundStyle(MZ.subtext).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Menu {
                TrackMenu(track: track, queue: queue, context: context, playlistID: playlistID)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MZ.subtext)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            haptic()
            if isCurrent { player.toggle() } else { player.play(queue, startAt: track.id, context: context) }
        }
        .contextMenu { TrackMenu(track: track, queue: queue, context: context, playlistID: playlistID) }
    }
}

// MARK: - Trang chủ

struct HomeScreen: View {
    @ObservedObject private var home = MusicHome.shared
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var lib = MusicLibrary.shared
    @ObservedObject private var settings = MusicSettings.shared
    @State private var showSettings = false

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: L("Chào buổi sáng")
        case 12..<18: L("Chào buổi chiều")
        default: L("Chào buổi tối")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                quickGrid
                if settings.provider == .off {
                    Text(L("Bật YouTube Music trong Cài đặt để xem gợi ý và bảng xếp hạng.")).foregroundStyle(MZ.subtext)
                }
                if let e = home.error, home.shelves.isEmpty { Text(e).foregroundStyle(MZ.subtext) }
                ForEach(home.shelves) { MobileShelf(shelf: $0) }
                if home.loading && home.shelves.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(40) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable { home.load(force: true) }
        .background(alignment: .top) {
            LinearGradient(colors: [(ArtColor.color(for: player.history.first) ?? Brand.liked).opacity(0.45), MZ.base],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 320)
                .ignoresSafeArea()
        }
        .background(MZ.base)
        .navigationTitle(greeting)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel(L("Cài đặt"))
            }
        }
        .sheet(isPresented: $showSettings) { MobileSettings() }
        .onAppear { if settings.provider != .off { home.load() } }
    }

    private var quickGrid: some View {
        let lists = Array(lib.playlists.prefix(1))
        let recent = Array(player.history.prefix(6 - lists.count))
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            QuickTile(title: L("Bài hát đã thích"), cover: AnyView(LikedCover(size: 56))) { MobileNav.shared.push(.liked) }
            ForEach(lists) { p in
                QuickTile(title: p.name, cover: AnyView(PlaylistCover(playlist: p, size: 56))) { MobileNav.shared.push(.playlist(p.id)) }
            }
            ForEach(recent) { t in
                QuickTile(title: t.title, cover: AnyView(ArtworkView(track: t, size: 56, radius: 0))) {
                    player.isCurrent(t) ? player.toggle() : player.play([t])
                }
            }
        }
    }
}

private struct QuickTile: View {
    let title: String
    let cover: AnyView
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                cover.frame(width: 56, height: 56).clipped()
                Text(title).font(.system(size: 13, weight: .bold)).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(height: 56)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
    }
}

private struct MobileShelf: View {
    @ObservedObject private var player = MusicPlayer.shared
    let shelf: HomeShelf

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if let s = shelf.subtitle { Text(s).font(.system(size: 13)).foregroundStyle(MZ.subtext) }
                Text(shelf.title).font(.system(size: 22, weight: .bold))
            }
            let songs = shelf.items.compactMap { if case .song(let t) = $0.kind { t } else { nil } }
            if shelf.style == .songs {
                VStack(spacing: 0) {
                    ForEach(songs.prefix(6)) { t in
                        MobileTrackRow(track: t, queue: songs, context: ("shelf:\(shelf.title)", shelf.title))
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(shelf.items) { item in card(item, songs: songs) }
                    }
                }
            }
        }
    }

    private func card(_ item: HomeItem, songs: [Track]) -> some View {
        Button {
            haptic()
            switch item.kind {
            case .song(let t): player.play(songs, startAt: t.id, context: ("shelf:\(shelf.title)", shelf.title))
            case .open(let target): MobileNav.shared.push(.remote(target))
            }
        } label: {
            VStack(alignment: item.round ? .center : .leading, spacing: 6) {
                Group {
                    if let t = item.localArt, MusicLibrary.shared.artwork(t) != nil { ArtworkView(track: t, size: 140, radius: 0) }
                    else { RemoteImage(url: item.art, placeholder: item.round ? "person.fill" : "music.note.list") }
                }
                .frame(width: 140, height: 140)
                .clipShape(item.round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous)))
                Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(item.subtitle).font(.system(size: 12)).foregroundStyle(MZ.subtext).lineLimit(2)
                    .multilineTextAlignment(item.round ? .center : .leading)
            }
            .frame(width: 140, alignment: item.round ? .center : .leading)
            .foregroundStyle(MZ.text)
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
    }
}

// MARK: - Tìm kiếm

struct SearchScreen: View {
    @ObservedObject private var search = SearchModel.shared
    @ObservedObject private var lib = MusicLibrary.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if search.query.trimmed.isEmpty || Catalog.looksLikeLink(search.query) {
                    browse
                } else {
                    results
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(MZ.base)
        .navigationTitle(L("Tìm kiếm"))
        .searchable(text: $search.query, prompt: L("Bạn muốn nghe gì?"))
        .plainInput()
        .onSubmit(of: .search) { search.submit() }
    }

    @ViewBuilder
    private var browse: some View {
        if Catalog.looksLikeLink(search.query) {
            Button { search.submit() } label: {
                Label(L("Tải bài hát từ link này"), systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(Brand.accent, in: Capsule())
                    .foregroundStyle(.black)
            }
            .buttonStyle(PressScaleStyle())
        }
        if !search.recent.isEmpty {
            Text(L("Tìm kiếm gần đây")).font(.system(size: 18, weight: .bold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(search.recent, id: \.self) { q in
                        Button { search.search(q) } label: {
                            Text(q).font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(MZ.elevated, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button(L("Xoá"), systemImage: "xmark") { search.forget(q) } }
                    }
                }
            }
        }
        Text(L("Duyệt tìm tất cả")).font(.system(size: 18, weight: .bold))
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            ForEach(Genre.all) { g in
                Button { MobileNav.shared.push(.remote(.genre(title: g.title, query: g.query))) } label: {
                    ZStack(alignment: .topLeading) {
                        MZ.hex(g.color)
                        Text(g.title).font(.system(size: 17, weight: .bold)).foregroundStyle(.white).padding(12)
                        Image(systemName: g.symbol)
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .rotationEffect(.degrees(25))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .offset(x: 8, y: 4)
                    }
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(PressScaleStyle(scale: 0.97))
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        let ctx = (key: "search:\(search.lastQuery)", title: L("Tìm “\(search.lastQuery)”"))
        if search.searching && search.results.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(40)
        } else if let e = search.error {
            Text(e).foregroundStyle(MZ.subtext).padding(.top, 20)
        } else if search.results.isEmpty && !search.lastQuery.isEmpty {
            Text(L("Không tìm thấy kết quả nào cho “\(search.lastQuery)”")).foregroundStyle(MZ.subtext).padding(.top, 20)
        }
        let artists = artistsFromResults
        if !artists.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(artists.prefix(8)) { a in
                        Button { MobileNav.shared.push(.remote(.artist(a.name))) } label: {
                            VStack(spacing: 6) {
                                ArtistAvatar(artist: a, size: 84)
                                Text(a.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).frame(width: 90)
                            }
                            .foregroundStyle(MZ.text)
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.95))
                    }
                }
            }
        }
        LazyVStack(spacing: 0) {
            ForEach(search.results) { t in
                MobileTrackRow(track: t, queue: search.results, context: ctx)
                    .simultaneousGesture(TapGesture().onEnded { search.remember(search.lastQuery) })
            }
        }
    }

    private var artistsFromResults: [Artist] {
        var seen = Set<String>()
        return search.results.compactMap { t in
            let name = LyricsStore.searchTerms(for: t).artist
            guard !name.isEmpty, name != L("Không rõ"), seen.insert(name.lowercased()).inserted else { return nil }
            return Artist(name: name, art: t.artworkURL)
        }
    }
}

// MARK: - Thư viện

struct LibraryScreen: View {
    @ObservedObject private var lib = MusicLibrary.shared
    @State private var importing = false
    @State private var askLink = false
    @State private var link = ""

    var body: some View {
        List {
            Section {
                NavigationLink(value: Route.liked) {
                    row(L("Bài hát đã thích"), L("Playlist • \(lib.liked.count) bài hát")) { LikedCover(size: 56) }
                }
                ForEach(lib.playlists) { p in
                    NavigationLink(value: Route.playlist(p.id)) {
                        row(p.name, L("Playlist • \(p.trackIDs.count) bài hát")) { PlaylistCover(playlist: p, size: 56) }
                    }
                    .swipeActions {
                        Button(L("Xoá"), role: .destructive) { UIState.shared.deletePlaylist(p.id) }
                    }
                }
                ForEach(lib.artists) { a in
                    NavigationLink(value: Route.remote(.artist(a.name))) {
                        row(a.name, L("Nghệ sĩ##một người")) { ArtistAvatar(artist: a, size: 56) }
                    }
                }
            }
            .listRowBackground(MZ.base)
            if !lib.jobs.isEmpty {
                Section(L("Đang tải xuống")) {
                    ForEach(lib.jobs) { j in
                        HStack {
                            Text(j.title).lineLimit(1)
                            Spacer()
                            if j.status == .failed {
                                Button(L("Thử lại")) { lib.retry(j) }.buttonStyle(.borderless)
                            } else {
                                ProgressView()
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(MZ.base)
        .navigationTitle(L("Thư viện"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(L("Tạo playlist mới"), systemImage: "music.note.list") {
                        let id = lib.newPlaylist()
                        UIState.shared.renaming = lib.playlists.first { $0.id == id }
                    }
                    Button(L("Nhập tệp nhạc…"), systemImage: "folder.badge.plus") { importing = true }
                    Button(L("Tải bài hát từ link…"), systemImage: "link") { askLink = true }
                } label: { Image(systemName: "plus") }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .mpeg4Movie, .movie], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { lib.importFiles(urls) }
        }
        .alert(L("Tải bài hát từ link…"), isPresented: $askLink) {
            TextField("https://…", text: $link).plainInput() // l10n:skip
            Button(L("Huỷ"), role: .cancel) { link = "" }
            Button(L("Tải xuống")) { lib.importLink(link); link = "" }
        } message: {
            Text(L("Dán link YouTube, YouTube Music hoặc Spotify."))
        }
    }

    private func row<C: View>(_ title: String, _ sub: String, @ViewBuilder cover: () -> C) -> some View {
        HStack(spacing: 12) {
            cover()
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16)).lineLimit(1)
                Text(sub).font(.system(size: 13)).foregroundStyle(MZ.subtext).lineLimit(1)
            }
        }
    }
}

// MARK: - Bài hát đã thích / playlist

struct CollectionScreen: View {
    @ObservedObject private var lib = MusicLibrary.shared
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var remote = RemoteArt.shared
    let playlistID: UUID?

    private var playlist: Playlist? { playlistID.flatMap { id in lib.playlists.first { $0.id == id } } }
    private var tracks: [Track] { playlist.map(lib.tracks(in:)) ?? lib.liked }
    private var title: String { playlist?.name ?? L("Bài hát đã thích") }
    private var context: (key: String, title: String) { playlist.map { ("playlist:\($0.id)", $0.name) } ?? ("liked", L("Bài hát đã thích")) }
    private var tint: Color { playlist == nil ? Brand.liked : ArtColor.color(for: tracks.first) ?? MZ.hex(0x535353) }

    var body: some View {
        let list = tracks
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    if let p = playlist { PlaylistCover(playlist: p, size: 220) } else { LikedCover(size: 220) }
                }
                .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                Text(title).font(.system(size: 26, weight: .bold))
                Text(L("\(list.count) bài hát") + (list.isEmpty ? "" : " • " + formatLength(list.reduce(0) { $0 + $1.duration })))
                    .font(.system(size: 13)).foregroundStyle(MZ.subtext)
                ActionRow(tracks: list, context: context) {
                    if let p = playlist {
                        Button(L("Đổi tên…"), systemImage: "pencil") { UIState.shared.renaming = p }
                        Button(L("Xoá playlist"), systemImage: "trash", role: .destructive) { UIState.shared.deletePlaylist(p.id) }
                    }
                }
                if list.isEmpty {
                    Text(playlist == nil ? L("Bài hát bạn thích sẽ xuất hiện ở đây") : L("Hãy tìm nội dung cho playlist của bạn"))
                        .font(.system(size: 17, weight: .bold)).frame(maxWidth: .infinity).padding(.top, 30)
                }
                LazyVStack(spacing: 0) {
                    ForEach(list) { t in
                        MobileTrackRow(track: t, queue: list, context: context, playlistID: playlist?.id)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(alignment: .top) {
            LinearGradient(colors: [tint, MZ.base], startPoint: .top, endPoint: .bottom).frame(height: 420).ignoresSafeArea()
        }
        .background(MZ.base)
        .navigationTitle(title)
        .inlineTitle()
    }
}

/// Phát · Trộn · Tải xuống · …
struct ActionRow<Extra: View>: View {
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var lib = MusicLibrary.shared
    let tracks: [Track]
    let context: (key: String, title: String)
    @ViewBuilder var extra: Extra

    var body: some View {
        let here = player.contextKey == context.key && player.current != nil
        let allDownloaded = !tracks.isEmpty && tracks.allSatisfy { lib.isDownloaded($0) }
        HStack(spacing: 20) {
            Button {
                lib.downloadAll(tracks)
                UIState.shared.show(toast: L("Đang tải xuống \(tracks.filter { !lib.isDownloaded($0) }.count) bài hát"))
            } label: {
                Image(systemName: allDownloaded ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 26)).foregroundStyle(allDownloaded ? Brand.accent : MZ.subtext)
            }
            .disabled(tracks.isEmpty || allDownloaded)
            Menu {
                Button(L("Thêm vào danh sách chờ"), systemImage: "text.badge.plus") { UIState.shared.addToQueue(tracks) }
                extra
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 22, weight: .bold)).foregroundStyle(MZ.subtext).frame(height: 44)
            }
            Spacer()
            Button { player.shuffle.toggle() } label: {
                Image(systemName: "shuffle").font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(player.shuffle ? Brand.accent : MZ.subtext)
            }
            PlayButton(isPlaying: here && player.isPlaying, size: 52, loading: here && player.isResolving) {
                haptic()
                if here { player.toggle() } else { player.play(tracks, context: context) }
            }
            .disabled(tracks.isEmpty)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Trang online: playlist YouTube Music, mix, nghệ sĩ, thể loại

struct RemoteScreen: View {
    @ObservedObject private var lib = MusicLibrary.shared
    @ObservedObject private var remote = RemoteArt.shared
    @ObservedObject private var artists = ArtistInfoStore.shared
    let target: HomeTarget
    @State private var page: YTM.Page?
    @State private var error: String?

    private var tracks: [Track] { page?.tracks ?? [] }
    private var art: String? {
        if case .artist(let n) = target, let pic = artists.info(n)?.picture { return pic }
        return page?.art ?? tracks.first?.artworkURL
    }
    private var tint: Color { ArtColor.color(url: art) ?? MZ.hex(0x535353) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RemoteImage(url: art, placeholder: target.isArtist ? "person.fill" : "music.note.list")
                    .frame(width: 220, height: 220)
                    .clipShape(target.isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                Text(page?.title ?? target.title).font(.system(size: 26, weight: .bold))
                if let page {
                    Text(page.subtitle.isEmpty ? L("\(page.tracks.count) bài hát") : "\(page.subtitle) • " + L("\(page.tracks.count) bài hát")) // l10n:skip
                        .font(.system(size: 13)).foregroundStyle(MZ.subtext)
                }
                if case .artist(let name) = target {
                    if let bio = artists.info(name)?.bio {
                        Text(bio).font(.system(size: 13)).foregroundStyle(MZ.subtext).lineLimit(4)
                    }
                }
                ActionRow(tracks: tracks, context: (target.key, page?.title ?? target.title)) {
                    if case .artist(let name) = target {
                        Button(lib.isFollowing(name) ? L("Bỏ theo dõi") : L("Theo dõi"), systemImage: "person.badge.plus") {
                            lib.toggleFollow(name, art: art)
                        }
                    } else {
                        Button(L("Lưu vào Thư viện"), systemImage: "plus.circle") {
                            lib.savePlaylist(name: page?.title ?? target.title, tracks: tracks)
                            UIState.shared.show(toast: L("Đã lưu vào Thư viện"))
                        }
                    }
                    Button(L("Thích tất cả"), systemImage: "heart") { tracks.forEach { lib.setLiked($0, true) } }
                }
                if let error { Text(error).foregroundStyle(MZ.subtext) }
                else if page == nil { ProgressView().frame(maxWidth: .infinity).padding(30) }
                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                        MobileTrackRow(track: t, queue: tracks, number: target.isArtist ? i + 1 : nil,
                                       context: (target.key, page?.title ?? target.title))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(alignment: .top) {
            LinearGradient(colors: [tint, MZ.base], startPoint: .top, endPoint: .bottom).frame(height: 420).ignoresSafeArea()
        }
        .background(MZ.base)
        .navigationTitle(page?.title ?? target.title)
        .inlineTitle()
        .task(id: target) {
            do {
                let p = try await target.page()
                lib.remember(p.tracks)
                page = p
                if p.tracks.isEmpty { error = L("Không có bài nào.") }
            } catch {
                self.error = L("Không tải được: \(error.localizedDescription)")
            }
        }
    }
}

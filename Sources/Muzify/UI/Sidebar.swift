import SwiftUI

// MARK: - Thư viện bên trái

struct LibrarySidebar: View {
    enum Filter: String { case playlists, artists }
    enum Sort: String, CaseIterable { case recent, alpha }

    @ObservedObject private var lib = MusicLibrary.shared
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var router = Router.shared
    @ObservedObject private var ui = UIState.shared
    @State private var filter: Filter?
    @State private var searching = false
    @State private var text = ""
    @AppStorage("librarySort") private var sort: Sort = .recent

    private var wide: Bool { ui.libraryWide }

    private var playlists: [Playlist] {
        var list = lib.playlists
        if !text.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(text) } }
        if sort == .alpha { list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
        return list
    }

    private var artists: [Artist] {
        var list = lib.artists
        if !text.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(text) } }
        if sort == .alpha { list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if wide {
                chips
                tools
            }
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    if filter != .artists && (text.isEmpty || L("Bài hát đã thích").lowercased().contains(text.lowercased())) {
                        SidebarItem(selected: router.current == .liked, wide: wide, title: L("Bài hát đã thích"),
                                    subtitle: L("Playlist • \(lib.liked.count) bài hát"), pinned: true,
                                    playing: player.isPlaying && player.contextKey == "liked") {
                            LikedCover(size: 48)
                        } action: { router.go(.liked) }
                        .dropDestination(for: String.self) { ids, _ in
                            for t in ids.compactMap(UUID.init(uuidString:)).compactMap(lib.track) { lib.setLiked(t, true) }
                            return true
                        }
                    }
                    if filter != .artists {
                        ForEach(playlists) { p in
                            SidebarItem(selected: router.current == .playlist(p.id), wide: wide, title: p.name,
                                        subtitle: L("Playlist • \(p.trackIDs.count) bài hát"),
                                        playing: player.isPlaying && player.contextKey == "playlist:\(p.id)") {
                                PlaylistCover(playlist: p, size: 48)
                            } action: { router.go(.playlist(p.id)) }
                            .contextMenu {
                                Button(L("Phát"), systemImage: "play.fill") {
                                    player.play(lib.tracks(in: p), context: ("playlist:\(p.id)", p.name))
                                }
                                Button(L("Thêm vào danh sách chờ"), systemImage: "text.badge.plus") { ui.addToQueue(lib.tracks(in: p)) }
                                Button(L("Tải xuống"), systemImage: "arrow.down.circle") { lib.downloadAll(lib.tracks(in: p)) }
                                Divider()
                                Button(L("Đổi tên…"), systemImage: "pencil") { ui.renaming = p }
                                Button(L("Xoá playlist"), systemImage: "trash", role: .destructive) { ui.deletePlaylist(p.id) }
                            }
                            .dropDestination(for: String.self) { ids, _ in
                                lib.add(ids: ids.compactMap(UUID.init(uuidString:)), to: p.id)
                                ui.show(toast: L("Đã thêm vào \(p.name)"))
                                return true
                            }
                        }
                    }
                    if filter != .playlists {
                        ForEach(artists) { a in
                            SidebarItem(selected: router.current == .remote(.artist(a.name)), wide: wide, title: a.name,
                                        subtitle: L("Nghệ sĩ##một người"), round: true,
                                        playing: player.isPlaying && player.contextKey == HomeTarget.artist(a.name).key) {
                                ArtistAvatar(artist: a, size: 48)
                            } action: { router.go(.remote(.artist(a.name))) }
                            .contextMenu {
                                Button(L("Bỏ theo dõi"), systemImage: "person.badge.minus") { lib.toggleFollow(a.name, art: a.art) }
                            }
                        }
                    }
                    if wide && lib.playlists.isEmpty && lib.artists.isEmpty && text.isEmpty {
                        emptyHint
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .background(MZ.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: Đầu khung

    @ViewBuilder
    private var header: some View {
        let toggle = Button { withAnimation(Brand.spring) { ui.libraryWide.toggle() } } label: {
            HStack(spacing: 10) {
                Image(systemName: "books.vertical.fill").font(.system(size: 20))
                if wide { Text(L("Thư viện")).font(.system(size: 16, weight: .bold)) }
            }
            .foregroundStyle(MZ.subtext)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(wide ? L("Thu gọn Thư viện") : L("Mở rộng Thư viện"))

        if wide {
            HStack(spacing: 8) {
                toggle
                Spacer()
                createMenu
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
        } else {
            VStack(spacing: 14) {
                toggle
                createMenu
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    private var createMenu: some View {
        Menu {
            Button(L("Tạo playlist mới"), systemImage: "music.note.list") { ui.newPlaylist() }
            Button(L("Nhập tệp nhạc từ máy…"), systemImage: "folder.badge.plus") { lib.importWithPanel() }
            Button(L("Tải bài hát từ link…"), systemImage: "link") {
                router.go(.search)
                NotificationCenter.default.post(name: .focusSearch, object: nil)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                if wide { Text(L("Tạo")).font(.system(size: 14, weight: .bold)) }
            }
            .foregroundStyle(MZ.text)
            .padding(.horizontal, wide ? 14 : 0)
            .frame(width: wide ? nil : 32, height: 32)
            .background(MZ.elevated, in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Tạo playlist hoặc thêm nhạc"))
    }

    private var chips: some View {
        HStack(spacing: 8) {
            if filter != nil {
                Button { withAnimation(Brand.quick) { filter = nil } } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(MZ.text)
                        .frame(width: 28, height: 28).background(MZ.elevated, in: Circle())
                }
                .buttonStyle(PressScaleStyle())
            }
            if filter != .artists {
                Chip(title: "Playlist", selected: filter == .playlists) {
                    withAnimation(Brand.quick) { filter = filter == .playlists ? nil : .playlists }
                }
            }
            if filter != .playlists && !lib.artists.isEmpty {
                Chip(title: L("Nghệ sĩ"), selected: filter == .artists) {
                    withAnimation(Brand.quick) { filter = filter == .artists ? nil : .artists }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var tools: some View {
        HStack(spacing: 6) {
            if searching {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(MZ.subtext)
                    PlainTextField(placeholder: L("Tìm trong Thư viện"), text: $text,
                                   onEscape: { text = ""; searching = false })
                }
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background(MZ.elevated, in: RoundedRectangle(cornerRadius: 4))
            } else {
                Button { withAnimation(Brand.quick) { searching = true } } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(MZ.subtext)
                        .frame(width: 32, height: 32).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(L("Tìm trong Thư viện"))
            }
            Spacer()
            Menu {
                Picker(L("Sắp xếp theo"), selection: $sort) {
                    Text(L("Gần đây")).tag(Sort.recent)
                    Text(L("Thứ tự chữ cái")).tag(Sort.alpha)
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 6) {
                    Text(sort == .recent ? L("Gần đây") : L("Chữ cái"))
                    Image(systemName: "list.bullet")
                }
                .font(.system(size: 13))
                .foregroundStyle(MZ.subtext)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Tạo playlist đầu tiên của bạn")).font(.system(size: 15, weight: .bold))
            Text(L("Rất dễ! Chúng tôi sẽ giúp bạn.")).font(.system(size: 13)).foregroundStyle(MZ.text)
            Button { ui.newPlaylist() } label: {
                Text(L("Tạo playlist")).font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
                    .padding(.horizontal, 14).padding(.vertical, 7).background(.white, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MZ.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.top, 8)
    }
}

private struct SidebarItem<Cover: View>: View {
    let selected: Bool
    let wide: Bool
    let title: String
    let subtitle: String
    var pinned = false
    var round = false
    let playing: Bool
    @ViewBuilder let cover: Cover
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                cover
                if wide {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 15))
                            .foregroundStyle(playing ? Brand.accent : MZ.text)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Brand.accent).rotationEffect(.degrees(45)) }
                            Text(subtitle).font(.system(size: 13)).foregroundStyle(MZ.subtext).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if playing { Image(systemName: "speaker.wave.2.fill").font(.system(size: 12)).foregroundStyle(Brand.accent) }
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: wide ? .leading : .center)
            .background(selected ? MZ.selected : hovering ? MZ.hover : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(wide ? "" : title)
    }
}

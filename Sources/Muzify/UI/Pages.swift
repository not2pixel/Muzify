import SwiftUI

// MARK: - Thành phần chung của trang playlist / nghệ sĩ

/// Đầu trang: ảnh bìa lớn + loại + tên rất to + thông tin, nền màu theo ảnh bìa.
struct PageHeader<Cover: View, Meta: View>: View {
    let tint: Color
    let kind: String
    let title: String
    let compact: Bool
    @ViewBuilder let cover: Cover
    @ViewBuilder let meta: Meta

    var body: some View {
        HStack(alignment: .bottom, spacing: 24) {
            cover.shadow(color: .black.opacity(0.5), radius: 30, y: 12)
            VStack(alignment: .leading, spacing: 8) {
                Text(kind).font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: title.count > 24 || compact ? 44 : 72, weight: .heavy))
                    .tracking(-1.2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) { meta }
                    .font(.system(size: 14))
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 72)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [tint, tint.opacity(0.75)], startPoint: .top, endPoint: .bottom))
    }
}

/// Thanh tiêu đề dính trên cùng, hiện khi đã cuộn qua đầu trang.
struct StickyHeader: View {
    let visible: Bool
    let tint: Color
    let title: String
    let isPlaying: Bool
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PlayButton(isPlaying: isPlaying, size: 44, action: onPlay)
            Text(title).font(.system(size: 22, weight: .bold)).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(height: 64)
        .background(tint.overlay(Color.black.opacity(0.45)))
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .animation(.easeOut(duration: 0.2), value: visible)
    }
}

/// Màn trang có cuộn + thanh dính.
private struct PageScroll<Content: View>: View {
    let tint: Color
    let title: String
    let isPlaying: Bool
    let onPlay: () -> Void
    @ViewBuilder let content: Content
    @State private var offset: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScrollOffsetReader()
                content
            }
        }
        .coordinateSpace(name: "page")
        .onPreferenceChange(ScrollOffsetKey.self) { offset = $0 }
        .overlay(alignment: .top) {
            StickyHeader(visible: offset < -260, tint: tint, title: title, isPlaying: isPlaying, onPlay: onPlay)
        }
        .background(MZ.panel)
    }
}

// MARK: - Bài hát đã thích / Playlist của bạn

struct CollectionView: View {
    enum Kind: Hashable { case liked, playlist(UUID) }
    enum SortKey: String, CaseIterable { case custom, title, artist, added, duration }

    let kind: Kind
    @ObservedObject private var lib = MusicLibrary.shared
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var remote = RemoteArt.shared
    @AppStorage("collectionSort") private var sort: SortKey = .custom
    @State private var filter = ""
    @State private var filtering = false
    @State private var width: CGFloat = 1000
    @State private var dropTargeted = false

    private var playlist: Playlist? {
        if case .playlist(let id) = kind { return lib.playlists.first { $0.id == id } }
        return nil
    }

    private var context: (key: String, title: String) {
        if let p = playlist { return ("playlist:\(p.id)", p.name) }
        return ("liked", L("Bài hát đã thích"))
    }

    private var base: [Track] { playlist.map(lib.tracks(in:)) ?? lib.liked }

    private var shown: [Track] {
        var list = base
        if !filter.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(filter) || $0.artist.localizedCaseInsensitiveContains(filter) }
        }
        switch sort {
        case .custom: return list
        case .title: return list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist: return list.sorted { $0.artist.localizedStandardCompare($1.artist) == .orderedAscending }
        case .added: return list.sorted { $0.addedAt > $1.addedAt }
        case .duration: return list.sorted { $0.duration < $1.duration }
        }
    }

    private var tint: Color {
        guard let p = playlist else { return Brand.liked }
        return ArtColor.color(for: lib.tracks(in: p).first) ?? MZ.hex(0x535353)
    }

    private var isPlayingHere: Bool { player.contextKey == context.key && player.current != nil }

    private func playAll() {
        if isPlayingHere { player.toggle() } else { player.play(shown, context: context) }
    }

    var body: some View {
        let list = shown
        PageScroll(tint: tint, title: playlist?.name ?? L("Bài hát đã thích"),
                   isPlaying: isPlayingHere && player.isPlaying, onPlay: playAll) {
            header(list)
            actionBar(list)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(lib.jobs.filter { $0.trackID == nil || kind == .liked }) { JobRow(job: $0) }
                if !list.isEmpty {
                    TrackTableHeader(showSource: width > 860, showDate: width > 680)
                }
            }
            .padding(.horizontal, 24)

            LazyVStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, t in
                    row(i, t, list)
                }
            }
            .padding(.horizontal, 24)

            if list.isEmpty && lib.jobs.isEmpty { emptyState }
            Color.clear.frame(height: 32)
        }
        .background(WidthReader(width: $width))
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.accent, lineWidth: 2)
                    .background(Brand.accent.opacity(0.06))
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            if !files.isEmpty { lib.importFiles(files) }
            if let web = urls.first(where: { !$0.isFileURL }) { lib.importLink(web.absoluteString) }
            return true
        } isTargeted: { dropTargeted = $0 && kind == .liked }
    }

    @ViewBuilder
    private func row(_ i: Int, _ t: Track, _ list: [Track]) -> some View {
        let r = TrackRow(number: i + 1, track: t, queue: list, context: context, playlistID: playlist?.id,
                         showSource: width > 860, showDate: width > 680)
        if let p = playlist, sort == .custom, filter.isEmpty {
            r.dropDestination(for: String.self) { ids, _ in
                for id in ids.compactMap(UUID.init(uuidString:)) {
                    if p.trackIDs.contains(id) { lib.move(id, before: t.id, in: p.id) }
                    else if let dropped = lib.track(id) { lib.add([dropped], to: p.id); lib.move(lib.persist(dropped), before: t.id, in: p.id) }
                }
                return true
            }
        } else {
            r
        }
    }

    private func header(_ list: [Track]) -> some View {
        let total = list.reduce(0) { $0 + $1.duration }
        let compact = width < 760
        return PageHeader(tint: tint, kind: playlist == nil ? "Playlist" : "Playlist", title: playlist?.name ?? L("Bài hát đã thích"),
                          compact: compact) {
            Group {
                if let p = playlist { PlaylistCover(playlist: p, size: compact ? 160 : 232) }
                else { LikedCover(size: compact ? 160 : 232) }
            }
            .onTapGesture { if let p = playlist { UIState.shared.renaming = p } }
        } meta: {
            Text(L("Bạn")).fontWeight(.bold)
            Text(L("• \(list.count) bài hát\(total > 0 ? ", \(formatLength(total))" : "")"))
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    private func actionBar(_ list: [Track]) -> some View {
        let allDownloaded = !list.isEmpty && list.allSatisfy { lib.isDownloaded($0) }
        return HStack(spacing: 24) {
            PlayButton(isPlaying: isPlayingHere && player.isPlaying, loading: isPlayingHere && player.isResolving, action: playAll)
                .disabled(list.isEmpty)
                .opacity(list.isEmpty ? 0.5 : 1)
            IconButton(symbol: "shuffle", active: player.shuffle, size: 26, help: L("Phát ngẫu nhiên")) { player.shuffle.toggle() }
            IconButton(symbol: allDownloaded ? "arrow.down.circle.fill" : "arrow.down.circle", active: allDownloaded,
                       size: 26, help: allDownloaded ? L("Đã tải xuống") : L("Tải xuống"), dot: false) {
                if !allDownloaded {
                    lib.downloadAll(list)
                    UIState.shared.show(toast: L("Đang tải xuống \(list.filter { !lib.isDownloaded($0) }.count) bài hát"))
                }
            }
            .disabled(list.isEmpty)
            Menu {
                if let p = playlist {
                    Button(L("Thêm vào danh sách chờ"), systemImage: "text.badge.plus") { UIState.shared.addToQueue(list) }
                    Button(L("Đổi tên…"), systemImage: "pencil") { UIState.shared.renaming = p }
                    Divider()
                    Button(L("Xoá playlist"), systemImage: "trash", role: .destructive) { UIState.shared.deletePlaylist(p.id) }
                } else {
                    Button(L("Nhập tệp nhạc từ máy…"), systemImage: "folder.badge.plus", action: lib.importWithPanel)
                    Button(L("Thêm vào danh sách chờ"), systemImage: "text.badge.plus") { UIState.shared.addToQueue(list) }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 24, weight: .bold)).foregroundStyle(MZ.subtext)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()

            if filtering {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(MZ.subtext)
                    PlainTextField(placeholder: L("Tìm trong playlist"), text: $filter, onEscape: { filter = ""; filtering = false })
                        .frame(width: 180)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(MZ.elevated, in: RoundedRectangle(cornerRadius: 4))
            } else {
                Button { withAnimation(Brand.quick) { filtering = true } } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(MZ.subtext)
                }
                .buttonStyle(.plain)
                .help(L("Tìm trong playlist"))
            }

            Menu {
                Picker(L("Sắp xếp theo"), selection: $sort) {
                    Text(playlist == nil ? L("Mới thêm trước") : L("Thứ tự tuỳ chỉnh")).tag(SortKey.custom)
                    Text(L("Tiêu đề")).tag(SortKey.title)
                    Text(L("Nghệ sĩ##một người")).tag(SortKey.artist)
                    Text(L("Ngày thêm")).tag(SortKey.added)
                    Text(L("Thời lượng")).tag(SortKey.duration)
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 6) {
                    Text(sortTitle)
                    Image(systemName: "list.bullet")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MZ.subtext)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(LinearGradient(colors: [tint.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom))
    }

    private var sortTitle: String {
        switch sort {
        case .custom: playlist == nil ? L("Gần đây") : L("Thứ tự tuỳ chỉnh")
        case .title: L("Tiêu đề")
        case .artist: L("Nghệ sĩ##một người")
        case .added: L("Ngày thêm")
        case .duration: L("Thời lượng")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: playlist == nil ? "heart" : "music.note.list").font(.system(size: 44)).foregroundStyle(MZ.subtext)
            Text(playlist == nil ? L("Bài hát bạn thích sẽ xuất hiện ở đây") : L("Hãy tìm nội dung cho playlist của bạn"))
                .font(.system(size: 22, weight: .bold))
            Text(playlist == nil
                 ? L("Lưu bài hát bằng cách nhấn vào biểu tượng ⊕. Bạn cũng có thể dán link vào ô tìm kiếm hoặc kéo thả tệp nhạc vào đây.")
                 : L("Kéo bài hát thả vào playlist ở Thư viện bên trái, hoặc chuột phải vào bài hát → Thêm vào playlist."))
                .font(.system(size: 14))
                .foregroundStyle(MZ.subtext)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button { Router.shared.go(.search); NotificationCenter.default.post(name: .focusSearch, object: nil) } label: {
                Text(L("Tìm bài hát")).font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                    .padding(.horizontal, 22).padding(.vertical, 10).background(.white, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }
}

/// Tiến độ tải xuống / nhập link.
struct JobRow: View {
    @ObservedObject private var lib = MusicLibrary.shared
    let job: DownloadJob

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch job.status {
                case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                case .converting: EqualizerBars()
                default: ProgressView().controlSize(.small)
                }
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.title).lineLimit(1)
                switch job.status {
                case .failed: Text(job.error ?? L("Lỗi")).font(.caption).foregroundStyle(.orange).lineLimit(2)
                case .fetching: Text(L("Đang lấy thông tin…")).font(.caption).foregroundStyle(MZ.subtext)
                case .converting: Text(L("Đang hoàn tất…")).font(.caption).foregroundStyle(MZ.subtext)
                case .downloading: ScrubBar(value: job.progress, onCommit: { _ in }).allowsHitTesting(false)
                }
            }
            Spacer()
            if job.status == .failed {
                Button(L("Thử lại")) { lib.retry(job) }
                Button { lib.dismissJob(job.id) } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(MZ.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Trang online: playlist, mix, nghệ sĩ, thể loại

struct RemotePageView: View {
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var lib = MusicLibrary.shared
    @ObservedObject private var remote = RemoteArt.shared
    let target: HomeTarget
    @State private var page: YTM.Page?
    @State private var error: String?
    @State private var showAll = false
    @State private var width: CGFloat = 1000

    private var tracks: [Track] { page?.tracks ?? [] }
    private var context: (key: String, title: String) { (target.key, page?.title ?? target.title) }
    private var isPlayingHere: Bool { player.contextKey == target.key && player.current != nil }
    @ObservedObject private var artists = ArtistInfoStore.shared

    private var art: String? {
        if case .artist(let name) = target, let pic = artists.info(name)?.picture { return pic }
        return page?.art ?? tracks.first?.artworkURL
    }

    private var tint: Color {
        if case .mix(let t) = target, let c = ArtColor.color(for: t) { return c }
        return ArtColor.color(url: art) ?? MZ.hex(0x535353)
    }

    private func playAll() {
        if isPlayingHere { player.toggle() } else { player.play(tracks, context: context) }
    }

    var body: some View {
        PageScroll(tint: tint, title: page?.title ?? target.title, isPlaying: isPlayingHere && player.isPlaying, onPlay: playAll) {
            header
            actions
            VStack(alignment: .leading, spacing: 0) {
                if let error {
                    Text(error).foregroundStyle(MZ.subtext).frame(maxWidth: .infinity).padding(40)
                } else if page == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                } else if target.isArtist {
                    Text(L("Phổ biến")).font(.system(size: 24, weight: .bold)).padding(.bottom, 12)
                    let shown = showAll ? tracks : Array(tracks.prefix(5))
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, t in
                        TrackRow(number: i + 1, track: t, queue: tracks, context: context)
                    }
                    if tracks.count > 5 {
                        ShowAllButton(expanded: showAll) { withAnimation(Brand.spring) { showAll.toggle() } }
                            .padding(.leading, 16).padding(.top, 12)
                    }
                } else {
                    TrackTableHeader(showSource: width > 760, sourceTitle: L("Kho nhạc"))
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                            TrackRow(number: i + 1, track: t, queue: tracks, context: context, showSource: width > 760)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(WidthReader(width: $width))
        .task(id: target) {
            page = nil
            error = nil
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

    private var header: some View {
        let compact = width < 760
        let size: CGFloat = compact ? 160 : 232
        return PageHeader(tint: tint, kind: kindLabel, title: page?.title ?? target.title, compact: compact) {
            Group {
                if case .mix(let t) = target {
                    ArtworkView(track: t, size: size, radius: 6)
                } else {
                    RemoteImage(url: art, placeholder: target.isArtist ? "person.fill" : "music.note.list")
                        .frame(width: size, height: size)
                        .clipShape(target.isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
                }
            }
        } meta: {
            if let page {
                Text("Muzify").fontWeight(.bold)
                Text(L("•\(page.subtitle.isEmpty ? "" : " \(page.subtitle) •") \(page.tracks.count) bài hát"))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            } else {
                Text(L("Đang tải…")).foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 24) {
            PlayButton(isPlaying: isPlayingHere && player.isPlaying, loading: isPlayingHere && player.isResolving, action: playAll)
                .disabled(tracks.isEmpty)
                .opacity(tracks.isEmpty ? 0.5 : 1)
            IconButton(symbol: "shuffle", active: player.shuffle, size: 26, help: L("Phát ngẫu nhiên")) { player.shuffle.toggle() }
            if case .artist(let name) = target {
                OutlineButton(title: lib.isFollowing(name) ? L("Đang theo dõi") : L("Theo dõi")) {
                    let was = lib.isFollowing(name)
                    lib.toggleFollow(name, art: art)
                    UIState.shared.show(toast: was ? L("Đã xoá khỏi Thư viện") : L("Đã thêm vào Thư viện"))
                }
            } else {
                IconButton(symbol: "plus.circle", size: 26, help: L("Lưu vào Thư viện"), dot: false) {
                    let id = lib.savePlaylist(name: page?.title ?? target.title, tracks: tracks)
                    UIState.shared.show(toast: L("Đã lưu vào Thư viện"))
                    Router.shared.go(.playlist(id))
                }
                .disabled(tracks.isEmpty)
            }
            Menu {
                Button(L("Thêm vào danh sách chờ"), systemImage: "text.badge.plus") { UIState.shared.addToQueue(tracks) }
                Button(L("Thích tất cả"), systemImage: "heart") {
                    tracks.forEach { lib.setLiked($0, true) }
                    UIState.shared.show(toast: L("Đã thêm \(tracks.count) bài vào Bài hát đã thích"))
                }
                if let first = tracks.first {
                    Button(L("Mix tương tự"), systemImage: "dot.radiowaves.left.and.right") { Router.shared.go(.remote(.mix(first))) }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 24, weight: .bold)).foregroundStyle(MZ.subtext)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(tracks.isEmpty)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(LinearGradient(colors: [tint.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom))
    }

    private var kindLabel: String {
        switch target {
        case .playlist: "Playlist"
        case .mix: L("Mix dành cho bạn")
        case .artist: L("Nghệ sĩ##một người")
        case .genre: L("Thể loại")
        }
    }
}

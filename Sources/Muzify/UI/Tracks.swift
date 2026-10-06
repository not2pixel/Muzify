import SwiftUI

// MARK: - Nút thích (⊕ → ✓ xanh, như Spotify hiện tại)

struct LikeButton: View {
    @ObservedObject private var lib = MusicLibrary.shared
    let track: Track
    var size: CGFloat = 16
    @State private var hovering = false

    var body: some View {
        let liked = lib.isLiked(track)
        let locked = lib.libraryIndex(of: track).map { lib.tracks[$0].isLocalFile } ?? false
        Button { UIState.shared.toggleLike(track) } label: {
            Image(systemName: liked ? "checkmark.circle.fill" : "plus.circle")
                .font(.system(size: size, weight: liked ? .regular : .medium))
                .symbolRenderingMode(liked ? .palette : .monochrome)
                .foregroundStyle(liked ? AnyShapeStyle(.black) : AnyShapeStyle(hovering ? MZ.text : MZ.subtext),
                                 liked ? AnyShapeStyle(hovering ? Brand.accentHover : Brand.accent) : AnyShapeStyle(.clear))
                .scaleEffect(hovering ? 1.06 : 1)
                .contentTransition(.symbolEffect(.replace))
        }
        .onHover { hovering = $0 }
        .buttonStyle(PressScaleStyle(scale: 0.8))
        .disabled(locked)
        .help(locked ? L("Tệp trên máy") : liked ? L("Xoá khỏi Bài hát đã thích") : L("Lưu vào Bài hát đã thích"))
    }
}

/// Biểu tượng trạng thái tải xuống nhỏ cạnh tên nghệ sĩ.
struct DownloadBadge: View {
    @ObservedObject private var lib = MusicLibrary.shared
    let track: Track

    var body: some View {
        if lib.isDownloading(track) {
            ProgressView().controlSize(.mini).frame(width: 12, height: 12)
        } else if lib.isDownloaded(track) {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 11)).foregroundStyle(Brand.accent)
        }
    }
}

// MARK: - Menu bài hát (chuột phải / nút …)

struct TrackMenu: View {
    @ObservedObject private var lib = MusicLibrary.shared
    let track: Track
    let queue: [Track]
    var context: (key: String, title: String)?
    var playlistID: UUID?

    var body: some View {
        let ui = UIState.shared
        let liked = lib.isLiked(track)
        let local = lib.libraryIndex(of: track).map { lib.tracks[$0].isLocalFile } ?? false

        Button(L("Phát"), systemImage: "play.fill") { MusicPlayer.shared.play(queue, startAt: track.id, context: context) }
        Button(L("Phát tiếp theo"), systemImage: "text.line.first.and.arrowtriangle.forward") { ui.playNext(track) }
        Button(L("Thêm vào danh sách chờ"), systemImage: "text.badge.plus") { ui.addToQueue([track]) }
        Divider()
        Menu(L("Thêm vào playlist")) {
            Button(L("Playlist mới"), systemImage: "plus") { ui.newPlaylist(with: [track]) }
            Divider()
            ForEach(lib.playlists) { p in
                Button(p.name) { ui.add([track], to: p) }
            }
        }
        if let playlistID, let id = lib.libraryIndex(of: track).map({ lib.tracks[$0].id }) {
            Button(L("Xoá khỏi playlist này"), systemImage: "minus.circle") { lib.remove(id, from: playlistID) }
        }
        if !local {
            Button(liked ? L("Xoá khỏi Bài hát đã thích") : L("Lưu vào Bài hát đã thích"),
                   systemImage: liked ? "heart.slash" : "heart") { ui.toggleLike(track) }
        }
        if lib.isDownloaded(track) {
            if !local { Button(L("Xoá bản tải xuống"), systemImage: "arrow.down.circle.dotted") { lib.removeDownload(track) } }
        } else {
            Button(L("Tải xuống"), systemImage: "arrow.down.circle") { ui.download(track) }
        }
        Divider()
        if track.artist != L("Không rõ") {
            Button(L("Chuyển tới nghệ sĩ"), systemImage: "person") { ui.openArtist(LyricsStore.searchTerms(for: track).artist) }
        }
        Button(L("Bắt đầu mix từ bài này"), systemImage: "dot.radiowaves.left.and.right") { Router.shared.go(.remote(.mix(track))) }
        if let s = track.source, let url = URL(string: s) {
            Button(L("Mở trên \(track.catalog ?? "web")"), systemImage: "safari") { Platform.open(url) }
            Button(L("Sao chép link bài hát"), systemImage: "link") {
                Platform.copy(s)
                ui.show(toast: L("Đã sao chép link"))
            }
        }
        if local, let t = lib.libraryIndex(of: track).map({ lib.tracks[$0] }) {
            Divider()
            Button(L("Sửa tên / nghệ sĩ…"), systemImage: "pencil") { ui.editing = t }
            Button(L("Xoá khỏi Muzify"), systemImage: "trash", role: .destructive) { lib.delete(t.id) }
        }
    }
}

// MARK: - Hàng bài hát (danh sách kiểu bảng)

struct TrackRow: View {
    @ObservedObject private var lib = MusicLibrary.shared
    @ObservedObject private var player = MusicPlayer.shared
    let number: Int?
    let track: Track
    let queue: [Track]
    var context: (key: String, title: String)?
    var playlistID: UUID?
    var showSource = false
    var showDate = false
    /// Nhãn nguồn nhỏ cạnh tên nghệ sĩ (kết quả tìm kiếm gộp nhiều nguồn).
    var showBadge = false
    var onPlay: (() -> Void)?
    @State private var hovering = false

    private var badge: String {
        if lib.libraryIndex(of: track) != nil { return L("Thư viện##nhãn") }
        switch track.catalog {
        case "YouTube Music": return "YT Music"
        case let c?: return c
        default: return L("Máy")
        }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = .app
        f.unitsStyle = .full
        return f
    }()

    private var added: String {
        Date().timeIntervalSince(track.addedAt) < 7 * 86_400
            ? Self.relative.localizedString(for: track.addedAt, relativeTo: .now)
            : track.addedAt.formatted(.dateTime.day().month(.abbreviated).year().locale(.app))
    }

    private func play() {
        onPlay?()
        MusicPlayer.shared.play(queue, startAt: track.id, context: context)
    }

    var body: some View {
        let isCurrent = player.isCurrent(track)
        let liked = lib.isLiked(track)
        HStack(spacing: 16) {
            if let number {
                ZStack {
                    if hovering {
                        Button { isCurrent ? player.toggle() : play() } label: {
                            Image(systemName: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(MZ.text)
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.85))
                    } else if isCurrent && player.isPlaying {
                        EqualizerBars()
                    } else {
                        Text("\(number)")
                            .font(.system(size: 15))
                            .monospacedDigit()
                            .foregroundStyle(isCurrent ? Brand.accent : MZ.subtext)
                    }
                }
                .frame(width: 24, alignment: .trailing)
            }

            HStack(spacing: 12) {
                ZStack {
                    ArtworkView(track: track, size: 40)
                    if number == nil && (hovering || (isCurrent && player.isPlaying)) {
                        Color.black.opacity(0.5).clipShape(RoundedRectangle(cornerRadius: 4))
                        Image(systemName: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 40, height: 40)
                .onTapGesture { if number == nil { isCurrent ? player.toggle() : play() } }

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 15))
                        .lineLimit(1)
                        .foregroundStyle(isCurrent ? Brand.accent : MZ.text)
                    HStack(spacing: 5) {
                        if showBadge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(MZ.panel)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(MZ.subtext, in: RoundedRectangle(cornerRadius: 2))
                        }
                        DownloadBadge(track: track)
                        ArtistLink(name: track.artist, hovering: hovering)
                    }
                }
            }
            Spacer(minLength: 8)
            if showSource {
                Text(track.catalog ?? track.sourceHost ?? L("Tệp trên máy")).frame(width: 130, alignment: .leading)
            }
            if showDate {
                Text(added).frame(width: 120, alignment: .leading)
            }
            LikeButton(track: track)
                .opacity(hovering || liked ? 1 : 0)
                .frame(width: 24)
            Text(track.duration > 0 ? formatTime(track.duration) : "")
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
            Menu {
                TrackMenu(track: track, queue: queue, context: context, playlistID: playlistID)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(MZ.subtext)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering ? 1 : 0)
            .help(L("Tuỳ chọn khác cho \(track.title)"))
        }
        .font(.system(size: 13))
        .foregroundStyle(MZ.subtext)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(hovering ? MZ.hover : .clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: play)
        .draggable(track.id.uuidString)
        .contextMenu { TrackMenu(track: track, queue: queue, context: context, playlistID: playlistID) }
    }
}

/// Tên nghệ sĩ bấm được (gạch chân khi rê chuột) → trang nghệ sĩ.
struct ArtistLink: View {
    let name: String
    var hovering = false
    var size: CGFloat = 13
    @State private var over = false

    var body: some View {
        Text(name)
            .font(.system(size: size))
            .lineLimit(1)
            .foregroundStyle(hovering || over ? MZ.text : MZ.subtext)
            .underline(over)
            .onHover { over = $0 }
            .onTapGesture { UIState.shared.openArtist(LyricsStore.searchTerms(for: Track(title: "", artist: name, file: "")).artist) }
    }
}

/// Tiêu đề cột của bảng bài hát.
struct TrackTableHeader: View {
    var numbered = true
    var showSource = false
    var showDate = false
    var sourceTitle = L("Nguồn")

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                if numbered { Text("#").frame(width: 24, alignment: .trailing) }
                Text(L("Tiêu đề"))
                Spacer()
                if showSource { Text(sourceTitle).frame(width: 130, alignment: .leading) }
                if showDate { Text(L("Ngày thêm")).frame(width: 120, alignment: .leading) }
                Color.clear.frame(width: 24)
                Image(systemName: "clock").frame(width: 48, alignment: .trailing)
                Color.clear.frame(width: 18)
            }
            .font(.system(size: 13))
            .foregroundStyle(MZ.subtext)
            .padding(.horizontal, 16)
            Rectangle().fill(MZ.divider).frame(height: 1)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Thẻ (bài hát / playlist / nghệ sĩ) kiểu Spotify

/// Rê chuột nền sáng lên + nút Play trượt lên.
struct MediaCard<Cover: View>: View {
    let title: String
    let subtitle: String
    var round = false
    var playing = false
    var width: CGFloat = 176
    @ViewBuilder let cover: Cover
    let onOpen: () -> Void
    var onPlay: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        let side = width - 20
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                cover
                    .frame(width: side, height: side)
                    .clipShape(round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous)))
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
                if let onPlay {
                    PlayButton(isPlaying: playing, size: 46, action: onPlay)
                        .padding(8)
                        .opacity(hovering || playing ? 1 : 0)
                        .offset(y: hovering || playing ? 0 : 8)
                }
            }
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: side, alignment: .leading)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(MZ.subtext)
                .lineLimit(2)
                .frame(maxWidth: side, alignment: .leading)
        }
        .padding(10)
        .frame(width: width, alignment: .topLeading)
        .background(hovering ? MZ.elevated : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { hovering = h } }
        .onTapGesture(perform: onOpen)
    }
}

/// Ô bài hát nhỏ (lưới "Gợi ý cho bạn").
struct SongTile: View {
    @ObservedObject private var player = MusicPlayer.shared
    let track: Track
    let queue: [Track]
    var context: (key: String, title: String)?
    @State private var hovering = false

    var body: some View {
        let isCurrent = player.isCurrent(track)
        HStack(spacing: 10) {
            ZStack {
                ArtworkView(track: track, size: 48)
                if hovering || (isCurrent && player.isPlaying) {
                    Color.black.opacity(0.45).clipShape(RoundedRectangle(cornerRadius: 4))
                    Image(systemName: isCurrent && player.isPlaying ? "pause.fill" : "play.fill").foregroundStyle(.white)
                }
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title).font(.system(size: 14)).lineLimit(1)
                    .foregroundStyle(isCurrent ? Brand.accent : MZ.text)
                ArtistLink(name: track.artist, hovering: hovering, size: 12)
            }
            Spacer(minLength: 0)
            LikeButton(track: track, size: 14).opacity(hovering ? 1 : 0)
        }
        .padding(6)
        .padding(.trailing, 6)
        .background(hovering ? MZ.hover : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { isCurrent ? player.toggle() : player.play(queue, startAt: track.id, context: context) }
        .draggable(track.id.uuidString)
        .contextMenu { TrackMenu(track: track, queue: queue, context: context) }
    }
}

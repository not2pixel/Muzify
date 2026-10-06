import SwiftUI

// MARK: - Muzify cho iPhone / iPad

@main
struct MuzifyMobileApp: App {
    var body: some Scene {
        WindowGroup {
            MobileRoot()
                .preferredColorScheme(.dark)
                .tint(Brand.accent)
        }
    }
}

/// Điều hướng: mỗi tab (iPhone) / mục bên trái (iPad) có một ngăn trang riêng.
@MainActor
final class MobileNav: ObservableObject {
    static let shared = MobileNav()
    enum Tab: Hashable { case home, search, library }

    @Published var tab: Tab = .home
    @Published var home: [Route] = []
    @Published var search: [Route] = []
    @Published var library: [Route] = []
    /// iPad: mục đang chọn ở cột bên.
    @Published var padRoot: Route? = .home
    @Published var pad: [Route] = []
    var isPad = false

    func push(_ r: Route) {
        UIState.shared.nowPlayingOpen = false
        if isPad { pad.append(r); return }
        switch tab {
        case .home: home.append(r)
        case .search: search.append(r)
        case .library: library.append(r)
        }
    }

    /// Bấm lại tab đang mở → về đầu.
    func reselect(_ t: Tab) {
        if tab == t {
            switch t {
            case .home: home = []
            case .search: search = []
            case .library: library = []
            }
        }
        tab = t
    }
}

struct MobileRoot: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject private var ui = UIState.shared
    @ObservedObject private var lib = MusicLibrary.shared
    @ObservedObject private var player = MusicPlayer.shared

    var body: some View {
        Group {
            // MUZIFY_LAYOUT=phone|pad: ép bố cục khi xem thử (chỉ dùng lúc phát triển).
            switch ProcessInfo.processInfo.environment["MUZIFY_LAYOUT"] ?? (sizeClass == .regular ? "pad" : "phone") {
            case "pad": PadLayout()
            default: PhoneLayout()
            }
        }
        .background(MZ.base)
        .overlay(alignment: .bottom) {
            if let text = ui.toast {
                Text(text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(MZ.hex(0x2E77D0), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 130)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .fullCover(isPresented: $ui.nowPlayingOpen) { NowPlayingScreen() }
        .sheet(item: $ui.renaming) { RenameSheet(playlist: $0) }
        .alert("Muzify", isPresented: Binding(get: { lib.message != nil }, set: { if !$0 { lib.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lib.message ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .skippedNonMusic)) { _ in
            ui.show(toast: L("Đã bỏ qua đoạn không phải nhạc"))
        }
        .onAppear {
            MobileNav.shared.isPad = sizeClass == .regular
            Router.shared.handler = { MobileNav.shared.push($0) }
        }
        .onChange(of: sizeClass) { _, s in MobileNav.shared.isPad = s == .regular }
    }
}

// MARK: - iPhone: 3 tab + mini player

private struct PhoneLayout: View {
    @ObservedObject private var nav = MobileNav.shared

    var body: some View {
        TabView(selection: Binding(get: { nav.tab }, set: { nav.reselect($0) })) {
            NavigationStack(path: $nav.home) {
                HomeScreen().routes()
            }
            .withMiniPlayer()
            .tabItem { Label(L("Trang chủ"), systemImage: "house.fill") }
            .tag(MobileNav.Tab.home)

            NavigationStack(path: $nav.search) {
                SearchScreen().routes()
            }
            .withMiniPlayer()
            .tabItem { Label(L("Tìm kiếm"), systemImage: "magnifyingglass") }
            .tag(MobileNav.Tab.search)

            NavigationStack(path: $nav.library) {
                LibraryScreen().routes()
            }
            .withMiniPlayer()
            .tabItem { Label(L("Thư viện"), systemImage: "books.vertical.fill") }
            .tag(MobileNav.Tab.library)
        }
        .darkBars()
    }
}

// MARK: - iPad: cột bên trái kiểu Spotify + mini player dưới cùng

private struct PadLayout: View {
    @ObservedObject private var nav = MobileNav.shared
    @ObservedObject private var lib = MusicLibrary.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $nav.padRoot) {
                Section {
                    Label(L("Trang chủ"), systemImage: "house.fill").tag(Route.home)
                    Label(L("Tìm kiếm"), systemImage: "magnifyingglass").tag(Route.search)
                    Label { Text(L("Bài hát đã thích")) } icon: { LikedCover(size: 22) }.tag(Route.liked)
                }
                if !lib.playlists.isEmpty {
                    Section(L("Playlist")) {
                        ForEach(lib.playlists) { p in
                            Label { Text(p.name).lineLimit(1) } icon: { PlaylistCover(playlist: p, size: 26) }
                                .tag(Route.playlist(p.id))
                        }
                    }
                }
                if !lib.artists.isEmpty {
                    Section(L("Nghệ sĩ")) {
                        ForEach(lib.artists) { a in
                            Label { Text(a.name).lineLimit(1) } icon: { ArtistAvatar(artist: a, size: 26) }
                                .tag(Route.remote(.artist(a.name)))
                        }
                    }
                }
            }
            .navigationTitle("Muzify")
            .toolbar {
                ToolbarItem { NewPlaylistButton() }
            }
        } detail: {
            NavigationStack(path: $nav.pad) {
                RouteScreen(route: nav.padRoot ?? .home).routes()
            }
            .id(nav.padRoot)
        }
        .onChange(of: nav.padRoot) { nav.pad = [] }
        .withMiniPlayer()
        .darkBars()
    }
}

extension View {
    /// Gắn mọi trang có thể mở (playlist, nghệ sĩ…) vào ngăn điều hướng.
    func routes() -> some View {
        navigationDestination(for: Route.self) { RouteScreen(route: $0) }
    }

    /// Mini player nằm trên thanh tab / đáy màn hình.
    func withMiniPlayer() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerBar() }
    }
}

struct RouteScreen: View {
    let route: Route
    var body: some View {
        switch route {
        case .home: HomeScreen()
        case .search: SearchScreen()
        case .liked: CollectionScreen(playlistID: nil)
        case .playlist(let id): CollectionScreen(playlistID: id)
        case .remote(let t): RemoteScreen(target: t)
        }
    }
}

// MARK: - Mini player

struct MiniPlayerBar: View {
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var remote = RemoteArt.shared

    var body: some View {
        if let t = player.current {
            let tint = ArtColor.color(for: t) ?? MZ.hex(0x404040)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    ArtworkView(track: t, size: 40, radius: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(t.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    LikeButton(track: t, size: 22)
                    Button {
                        haptic()
                        player.toggle()
                    } label: {
                        Group {
                            if player.isResolving || (player.isBuffering && player.isPlaying) { Spinner(color: .white, size: 18) }
                            else { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 22)) }
                        }
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                GeometryReader { g in
                    Capsule().fill(.white.opacity(0.2))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white).frame(width: g.size.width * (player.duration > 0 ? min(player.time / player.duration, 1) : 0))
                        }
                }
                .frame(height: 2)
                .padding(.horizontal, 8)
            }
            .background(tint.opacity(0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture { UIState.shared.nowPlayingOpen = true }
            .gesture(DragGesture(minimumDistance: 20).onEnded { g in
                if g.translation.height < -30 { UIState.shared.nowPlayingOpen = true }
                else if g.translation.width < -60 { player.next() }
                else if g.translation.width > 60 { player.previous() }
            })
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Đổi tên playlist

private struct RenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Thêm tên"), text: $name)
            }
            .navigationTitle(L("Sửa thông tin chi tiết"))
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Huỷ")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Lưu")) {
                        MusicLibrary.shared.renamePlaylist(playlist.id, to: name)
                        dismiss()
                    }
                    .disabled(name.trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { name = playlist.name }
    }
}

struct NewPlaylistButton: View {
    var body: some View {
        Button {
            let lib = MusicLibrary.shared
            let id = lib.newPlaylist()
            UIState.shared.renaming = lib.playlists.first { $0.id == id }
            MobileNav.shared.push(.playlist(id))
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel(L("Tạo playlist"))
    }
}

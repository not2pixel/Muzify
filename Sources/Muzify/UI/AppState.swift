import SwiftUI

// MARK: - Điều hướng (có Quay lại / Tiến tới như trình duyệt)

enum Route: Hashable {
    case home, search, liked
    case playlist(UUID)
    case remote(HomeTarget)
}

@MainActor
final class Router: ObservableObject {
    static let shared = Router()
    @Published private(set) var history: [Route] = [.home]
    @Published private(set) var position = 0

    var current: Route { history[position] }
    var canGoBack: Bool { position > 0 }
    var canGoForward: Bool { position + 1 < history.count }

    /// iPhone/iPad: đẩy trang vào ngăn điều hướng hiện tại thay cho lịch sử kiểu Mac.
    var handler: ((Route) -> Void)?

    func go(_ r: Route) {
        if let handler { handler(r); return }
        UIState.shared.showLyrics = false
        guard r != current else { return }
        history = Array(history.prefix(position + 1)) + [r]
        if history.count > 60 { history.removeFirst(history.count - 60) }
        position = history.count - 1
    }

    func back() {
        UIState.shared.showLyrics = false
        if canGoBack { position -= 1 }
    }

    func forward() {
        UIState.shared.showLyrics = false
        if canGoForward { position += 1 }
    }

    /// Trang không còn tồn tại (playlist bị xoá) → bỏ khỏi lịch sử.
    func forget(_ r: Route) {
        let wasCurrent = current == r
        let cur = current
        history.removeAll { $0 == r }
        if history.isEmpty { history = [.home] }
        position = wasCurrent ? history.count - 1 : (history.lastIndex(of: cur) ?? history.count - 1)
    }
}

// MARK: - Trạng thái giao diện

enum RightPanel: String { case none, nowPlaying, queue }

@MainActor
final class UIState: ObservableObject {
    static let shared = UIState()
    private let d = UserDefaults.standard

    @Published var rightPanel: RightPanel { didSet { d.set(rightPanel.rawValue, forKey: "rightPanel") } }
    @Published var libraryWide: Bool { didSet { d.set(libraryWide, forKey: "libraryWide") } }
    @Published var showLyrics = false
    /// iPhone/iPad: màn Đang phát toàn màn hình.
    @Published var nowPlayingOpen = false
    @Published var fullScreen = false
    @Published var renaming: Playlist?
    @Published var editing: Track?
    @Published private(set) var toast: String?
    private var toastTask: Task<Void, Never>?

    private init() {
        rightPanel = RightPanel(rawValue: d.string(forKey: "rightPanel") ?? "") ?? .nowPlaying
        libraryWide = d.object(forKey: "libraryWide") as? Bool ?? true
    }

    func toggle(_ p: RightPanel) {
        withAnimation(Brand.spring) { rightPanel = rightPanel == p ? .none : p }
    }

    func toggleLyrics() {
        guard MusicPlayer.shared.current != nil else { return }
        withAnimation(Brand.spring) { showLyrics.toggle() }
    }

    /// Thông báo nhỏ phía trên thanh phát ("Đã thêm vào Bài hát đã thích"…).
    func show(toast text: String) {
        toastTask?.cancel()
        withAnimation(Brand.spring) { toast = text }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(Brand.spring) { toast = nil }
        }
    }

    // MARK: Thao tác chung (kèm thông báo)

    func toggleLike(_ t: Track) {
        let lib = MusicLibrary.shared
        let was = lib.isLiked(t)
        lib.toggleLike(t)
        show(toast: was ? L("Đã xoá khỏi Bài hát đã thích") : L("Đã thêm vào Bài hát đã thích"))
    }

    func add(_ list: [Track], to p: Playlist) {
        MusicLibrary.shared.add(list, to: p.id)
        show(toast: L("Đã thêm vào \(p.name)"))
    }

    func newPlaylist(with list: [Track] = []) {
        let lib = MusicLibrary.shared
        let id = lib.newPlaylist(list.count == 1 ? list[0].title : nil)
        if !list.isEmpty { lib.add(list, to: id) }
        Router.shared.go(.playlist(id))
        renaming = lib.playlists.first { $0.id == id }
    }

    func deletePlaylist(_ id: UUID) {
        MusicLibrary.shared.deletePlaylist(id)
        Router.shared.forget(.playlist(id))
        show(toast: L("Đã xoá playlist"))
    }

    func playNext(_ t: Track) {
        MusicPlayer.shared.playNext(t)
        show(toast: L("Sẽ phát tiếp theo"))
    }

    func addToQueue(_ list: [Track]) {
        MusicPlayer.shared.addToQueue(list)
        show(toast: L("Đã thêm vào danh sách chờ"))
    }

    func download(_ t: Track) {
        MusicLibrary.shared.download(t)
        show(toast: L("Đang tải xuống “\(t.title)”"))
    }

    func openArtist(_ name: String) {
        guard !name.isEmpty, name != L("Không rõ") else { return }
        Router.shared.go(.remote(.artist(name)))
    }
}

// MARK: - Tìm kiếm

@MainActor
final class SearchModel: ObservableObject {
    static let shared = SearchModel()

    @Published var query = "" { didSet { if query != oldValue { schedule() } } }
    @Published private(set) var results: [Track] = []
    @Published private(set) var searching = false
    @Published private(set) var error: String?
    @Published private(set) var lastQuery = ""
    @Published private(set) var recent: [String] = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []
    private var task: Task<Void, Never>?

    private func schedule() {
        task?.cancel()
        let q = query.trimmed
        guard !q.isEmpty else {
            results = []
            lastQuery = ""
            error = nil
            searching = false
            return
        }
        if Router.shared.current != .search { Router.shared.go(.search) }
        guard !Catalog.looksLikeLink(q), MusicSettings.shared.provider != .off else { return }
        task = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await run(q)
        }
    }

    func submit() {
        let q = query.trimmed
        guard !q.isEmpty else { return }
        let lib = MusicLibrary.shared
        if Catalog.looksLikeLink(q) {
            lib.importLink(q)
            query = ""
            Router.shared.go(.liked)
            return
        }
        guard MusicSettings.shared.provider != .off else {
            lib.message = L("Bật kho nhạc online trong Cài đặt để tìm bài hát, hoặc dán link để tải.")
            return
        }
        remember(q)
        task?.cancel()
        Router.shared.go(.search)
        task = Task { await run(q) }
    }

    func search(_ q: String) {
        query = q
        submit()
    }

    func remember(_ q: String) {
        let q = q.trimmed
        guard !q.isEmpty else { return }
        recent.removeAll { $0.lowercased() == q.lowercased() }
        recent.insert(q, at: 0)
        if recent.count > 10 { recent.removeLast(recent.count - 10) }
        UserDefaults.standard.set(recent, forKey: "recentSearches")
    }

    func forget(_ q: String) {
        recent.removeAll { $0 == q }
        UserDefaults.standard.set(recent, forKey: "recentSearches")
    }

    private func run(_ q: String) async {
        lastQuery = q
        searching = true
        error = nil
        do {
            let found = try await Catalog.search(q)
            guard q == lastQuery, !Task.isCancelled else { return }
            MusicLibrary.shared.remember(found)
            results = found
        } catch {
            guard q == lastQuery, !Task.isCancelled else { return }
            results = []
            self.error = error.localizedDescription
        }
        searching = false
    }
}

// MARK: - Thể loại (trang Duyệt tìm)

struct Genre: Identifiable {
    let title: String
    let query: String
    let color: UInt32
    let symbol: String
    var id: String { title }

    static let all: [Genre] = [
        .init(title: L("Nhạc Việt"), query: "nhạc việt hot nhất", color: 0xE13300, symbol: "music.mic"),
        .init(title: "V-Pop", query: "vpop hits", color: 0x8D67AB, symbol: "star.fill"),
        .init(title: L("Rap Việt"), query: "rap việt", color: 0xBA5D07, symbol: "music.quarternote.3"),
        .init(title: "K-Pop", query: "kpop hits", color: 0xE8115B, symbol: "sparkles"),
        .init(title: "US-UK", query: "us uk top hits", color: 0x1E3264, symbol: "globe.americas.fill"),
        .init(title: "Lo-fi", query: "lofi chill beats", color: 0x477D95, symbol: "cloud.rain.fill"),
        .init(title: "Ballad", query: "ballad việt buồn", color: 0xB02897, symbol: "heart.fill"),
        .init(title: "EDM", query: "edm dance hits", color: 0x0D73EC, symbol: "waveform"),
        .init(title: "Indie", query: "indie việt", color: 0x608108, symbol: "leaf.fill"),
        .init(title: "Acoustic", query: "acoustic cover", color: 0x27856A, symbol: "guitars.fill"),
        .init(title: L("Nhạc Trịnh"), query: "nhạc trịnh công sơn", color: 0x503750, symbol: "moon.stars.fill"),
        .init(title: "Bolero", query: "bolero trữ tình", color: 0xAF2896, symbol: "music.note"),
        .init(title: L("Tập trung"), query: "focus music instrumental", color: 0x503750, symbol: "brain.head.profile"),
        .init(title: L("Ngủ ngon"), query: "sleep music piano", color: 0x1E3264, symbol: "bed.double.fill"),
        .init(title: L("Tình yêu"), query: "love songs", color: 0xE91429, symbol: "heart.circle.fill"),
        .init(title: L("Tiệc tùng"), query: "party hits", color: 0xD84000, symbol: "party.popper.fill"),
        .init(title: L("Tập luyện"), query: "workout music", color: 0x777777, symbol: "figure.run"),
        .init(title: "Anime", query: "anime songs", color: 0xE8115B, symbol: "tv.fill"),
        .init(title: "Piano", query: "piano instrumental", color: 0x7358FF, symbol: "pianokeys"),
        .init(title: "Jazz", query: "jazz", color: 0x8D67AB, symbol: "music.note.house.fill"),
        .init(title: "Rock", query: "rock", color: 0xE91429, symbol: "bolt.fill"),
        .init(title: L("Nhạc phim"), query: "nhạc phim ost", color: 0x148A08, symbol: "film.fill"),
    ]
}

import Foundation

// MARK: - YouTube Music (InnerTube) — tìm kiếm, trang chủ, bảng xếp hạng, playlist, bài tương tự

enum YTM {
    /// Bộ lọc tìm kiếm: chỉ "Bài hát".
    static let songsFilter = "EgWKAQIIAWoKEAkQBRAKEAMQBA=="

    static func call(_ endpoint: String, _ body: [String: Any], mobile: Bool = false) async throws -> Any {
        var req = URLRequest(url: URL(string: "https://music.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        req.setValue(Catalog.browserUA, forHTTPHeaderField: "User-Agent")
        var b = body
        // Client di động trả về lời bài hát có mốc thời gian (web chỉ có lời thường).
        b["context"] = ["client": mobile
            ? ["clientName": "ANDROID_MUSIC", "clientVersion": "7.21.50", "androidSdkVersion": 30, "hl": AppLanguage.current, "gl": "VN"] as [String: Any]
            : ["clientName": "WEB_REMIX", "clientVersion": "1.20241023.01.00", "hl": AppLanguage.current, "gl": "VN"]]
        req.httpBody = try JSONSerialization.data(withJSONObject: b)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: Đọc JSON

    static func all(_ key: String, in o: Any) -> [[String: Any]] {
        var out: [[String: Any]] = []
        func walk(_ o: Any) {
            if let d = o as? [String: Any] {
                if let v = d[key] as? [String: Any] { out.append(v) }
                d.values.forEach(walk)
            } else if let a = o as? [Any] { a.forEach(walk) }
        }
        walk(o)
        return out
    }

    static func runs(_ o: Any?) -> String {
        (((o as? [String: Any])?["runs"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined()
    }

    static func thumb(_ o: Any?, size: Int = 544) -> String? {
        var urls: [String] = []
        func walk(_ o: Any) {
            if let d = o as? [String: Any] {
                if let t = d["thumbnails"] as? [[String: Any]] { urls += t.compactMap { $0["url"] as? String } }
                d.values.forEach(walk)
            } else if let a = o as? [Any] { a.forEach(walk) }
        }
        walk(o ?? [:])
        guard var u = urls.last else { return nil }
        if let r = u.range(of: #"=w\d+-h\d+"#, options: .regularExpression) { u.replaceSubrange(r, with: "=w\(size)-h\(size)") }
        else if let r = u.range(of: #"/(hq|mq|sd)default\.jpg"#, options: .regularExpression) { u.replaceSubrange(r, with: "/hqdefault.jpg") }
        return u
    }

    static func seconds(_ s: String) -> Double {
        s.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }

    static func track(videoID id: String, title: String, artist: String, duration: Double, art: String?) -> Track {
        let page = "https://music.youtube.com/watch?v=\(id)"
        return Track(title: title, artist: artist.isEmpty ? L("Không rõ") : artist, duration: duration, file: "", artwork: nil,
                     source: page, remoteURL: "ytdlp:" + page, artworkURL: art, catalog: "YouTube Music")
    }

    /// Hàng bài hát (musicResponsiveListItemRenderer).
    static func song(row r: [String: Any]) -> Track? {
        let id = ((r["playlistItemData"] as? [String: Any])?["videoId"] as? String)
            ?? (all("watchEndpoint", in: r["flexColumns"] ?? []).first?["videoId"] as? String)
        guard let id else { return nil }
        let cols = (r["flexColumns"] as? [[String: Any]]) ?? []
        func col(_ i: Int) -> String {
            guard i < cols.count else { return "" }
            return runs((cols[i]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"])
        }
        let title = col(0)
        guard !title.isEmpty else { return nil }
        let meta = col(1).components(separatedBy: " • ")
        let fixed = ((r["fixedColumns"] as? [[String: Any]])?.first?["musicResponsiveListItemFixedColumnRenderer"] as? [String: Any])?["text"]
        let dur = runs(fixed).nilIfEmpty ?? meta.last { $0.range(of: #"^\d+(:\d{2})+$"#, options: .regularExpression) != nil }
        return track(videoID: id, title: title, artist: meta.first ?? "", duration: dur.map(seconds) ?? 0, art: thumb(r["thumbnail"]))
    }

    /// Bài trong danh sách "tiếp theo" (playlistPanelVideoRenderer).
    static func song(panel p: [String: Any]) -> Track? {
        guard let id = p["videoId"] as? String else { return nil }
        let byline = runs(p["longBylineText"]).components(separatedBy: " • ")
        return track(videoID: id, title: runs(p["title"]), artist: byline.first ?? "",
                     duration: seconds(runs(p["lengthText"])), art: thumb(p["thumbnail"]))
    }

    static func videoID(of t: Track) -> String? {
        guard let s = t.source, let u = URL(string: s) else { return nil }
        if let v = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value { return v }
        if u.host?.contains("youtu.be") == true { return u.pathComponents.dropFirst().first }
        return nil
    }

    // MARK: API

    /// Tìm bài hát.
    static func songs(of query: String) async throws -> [Track] {
        let obj = try await call("search", ["query": query, "params": songsFilter])
        return all("musicResponsiveListItemRenderer", in: obj).compactMap(song(row:))
    }

    /// Khoảng 50 bài cùng gu với một bài (giống "radio" / mix của Spotify).
    static func related(to t: Track) async throws -> [Track] {
        var id = videoID(of: t)
        if id == nil {
            // Bài trên máy / SoundCloud: tìm bài tương ứng trên YouTube Music trước.
            let terms = LyricsStore.searchTerms(for: t)
            id = try await songs(of: "\(terms.artist) \(terms.title)").first.flatMap(videoID(of:))
        }
        guard let id else { return [] }
        let obj = try await call("next", ["videoId": id, "playlistId": "RDAMVM\(id)", "isAudioOnly": true])
        var seen = Set<String>()
        return all("playlistPanelVideoRenderer", in: obj).compactMap(song(panel:)).filter { seen.insert($0.title + $0.artist).inserted }
    }

    // MARK: Lời bài hát

    struct Lyrics {
        /// (giây, dòng) nếu có mốc thời gian.
        var timed: [(Double, String)]?
        var plain: String?
        /// "Nguồn: LyricFind"…
        var credit: String?
    }

    /// Lời bài hát của một video trên YouTube Music: thử bản có mốc thời gian trước, rồi bản thường.
    static func lyrics(videoID: String) async throws -> Lyrics? {
        let next = try await call("next", ["videoId": videoID, "isAudioOnly": true])
        guard let browseID = all("browseEndpoint", in: next).lazy.compactMap({ $0["browseId"] as? String })
            .first(where: { $0.hasPrefix("MPLYt") }) else { return nil }

        if let mobile = try? await call("browse", ["browseId": browseID], mobile: true) {
            var timed: [(Double, String)] = []
            func walk(_ o: Any) {
                if let d = o as? [String: Any] {
                    if let line = d["lyricLine"] as? String,
                       let ms = (d["cueRange"] as? [String: Any])?["startTimeMilliseconds"] {
                        let v = (ms as? Double) ?? Double(ms as? String ?? "") ?? Double(ms as? Int ?? 0)
                        timed.append((v / 1000, line))
                    }
                    d.values.forEach(walk)
                } else if let a = o as? [Any] { a.forEach(walk) }
            }
            walk(mobile)
            if timed.count > 2 {
                let credit = all("lyricsData", in: mobile).first?["sourceMessage"] as? String
                return Lyrics(timed: timed.sorted { $0.0 < $1.0 }, plain: nil, credit: credit)
            }
        }

        let obj = try await call("browse", ["browseId": browseID])
        guard let shelf = all("musicDescriptionShelfRenderer", in: obj).first else { return nil }
        let text = runs(shelf["description"])
        guard !text.isEmpty else { return nil }
        return Lyrics(timed: nil, plain: text, credit: runs(shelf["footer"]).nilIfEmpty)
    }

    struct Page {
        var title: String
        var subtitle: String
        var art: String?
        var tracks: [Track]
    }

    static func playlist(_ browseID: String) async throws -> Page {
        let obj = try await call("browse", ["browseId": browseID])
        let header = all("musicResponsiveHeaderRenderer", in: obj).first ?? all("musicDetailHeaderRenderer", in: obj).first ?? [:]
        let rows = all("musicResponsiveListItemRenderer", in: obj).compactMap(song(row:))
        return Page(title: runs(header["title"]).nilIfEmpty ?? "Playlist",
                    subtitle: runs(header["subtitle"]).nilIfEmpty ?? runs(header["secondSubtitle"]),
                    art: thumb(header["thumbnail"]), tracks: rows)
    }
}

// MARK: - Nội dung mở được từ trang chủ / tìm kiếm

enum HomeTarget: Hashable {
    case playlist(id: String, title: String)
    case mix(Track)
    case artist(String)
    case genre(title: String, query: String)

    var title: String {
        switch self {
        case .playlist(_, let t): t
        case .mix(let t): "Mix \(LyricsStore.searchTerms(for: t).artist)"
        case .artist(let a): a
        case .genre(let t, _): t
        }
    }

    var key: String {
        switch self {
        case .playlist(let id, _): "pl:\(id)"
        case .mix(let t): "mix:\(t.source ?? t.id.uuidString)"
        case .artist(let a): "artist:\(a.lowercased())"
        case .genre(_, let q): "genre:\(q)"
        }
    }

    var isArtist: Bool { if case .artist = self { true } else { false } }

    func page() async throws -> YTM.Page {
        switch self {
        case .playlist(let id, _):
            return try await YTM.playlist(id)
        case .mix(let t):
            return YTM.Page(title: title, subtitle: L("Bắt đầu từ \(LyricsStore.searchTerms(for: t).title)"),
                            art: t.artworkURL, tracks: try await YTM.related(to: t))
        case .artist(let a):
            let found = try await YTM.songs(of: a)
            // Chỉ giữ bài của đúng nghệ sĩ (kết quả tìm kiếm có thể lẫn người khác).
            let own = found.filter { $0.artist.localizedCaseInsensitiveContains(a) }
            return YTM.Page(title: a, subtitle: L("Bài hát phổ biến"), art: (own.first ?? found.first)?.artworkURL,
                            tracks: own.count >= 3 ? own : found)
        case .genre(let t, let q):
            let list = try await YTM.songs(of: q)
            return YTM.Page(title: t, subtitle: L("Tuyển tập \(t)"), art: list.first?.artworkURL, tracks: list)
        }
    }
}

// MARK: - Mô hình trang chủ

struct HomeItem: Identifiable {
    enum Kind { case song(Track), open(HomeTarget) }
    let id = UUID()
    var title: String
    var subtitle: String
    var art: String?
    var localArt: Track?
    var kind: Kind
    var round = false
}

struct HomeShelf: Identifiable {
    enum Style { case cards, songs }
    let id = UUID()
    var title: String
    var subtitle: String?
    var style: Style = .cards
    var items: [HomeItem]
}

@MainActor
final class MusicHome: ObservableObject {
    static let shared = MusicHome()
    @Published private(set) var shelves: [HomeShelf] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var loadedAt: Date?

    /// Các phần của trang chủ — nguồn nào xong trước thì hiện trước (không đợi nguồn chậm).
    private var mixes: [HomeShelf] = []
    private var recommended: [HomeShelf] = []
    private var ytHome: [HomeShelf] = []
    private var ytCharts: [HomeShelf] = []
    private var charts: [HomeShelf] = []
    private var fresh: [HomeShelf] = []
    private var pending = 0

    private func publish() {
        shelves = mixes + recommended + ytHome + ytCharts + charts + fresh
        let all = shelves.flatMap(\.items).compactMap { if case .song(let t) = $0.kind { t } else { nil } }
        MusicLibrary.shared.remember(all)
    }

    private func finish() {
        pending -= 1
        publish()
        if pending <= 0 {
            loading = false
            loadedAt = .now
            if shelves.isEmpty { error = L("Không tải được gợi ý. Kiểm tra kết nối mạng.") }
        }
    }

    func load(force: Bool = false) {
        if !force, let t = loadedAt, Date().timeIntervalSince(t) < 1800, !shelves.isEmpty { return }
        guard !loading else { return }
        loading = true
        error = nil
        pending = 5
        let seeds = seedTracks()

        // Mix theo nghệ sĩ bạn hay nghe: có ngay, không cần mạng.
        mixes = seeds.isEmpty ? [] : [HomeShelf(title: L("Mix hàng ngày"), subtitle: L("Mix tự tạo theo nhạc bạn nghe"),
                                                items: seeds.prefix(8).map { s in
            let terms = LyricsStore.searchTerms(for: s)
            return HomeItem(title: "Mix \(terms.artist)", subtitle: L("\(terms.title) và những bài tương tự"),
                            art: s.artworkURL, localArt: s, kind: .open(.mix(s)))
        })]
        // Bảng xếp hạng lần trước (lưu trên máy) — hiện ngay, cập nhật ngầm.
        if charts.isEmpty { charts = Self.cachedCharts() }
        publish()

        Task {
            if let first = seeds.first, let rec = try? await YTM.related(to: first), rec.count > 1 {
                recommended = [HomeShelf(title: L("Gợi ý cho bạn"), subtitle: L("Dựa trên \(LyricsStore.searchTerms(for: first).title)"),
                                         style: .songs, items: rec.dropFirst().prefix(12).map(Self.songItem))]
            }
            finish()
        }
        Task {
            if let h = try? await YTM.call("browse", ["browseId": "FEmusic_home"]) { ytHome = Self.shelves(from: h) }
            finish()
        }
        Task {
            if let c = try? await YTM.call("browse", ["browseId": "FEmusic_charts", "formData": ["selectedValues": ["VN"]]]) {
                ytCharts = Self.shelves(from: c).map { s in
                    var s = s
                    if s.title.lowercased().contains("nghệ sĩ") || s.title.lowercased().contains("artist") { // l10n:skip
                        s.items = s.items.map { var i = $0; i.round = true; return i }
                    }
                    for chart in ["Bảng xếp hạng video", "Video charts"] { // l10n:skip
                        s.title = s.title.replacingOccurrences(of: chart, with: L("Thịnh hành tại Việt Nam"))
                    }
                    return s
                }
            }
            finish()
        }
        Task {
            if let f = try? await YTM.call("browse", ["browseId": "FEmusic_new_releases"]) {
                fresh = Self.shelves(from: f).map { var s = $0; s.title = L("Mới phát hành"); return s }
            }
            finish()
        }
        Task {
            async let vn = Charts.appleMusic()
            async let global = Charts.deezer()
            let top = await vn
            var world = await global
            var worldTitle = L("Top toàn cầu"), worldSub = L("Bảng xếp hạng Deezer")
            if world.isEmpty {
                // Deezer bị chặn ở một số nhà mạng → dùng bảng xếp hạng Apple Music Mỹ.
                world = await Charts.appleMusic(country: "us")
                worldTitle = L("Top Hoa Kỳ"); worldSub = L("Bảng xếp hạng Apple Music")
            }
            var fresh: [HomeShelf] = []
            if !top.isEmpty {
                fresh.append(HomeShelf(title: L("Top bài hát Việt Nam"), subtitle: L("Bảng xếp hạng Apple Music"), items: top.map(Self.songItem)))
            }
            if !world.isEmpty {
                fresh.append(HomeShelf(title: worldTitle, subtitle: worldSub, items: world.map(Self.songItem)))
            }
            if !fresh.isEmpty {
                charts = fresh
                Self.saveCharts(fresh)
            }
            finish()
        }
    }

    // MARK: Lưu bảng xếp hạng trên máy

    private struct ChartCache: Codable { var title: String; var subtitle: String?; var tracks: [Track] }
    private static var chartsURL: URL { MusicLibrary.shared.dir.appendingPathComponent("charts.json") }

    private static func cachedCharts() -> [HomeShelf] {
        guard let data = try? Data(contentsOf: chartsURL),
              let list = try? JSONDecoder().decode([ChartCache].self, from: data) else { return [] }
        return list.map { HomeShelf(title: $0.title, subtitle: $0.subtitle, items: $0.tracks.map(songItem)) }
    }

    private static func saveCharts(_ shelves: [HomeShelf]) {
        let list = shelves.map { s in
            ChartCache(title: s.title, subtitle: s.subtitle,
                       tracks: s.items.compactMap { if case .song(let t) = $0.kind { t } else { nil } })
        }
        if let data = try? JSONEncoder().encode(list) { try? data.write(to: chartsURL, options: .atomic) }
    }

    /// Bài gốc để gợi ý: nghe gần đây, rồi tới bài đã thích; mỗi nghệ sĩ một bài.
    private func seedTracks() -> [Track] {
        var seen = Set<String>()
        let pool = MusicPlayer.shared.history + MusicLibrary.shared.liked
        return pool.filter { seen.insert(LyricsStore.searchTerms(for: $0).artist.lowercased()).inserted }
    }

    private static func songItem(_ t: Track) -> HomeItem {
        HomeItem(title: t.title, subtitle: t.artist, art: t.artworkURL, kind: .song(t))
    }

    /// Các kệ ngang (musicCarouselShelfRenderer) của một trang YouTube Music.
    private static func shelves(from obj: Any) -> [HomeShelf] {
        YTM.all("musicCarouselShelfRenderer", in: obj).compactMap { shelf in
            let header = (shelf["header"] as? [String: Any])?["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any]
            let title = YTM.runs(header?["title"])
            let contents = shelf["contents"] as? [[String: Any]] ?? []
            var songs = 0
            let items: [HomeItem] = contents.compactMap { c in
                if let r = c["musicResponsiveListItemRenderer"] as? [String: Any] {
                    if let t = YTM.song(row: r) { songs += 1; return songItem(t) }
                    // Nghệ sĩ dạng hàng
                    let cols = (r["flexColumns"] as? [[String: Any]]) ?? []
                    let name = cols.first.map { YTM.runs(($0["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"]) } ?? ""
                    guard !name.isEmpty else { return nil }
                    let sub = cols.count > 1 ? YTM.runs((cols[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"]) : ""
                    return HomeItem(title: name, subtitle: sub.isEmpty ? L("Nghệ sĩ##một người") : sub, art: YTM.thumb(r["thumbnail"], size: 360),
                                    kind: .open(.artist(name)), round: true)
                }
                guard let r = c["musicTwoRowItemRenderer"] as? [String: Any] else { return nil }
                let name = YTM.runs(r["title"])
                let sub = YTM.runs(r["subtitle"])
                let art = YTM.thumb(r["thumbnailRenderer"])
                let nav = r["navigationEndpoint"] as? [String: Any] ?? [:]
                if let w = nav["watchEndpoint"] as? [String: Any], let vid = w["videoId"] as? String {
                    songs += 1
                    // Dòng phụ dạng "Bài hát • Nghệ sĩ • 1,2 Tr lượt xem" → lấy phần là tên nghệ sĩ
                    let skip = ["bài hát", "video", "đĩa đơn", "song", "single", "ep", "album"] // l10n:skip
                    let artist = sub.components(separatedBy: " • ").first {
                        let l = $0.lowercased()
                        return !skip.contains(l) && !l.contains("lượt") && !l.contains("view") // l10n:skip
                            && l.range(of: #"^\d{4}$"#, options: .regularExpression) == nil
                    } ?? sub
                    return songItem(YTM.track(videoID: vid, title: name, artist: artist, duration: 0, art: art))
                }
                if let b = nav["browseEndpoint"] as? [String: Any], let id = b["browseId"] as? String {
                    let type = ((b["browseEndpointContextSupportedConfigs"] as? [String: Any])?["browseEndpointContextMusicConfig"]
                        as? [String: Any])?["pageType"] as? String ?? ""
                    if type.contains("ARTIST") {
                        return HomeItem(title: name, subtitle: L("Nghệ sĩ##một người"), art: art, kind: .open(.artist(name)), round: true)
                    }
                    return HomeItem(title: name, subtitle: sub, art: art, kind: .open(.playlist(id: id, title: name)))
                }
                return nil
            }
            guard !items.isEmpty, !title.isEmpty else { return nil }
            let allSongs = songs == items.count && contents.first?["musicResponsiveListItemRenderer"] != nil
            return HomeShelf(title: title, style: allSongs ? .songs : .cards, items: items)
        }
    }
}

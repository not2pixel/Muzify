import Foundation

// MARK: - SponsorBlock: bỏ qua đoạn không phải nhạc (intro/outro MV, đoạn nói…)
// API công khai, miễn phí, không cần key: https://sponsor.ajay.app

actor SponsorBlock {
    static let shared = SponsorBlock()
    private var cache: [String: [ClosedRange<Double>]] = [:]

    /// Các đoạn "music_offtopic" của một video YouTube (rỗng nếu không có).
    func segments(videoID: String) async -> [ClosedRange<Double>] {
        if let c = cache[videoID] { return c }
        var c = URLComponents(string: "https://sponsor.ajay.app/api/skipSegments")!
        c.queryItems = [.init(name: "videoID", value: videoID), .init(name: "categories", value: #"["music_offtopic"]"#)]
        var req = URLRequest(url: c.url!)
        req.timeoutInterval = 10
        req.setValue("Muzify/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        var out: [ClosedRange<Double>] = []
        if let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
           let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            out = items.compactMap { i in
                guard let s = i["segment"] as? [Double], s.count == 2, s[1] - s[0] >= 1 else { return nil }
                return s[0]...s[1]
            }
        }
        cache[videoID] = out
        return out
    }
}

// MARK: - Thông tin nghệ sĩ: ảnh + người hâm mộ (Deezer) + tiểu sử, ảnh dự phòng (Wikipedia) — đều không cần key
// Lưu ý: Deezer bị nhà mạng Việt Nam chặn (DNS trả 127.0.0.1) → khi đó ảnh lấy từ Wikipedia, số người hâm mộ ẩn đi.

struct ArtistInfo: Equatable {
    var picture: String?
    var fans: Int?
    var bio: String?
    var wikiURL: String?
}

@MainActor
final class ArtistInfoStore: ObservableObject {
    static let shared = ArtistInfoStore()
    @Published private(set) var infos: [String: ArtistInfo] = [:]
    private var loading = Set<String>()

    /// Trả về ngay nếu đã có; chưa có thì tải nền rồi cập nhật giao diện.
    func info(_ name: String) -> ArtistInfo? {
        let key = name.lowercased()
        guard !key.isEmpty else { return nil }
        if let i = infos[key] { return i }
        guard !loading.contains(key) else { return nil }
        loading.insert(key)
        let lang = AppLanguage.current
        Task {
            async let deezer = Self.deezer(name)
            async let wiki = Self.wikipedia(name, lang: lang)
            let (d, w) = await (deezer, wiki)
            infos[key] = ArtistInfo(picture: d?.picture ?? w?.image, fans: d?.fans, bio: w?.bio, wikiURL: w?.url)
            loading.remove(key)
        }
        return nil
    }

    private nonisolated static func json(_ url: URL) async -> Any? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("Muzify/1.0 (macOS music player)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private nonisolated static func same(_ a: String, _ b: String) -> Bool {
        func n(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber } }
        return n(a) == n(b)
    }

    private nonisolated static func deezer(_ name: String) async -> (picture: String?, fans: Int?)? {
        var c = URLComponents(string: "https://api.deezer.com/search/artist")!
        c.queryItems = [.init(name: "q", value: name), .init(name: "limit", value: "5")]
        guard let obj = await json(c.url!) as? [String: Any], let list = obj["data"] as? [[String: Any]],
              let a = list.first(where: { same($0["name"] as? String ?? "", name) }) else { return nil }
        return (a["picture_xl"] as? String, a["nb_fan"] as? Int)
    }

    private nonisolated static func wikipedia(_ name: String, lang: String) async -> (bio: String, url: String?, image: String?)? {
        let hint = lang == "en" ? "singer" : "ca sĩ" // l10n:skip — từ khoá tìm kiếm
        var c = URLComponents(string: "https://\(lang).wikipedia.org/w/api.php")!
        c.queryItems = [.init(name: "action", value: "query"), .init(name: "list", value: "search"), .init(name: "format", value: "json"),
                        .init(name: "srlimit", value: "3"), .init(name: "srsearch", value: "\(name) \(hint)")]
        guard let obj = await json(c.url!) as? [String: Any],
              let hits = (obj["query"] as? [String: Any])?["search"] as? [[String: Any]] else { return nil }
        for hit in hits {
            guard let title = hit["title"] as? String,
                  let enc = title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let u = URL(string: "https://\(lang).wikipedia.org/api/rest_v1/page/summary/\(enc)"),
                  let s = await json(u) as? [String: Any], let text = s["extract"] as? String,
                  (s["type"] as? String) != "disambiguation",
                  text.localizedCaseInsensitiveContains(name.components(separatedBy: " ").first ?? name)
            else { continue }
            let url = ((s["content_urls"] as? [String: Any])?["desktop"] as? [String: Any])?["page"] as? String
            let image = ((s["originalimage"] as? [String: Any]) ?? (s["thumbnail"] as? [String: Any]))?["source"] as? String
            return (text, url, image)
        }
        return nil
    }
}

// MARK: - Bảng xếp hạng: Apple Music (theo quốc gia) và Deezer (toàn cầu) — không cần key
// Chỉ có thông tin bài; khi phát Muzify tìm bản tương ứng trên YouTube Music ("find:<nghệ sĩ> <tên bài>").

enum Charts {
    static func findTrack(title: String, artist: String, duration: Double = 0, art: String?, page: String?, catalog: String) -> Track {
        Track(title: title, artist: artist, duration: duration, file: "", artwork: nil, source: page,
              remoteURL: "find:\(artist) \(title)", artworkURL: art, catalog: catalog)
    }

    /// Tải nhanh hoặc bỏ (máy chủ bảng xếp hạng đôi khi rất chậm — không để trang chủ chờ).
    private static func data(_ url: URL) async -> Data? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        return try? await URLSession.shared.data(for: req).0
    }

    static func appleMusic(country: String = "vn", limit: Int = 50) async -> [Track] {
        guard let url = URL(string: "https://rss.applemarketingtools.com/api/v2/\(country)/music/most-played/\(limit)/songs.json"),
              let data = await data(url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = (obj["feed"] as? [String: Any])?["results"] as? [[String: Any]] else { return [] }
        return items.compactMap { i in
            guard let name = i["name"] as? String, let artist = i["artistName"] as? String else { return nil }
            let art = (i["artworkUrl100"] as? String)?.replacingOccurrences(of: "100x100", with: "600x600")
            return findTrack(title: name, artist: artist, art: art, page: i["url"] as? String, catalog: "Apple Music")
        }
    }

    static func deezer(limit: Int = 50) async -> [Track] {
        guard let url = URL(string: "https://api.deezer.com/chart/0/tracks?limit=\(limit)"),
              let data = await data(url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["data"] as? [[String: Any]] else { return [] }
        return items.compactMap { i in
            guard let title = i["title"] as? String, let artist = (i["artist"] as? [String: Any])?["name"] as? String else { return nil }
            return findTrack(title: title, artist: artist, duration: Double(i["duration"] as? Int ?? 0),
                             art: (i["album"] as? [String: Any])?["cover_xl"] as? String, page: i["link"] as? String, catalog: "Deezer")
        }
    }
}

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

// MARK: - Thông tin nghệ sĩ: lấy đúng từ trang nghệ sĩ trên YouTube Music
// (ảnh, mô tả, người nghe hằng tháng, người đăng ký, bài hát hàng đầu).

struct ArtistInfo: Equatable {
    var channelID: String
    var name: String
    /// Ảnh đại diện vuông (như ảnh tròn trên YouTube Music).
    var picture: String?
    /// Ảnh bìa ngang của trang nghệ sĩ.
    var banner: String?
    /// "9,29 Tr khán thính giả mỗi tháng" — nguyên văn từ YouTube.
    var listeners: String?
    var subscribers: String?
    var bio: String?
    var songs: [Track]
    /// Playlist "Xem tất cả" bài hát của nghệ sĩ.
    var allSongs: String?
    var url: String { "https://music.youtube.com/channel/\(channelID)" }
}

@MainActor
final class ArtistInfoStore: ObservableObject {
    static let shared = ArtistInfoStore()
    @Published private(set) var infos: [String: ArtistInfo] = [:]
    private var loading = Set<String>()

    /// Trả về ngay nếu đã có; chưa có thì tải nền rồi cập nhật giao diện.
    func info(_ name: String, channelID: String? = nil) -> ArtistInfo? {
        let key = name.lowercased()
        guard !key.isEmpty else { return nil }
        if let i = infos[key] { return i }
        guard !loading.contains(key) else { return nil }
        loading.insert(key)
        let cid = channelID ?? MusicLibrary.shared.artists.first { $0.id == key }?.channelID
        Task {
            if let i = try? await YTM.artist(name: name, channelID: cid) { infos[key] = i }
            loading.remove(key)
        }
        return nil
    }
}

extension YTM {
    /// Trang nghệ sĩ trên YouTube Music (tìm kênh theo tên nếu chưa biết ID kênh).
    static func artist(name: String, channelID: String? = nil) async throws -> ArtistInfo? {
        var cid = channelID
        var avatar: String?
        if cid == nil || avatar == nil {
            let found = try await call("search", ["query": name, "params": "EgWKAQIgAWoKEAkQBRAKEAMQBA=="]) // bộ lọc: Nghệ sĩ
            func norm(_ s: String) -> String {
                s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
            }
            var candidates: [(id: String, name: String, art: String?)] = []
            for r in all("musicResponsiveListItemRenderer", in: found) {
                guard let id = all("browseEndpoint", in: r).first?["browseId"] as? String, id.hasPrefix("UC") else { continue }
                let cols = (r["flexColumns"] as? [[String: Any]]) ?? []
                let n = cols.first.map { runs(($0["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"]) } ?? ""
                candidates.append((id, n, thumb(r["thumbnail"], size: 544)))
            }
            let pick = (cid.flatMap { c in candidates.first { $0.id == c } })
                ?? candidates.first { norm($0.name) == norm(name) } ?? candidates.first
            cid = cid ?? pick?.id
            avatar = pick?.id == cid ? pick?.art : nil
        }
        guard let cid else { return nil }
        let page = try await call("browse", ["browseId": cid])
        guard let h = all("musicImmersiveHeaderRenderer", in: page).first ?? all("musicVisualHeaderRenderer", in: page).first
        else { return nil }
        var bannerURLs: [String] = []
        if let list = ((h["thumbnail"] as? [String: Any]).flatMap { all("musicThumbnailRenderer", in: $0).first ?? $0 })?["thumbnail"] as? [String: Any],
           let ts = list["thumbnails"] as? [[String: Any]] {
            bannerURLs = ts.compactMap { $0["url"] as? String }
        }
        let shelf = all("musicShelfRenderer", in: page).first
        let songs = shelf.map { all("musicResponsiveListItemRenderer", in: $0).compactMap(song(row:)) } ?? []
        let seeAll = ((shelf?["bottomEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any])?["browseId"] as? String
            ?? (shelf.flatMap { all("browseEndpoint", in: $0["title"] ?? [:]).first?["browseId"] as? String })
        let subs = all("subscribeButtonRenderer", in: h).first.map { runs($0["subscriberCountText"]) }
        let banner = bannerURLs.last
        return ArtistInfo(channelID: cid, name: runs(h["title"]).nilIfEmpty ?? name,
                          picture: avatar ?? banner, banner: banner,
                          listeners: runs(h["monthlyListenerCount"]).nilIfEmpty, subscribers: subs?.nilIfEmpty,
                          bio: runs(h["description"]).nilIfEmpty, songs: songs, allSongs: seeAll)
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

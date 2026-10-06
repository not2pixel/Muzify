import SwiftUI

// MARK: - Ảnh bìa trên mạng (tải 1 lần, giữ trong bộ nhớ)

@MainActor
final class RemoteArt: ObservableObject {
    static let shared = RemoteArt()
    @Published private(set) var images: [String: PlatformImage] = [:]
    private var loading = Set<String>()

    func image(_ url: String?) -> PlatformImage? {
        guard let url, !url.isEmpty else { return nil }
        if let img = images[url] { return img }
        guard !loading.contains(url), let u = URL(string: url) else { return nil }
        loading.insert(url)
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: u), let img = PlatformImage(data: data) {
                images[url] = img
            }
            loading.remove(url)
        }
        return nil
    }
}

// MARK: - Cài đặt kho nhạc

enum CatalogProvider: String, CaseIterable, Identifiable {
    case all, off, youtubeMusic, soundcloud, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L("Tất cả nguồn")
        case .off: L("Chỉ nhạc trên máy")
        case .youtubeMusic: "YouTube Music"
        case .soundcloud: "SoundCloud"
        case .custom: L("API riêng")
        }
    }

    var detail: String {
        switch self {
        case .all: L("Gộp mọi nguồn làm một.")
        case .off: L("Không dùng kho nhạc online.")
        case .youtubeMusic: L("Kho nhạc online lớn.")
        case .soundcloud: L("Remix, cover, nhạc độc lập.")
        case .custom: L("Nguồn nhạc của riêng bạn.")
        }
    }
}

@MainActor
final class MusicSettings: ObservableObject {
    static let shared = MusicSettings()
    private let d = UserDefaults.standard

    @Published var provider: CatalogProvider { didSet { d.set(provider.rawValue, forKey: "catalog") } }
    /// Ví dụ: https://api.example.com/search?q={query}
    @Published var customURL: String { didSet { d.set(customURL, forKey: "customURL") } }
    /// Hết danh sách thì tự phát tiếp bài cùng gu.
    @Published var autoplay: Bool { didSet { d.set(autoplay, forKey: "autoplay") } }

    private init() {
        provider = CatalogProvider(rawValue: d.string(forKey: "catalog") ?? "") ?? .all
        customURL = d.string(forKey: "customURL") ?? ""
        autoplay = d.object(forKey: "autoplay") as? Bool ?? true
    }
}

// MARK: - Tìm kiếm

enum Catalog {
    static let browserUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15"

    static func looksLikeLink(_ s: String) -> Bool {
        let t = s.trimmed.lowercased()
        return t.contains("://") || t.hasPrefix("www.") || t.hasPrefix("youtu.be/") || t.hasPrefix("open.spotify.com")
    }

    @MainActor
    static func search(_ query: String) async throws -> [Track] {
        let s = MusicSettings.shared
        let q = query.trimmed
        guard !q.isEmpty else { return [] }
        switch s.provider {
        case .all: return try await merged(q)
        case .off: return []
        case .youtubeMusic:
            return try await YTM.songs(of: q)
        case .soundcloud:
            do { return try await SoundCloudAPI.shared.search(q) } catch { return try await soundcloud(q) }
        case .custom: return try await custom(q, template: s.customURL)
        }
    }

    // MARK: Gộp nhiều nguồn

    /// Nhạc trong máy trước, rồi YouTube Music; bỏ bài trùng.
    @MainActor
    private static func merged(_ q: String) async throws -> [Track] {
        let local = MusicLibrary.shared.tracks.filter {
            $0.title.localizedStandardContains(q) || $0.artist.localizedStandardContains(q)
                || "\($0.artist) \($0.title)".localizedStandardContains(q)
        }
        var online: [Track] = []
        do { online = try await YTM.songs(of: q) } catch { if local.isEmpty { throw error } }
        var seen = Set<String>()
        return (local + online).filter { seen.insert(key($0)).inserted }
    }

    /// Khoá so trùng: tên bài + nghệ sĩ đầu tiên, bỏ dấu, bỏ (…)/[…], chỉ giữ chữ và số.
    nonisolated static func key(_ t: Track) -> String {
        let terms = LyricsStore.searchTerms(for: t)
        func norm(_ s: String) -> String {
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
                .replacingOccurrences(of: "đ", with: "d") // l10n:skip
                .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
        }
        let firstArtist = terms.artist.components(separatedBy: CharacterSet(charactersIn: ",&")).first?
            .components(separatedBy: " và ").first?.components(separatedBy: " x ").first ?? terms.artist // l10n:skip
        return norm(terms.title) + "|" + norm(firstArtist)
    }

    private static func json(_ url: URL) async throws -> Any {
        var req = URLRequest(url: url)
        req.setValue("Muzify/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw MusicError.message(L("Kho nhạc trả về lỗi \(http.statusCode)."))
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    // SoundCloud — qua yt-dlp (dự phòng khi API v2 lỗi)
    @MainActor
    private static func soundcloud(_ q: String) async throws -> [Track] {
        #if os(macOS)
        guard let tool = MusicLibrary.shared.ytdlpPath() else {
            throw MusicError.message(L("SoundCloud cần yt-dlp — vào Cài đặt → Thư viện để cài."))
        }
        let info = try await MusicLibrary.run(tool, ["--flat-playlist", "-J", "--no-warnings", "scsearch30:\(q)"]) { _ in }
        let items = info["entries"] as? [[String: Any]] ?? []
        let tracks: [Track] = items.compactMap { e in
            guard let title = e["title"] as? String, let page = e["webpage_url"] as? String else { return nil }
            let thumbs = e["thumbnails"] as? [[String: Any]] ?? []
            let art = (thumbs.first { ($0["id"] as? String) == "t500x500" } ?? thumbs.last)?["url"] as? String
            return Track(title: title, artist: e["uploader"] as? String ?? L("Không rõ"),
                         duration: e["duration"] as? Double ?? 0, file: "", artwork: nil, source: page,
                         remoteURL: "ytdlp:" + page, artworkURL: art, catalog: "SoundCloud")
        }
        // Lấy sẵn link phát cho vài bài đầu để bấm là nghe ngay.
        Task { for t in tracks.prefix(3) { _ = await MusicLibrary.shared.resolveStream(t) } }
        return tracks
        #else
        throw MusicError.message(L("Không kết nối được SoundCloud."))
        #endif
    }

    /// API riêng: GET template có {query}; trả về mảng JSON (hoặc {results|data|tracks: [...]}).
    /// Mỗi phần tử: title/name, artist, url/stream/audio, artwork/image/cover, duration (giây).
    /// Phần tử có "preview": true (chỉ nghe thử) sẽ bị bỏ qua.
    private static func custom(_ q: String, template: String) async throws -> [Track] {
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        guard template.contains("{query}"), let u = URL(string: template.replacingOccurrences(of: "{query}", with: enc)) else {
            throw MusicError.message(L("Địa chỉ API riêng cần có {query}, ví dụ https://…/search?q={query}"))
        }
        let obj = try await json(u)
        let items: [[String: Any]] = (obj as? [[String: Any]])
            ?? ["results", "data", "tracks", "items"].lazy.compactMap { (obj as? [String: Any])?[$0] as? [[String: Any]] }.first
            ?? []
        func str(_ d: [String: Any], _ keys: [String]) -> String? {
            keys.lazy.compactMap { d[$0] as? String }.first { !$0.isEmpty }
        }
        return items.compactMap { t in
            guard (t["preview"] as? Bool) != true,
                  let title = str(t, ["title", "name"]), let audio = str(t, ["url", "stream", "audio", "src"]) else { return nil }
            return Track(title: title, artist: str(t, ["artist", "artist_name", "author"]) ?? L("Không rõ"),
                         duration: (t["duration"] as? Double) ?? Double(t["duration"] as? Int ?? 0), file: "",
                         artwork: nil, source: str(t, ["link", "page", "permalink"]) ?? audio, remoteURL: audio,
                         artworkURL: str(t, ["artwork", "image", "cover", "thumbnail"]), catalog: L("API riêng"))
        }
    }
}

// MARK: - SoundCloud API v2 (gọi thẳng, nhanh hơn yt-dlp nhiều)

/// Dùng client_id công khai của web SoundCloud (giống yt-dlp). Hết hạn thì tự lấy lại.
actor SoundCloudAPI {
    static let shared = SoundCloudAPI()
    private var clientID: String? = UserDefaults.standard.string(forKey: "scClientID")

    private func get(_ url: URL) async throws -> (Data, Int) {
        var r = URLRequest(url: url)
        r.setValue(Catalog.browserUA, forHTTPHeaderField: "User-Agent")
        r.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: r)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func refreshClientID() async throws -> String {
        let (html, _) = try await get(URL(string: "https://soundcloud.com")!)
        let page = String(decoding: html, as: UTF8.self)
        let scripts = page.matches(of: try Regex(#"<script crossorigin src="(https://a-v2\.sndcdn\.com/assets/[^"]+\.js)""#))
            .compactMap { $0.output[1].substring.map(String.init) }
        for s in scripts.reversed() {
            guard let u = URL(string: s) else { continue }
            let js = String(decoding: try await get(u).0, as: UTF8.self)
            if let m = js.firstMatch(of: try Regex(#"client_id\s*:\s*"([0-9a-zA-Z]{32})""#)), let id = m.output[1].substring {
                clientID = String(id)
                UserDefaults.standard.set(clientID, forKey: "scClientID")
                return String(id)
            }
        }
        throw MusicError.message(L("Không kết nối được SoundCloud."))
    }

    /// Gọi API kèm client_id; nếu bị từ chối thì lấy client_id mới và thử lại 1 lần.
    private func api(_ path: String, _ items: [URLQueryItem]) async throws -> Any {
        for attempt in 0..<2 {
            let id: String
            if attempt == 0, let cached = clientID { id = cached } else { id = try await refreshClientID() }
            var c = URLComponents(string: path)!
            c.queryItems = items + [URLQueryItem(name: "client_id", value: id)]
            let (data, code) = try await get(c.url!)
            if code == 401 || code == 403 { continue }
            guard code == 200 else { throw MusicError.message(L("SoundCloud lỗi \(code).")) }
            return try JSONSerialization.jsonObject(with: data)
        }
        throw MusicError.message(L("SoundCloud từ chối truy cập."))
    }

    func search(_ q: String) async throws -> [Track] {
        let obj = try await api("https://api-v2.soundcloud.com/search/tracks",
                                [.init(name: "q", value: q), .init(name: "limit", value: "40")])
        let items = (obj as? [String: Any])?["collection"] as? [[String: Any]] ?? []
        return items.compactMap { t in
            let policy = t["policy"] as? String
            guard let title = t["title"] as? String, policy != "BLOCK", policy != "SNIP",
                  let codings = (t["media"] as? [String: Any])?["transcodings"] as? [[String: Any]] else { return nil }
            func pick(_ proto: String, _ mime: String) -> String? {
                codings.first {
                    let f = $0["format"] as? [String: Any]
                    return (f?["protocol"] as? String) == proto && ((f?["mime_type"] as? String) ?? "").hasPrefix(mime)
                }?["url"] as? String
            }
            guard let coding = pick("progressive", "audio/mpeg") ?? pick("hls", "audio/mpeg") ?? pick("hls", "audio/mp4")
            else { return nil }
            let auth = t["track_authorization"] as? String ?? ""
            let art = ((t["artwork_url"] as? String) ?? ((t["user"] as? [String: Any])?["avatar_url"] as? String))?
                .replacingOccurrences(of: "-large.", with: "-t500x500.")
            return Track(title: title, artist: (t["user"] as? [String: Any])?["username"] as? String ?? L("Không rõ"),
                         duration: Double(t["full_duration"] as? Int ?? t["duration"] as? Int ?? 0) / 1000, file: "",
                         artwork: nil, source: t["permalink_url"] as? String,
                         remoteURL: "sc:\(coding)|\(auth)", artworkURL: art, catalog: "SoundCloud")
        }
    }

    /// "coding|auth" → link mp3/m3u8 thật.
    func stream(_ encoded: String) async -> URL? {
        let parts = encoded.split(separator: "|", maxSplits: 1).map(String.init)
        guard let coding = parts.first else { return nil }
        let auth = parts.count > 1 ? parts[1] : ""
        guard let obj = try? await api(coding, [.init(name: "track_authorization", value: auth)]),
              let s = (obj as? [String: Any])?["url"] as? String else { return nil }
        return URL(string: s)
    }
}

import Foundation

// MARK: - Lời bài hát: LRCLIB (lrclib.net) + YouTube Music, gộp làm một
//
// Thứ tự: lời chạy theo nhạc của LRCLIB → lời chạy theo nhạc của YouTube Music → lời thường
// (bài phát từ YouTube Music ưu tiên lời của chính video đó vì khớp tuyệt đối).

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double?
    let text: String
}

private struct LyricsCache: Codable {
    var synced: String?
    var plain: String?
    var name: String?
    var artist: String?
    var instrumental = false
    /// Nguồn: "LRCLIB", "YouTube Music · Nguồn: LyricFind"…
    var provider: String?
    /// Thời lượng bản nhạc mà lời được canh giờ theo.
    var duration: Double?
    /// Lời của đúng video đang phát (đã khớp sẵn, không cần bù lệch).
    var exact: Bool?
}

@MainActor
final class LyricsStore: ObservableObject {
    static let shared = LyricsStore()

    enum State: Equatable {
        case idle, loading, notFound, instrumental
        case failed(String)
        case found(lines: [LyricLine], synced: Bool, match: String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var trackID: UUID?

    private let dir: URL
    private var task: Task<Void, Never>?

    private init() {
        dir = MusicLibrary.shared.dir.appendingPathComponent("Lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Bộ nhớ đệm theo nguồn (bài online tìm thấy nhiều lần có id khác nhau nhưng cùng nguồn).
    private func cacheURL(_ t: Track) -> URL {
        // FNV-1a: ổn định giữa các lần mở app (khác `hashValue`).
        let key = t.source.map { s in
            String(s.utf8.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 }, radix: 16)
        } ?? t.id.uuidString
        return dir.appendingPathComponent("v5-\(key).json")
    }

    private var lyricsDuration: Double?
    private var lyricsExact = false

    /// Lệch tự động khi SponsorBlock cắt intro của MV mà lời lại canh theo bản audio (không có intro):
    /// dòng đầu nằm trong đoạn intro, hoặc thời lượng của lời ≈ thời lượng bài − intro → lùi lời đúng bằng intro.
    var autoOffset: Double {
        let p = MusicPlayer.shared
        let intro = p.introSkip
        guard intro > 0, !lyricsExact, case .found(let lines, true, _) = state,
              let first = lines.first(where: { !$0.text.isEmpty })?.time else { return 0 }
        if first < intro - 1 { return intro }
        // Bản MV = intro + bài + outro: trừ hết các đoạn bị cắt rồi so với thời lượng của lời.
        if let d = lyricsDuration, d > 0, abs(p.duration - p.skippedTotal - d) < 4 { return intro }
        return 0
    }

    /// Thời điểm trong bài = mốc của lời + offset.
    var offset: Double { autoOffset }

    /// Dòng đang hát ở thời điểm `time` của bài.
    func currentLine(at time: Double) -> Int? {
        guard case .found(let lines, true, _) = state else { return nil }
        let t = time - offset
        return lines.lastIndex { ($0.time ?? 0) <= t + 0.2 }
    }

    /// Thời điểm trong bài ứng với một dòng (để bấm vào dòng là tua tới).
    func seekTime(for line: LyricLine) -> Double? { line.time.map { max($0 + offset, 0) } }

    /// Tên tìm kiếm đã làm sạch (bỏ "official", "lyric video", [..], (..)…).
    nonisolated static func searchTerms(for t: Track) -> (title: String, artist: String) {
        var title = t.title
        var artist = t.artist
        for pattern in [#"\([^)]*\)"#, #"\[[^\]]*\]"#, #"【[^】]*】"#, #"\|.*$"#] {
            title = title.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        for junk in ["official music video", "official video", "official audio", "official visualizer", "lyric visualizer",
                     "lyrics video", "lyric video", "lyrics", "visualizer", "mv", "audio", "m/v"] {
            title = title.replacingOccurrences(of: junk, with: "", options: [.caseInsensitive])
        }
        // "Ca sĩ - Tên bài" → tách ra
        let parts = title.components(separatedBy: " - ")
        if parts.count >= 2 {
            artist = parts[0]
            title = parts.dropFirst().joined(separator: " - ")
        }
        artist = artist.replacingOccurrences(of: #"\s*-\s*Topic$|VEVO$|Official$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return (title.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "-–—·").union(.whitespaces)), artist.trimmed)
    }

    func load(_ track: Track, query: String? = nil) {
        trackID = track.id
        task?.cancel()

        let cacheURL = cacheURL(track)
        lyricsDuration = nil
        lyricsExact = false
        if query == nil, let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(LyricsCache.self, from: data) {
            apply(cached)
            return
        }

        state = .loading
        let terms = Self.searchTerms(for: track)
        let duration = track.duration
        let id = track.id
        let videoID = YTM.videoID(of: track)
        task = Task {
            do {
                let result = try await Self.fetch(title: terms.title, artist: terms.artist, duration: duration,
                                                  query: query, videoID: videoID)
                guard !Task.isCancelled, trackID == id else { return }
                let cache = result ?? LyricsCache()
                if let data = try? JSONEncoder().encode(cache) { try? data.write(to: cacheURL) }
                apply(cache)
            } catch {
                guard !Task.isCancelled, trackID == id else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func apply(_ c: LyricsCache) {
        let song = [c.name, c.artist].compactMap { $0 }.joined(separator: " — ")
        let match = L("Lời bài hát do \(c.provider ?? "LRCLIB") cung cấp") + (song.isEmpty ? "" : L(" · \(song)"))
        lyricsDuration = c.duration
        lyricsExact = c.exact == true
        if c.instrumental { state = .instrumental }
        else if let s = c.synced, !s.isEmpty { state = .found(lines: Self.parseLRC(s), synced: true, match: match) }
        else if let p = c.plain, !p.isEmpty {
            let lines = p.components(separatedBy: "\n").enumerated().map { LyricLine(id: $0.offset, time: nil, text: $0.element) }
            state = .found(lines: lines, synced: false, match: match)
        } else { state = .notFound }
    }

    static func parseLRC(_ lrc: String) -> [LyricLine] {
        let tag = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)
        var out: [(Double, String)] = []
        for raw in lrc.components(separatedBy: "\n") {
            let ns = raw as NSString
            let matches = tag.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length).trimmed
            for m in matches {
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2))) ?? 0
                out.append((min * 60 + sec, text))
            }
        }
        return out.sorted { $0.0 < $1.0 }.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }

    // MARK: Mạng

    private struct Item: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    nonisolated private static func request(_ path: String, _ items: [URLQueryItem]) async throws -> Data? {
        var c = URLComponents(string: "https://lrclib.net/api/\(path)")!
        c.queryItems = items
        var req = URLRequest(url: c.url!)
        req.setValue("Muzify/1.0 (macOS music player)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw MusicError.message(L("LRCLIB lỗi \(http.statusCode).")) }
        return data
    }

    /// Luôn ưu tiên YouTube Music (kể cả khi chỉ có lời thường); không có mới dùng LRCLIB:
    /// 1. YouTube Music của đúng video đang phát · 2. YouTube Music tìm theo tên (vd MV không có lời → bản audio)
    /// 3. LRCLIB khớp chính xác tên + nghệ sĩ + thời lượng · 4. LRCLIB tìm gần đúng
    /// Trong cùng YouTube Music: bản có lời chạy theo nhạc được chọn trước bản lời thường.
    nonisolated private static func fetch(title: String, artist: String, duration: Double, query: String?,
                                          videoID: String?) async throws -> LyricsCache? {
        func has(_ c: LyricsCache?) -> Bool { c.map { $0.instrumental || $0.synced?.isEmpty == false || $0.plain?.isEmpty == false } ?? false }
        func synced(_ c: LyricsCache?) -> Bool { c?.synced?.isEmpty == false }
        func norm(_ s: String) -> String {
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
        }

        // YouTube Music
        var ytPlain: LyricsCache?
        if query == nil, let videoID {
            let c = await youtube(videoID, exact: true)
            if synced(c) { return c }
            if has(c) { ytPlain = c }
        }
        if let hit = try? await YTM.songs(of: query ?? "\(artist) \(title)".trimmed).first,
           let vid = YTM.videoID(of: hit), vid != videoID || query != nil,
           // Tìm theo tên thì chỉ nhận khi đúng bài (tránh lời của bài khác).
           query != nil || title.isEmpty || norm(hit.title).contains(norm(title)) || norm(title).contains(norm(hit.title)) {
            let c = await youtube(vid, duration: hit.duration)
            if synced(c) { return c }
            if ytPlain == nil, has(c) { ytPlain = c }
        }
        if let ytPlain { return ytPlain }

        // LRCLIB
        if query == nil, let c = try? await lrclibExact(title: title, artist: artist, duration: duration), has(c) { return c }
        let c = try await lrclibSearch(title: title, artist: artist, duration: duration, query: query)
        return has(c) ? c : nil
    }

    nonisolated private static func youtube(_ videoID: String, exact: Bool = false, duration: Double? = nil) async -> LyricsCache? {
        guard let l = try? await YTM.lyrics(videoID: videoID) else { return nil }
        let synced = l.timed.map { rows in
            rows.map { String(format: "[%02d:%05.2f]", Int($0.0) / 60, $0.0.truncatingRemainder(dividingBy: 60)) + $0.1 }
                .joined(separator: "\n")
        }
        let credit = l.credit.map { L("YouTube Music · \($0)") } ?? "YouTube Music"
        return LyricsCache(synced: synced, plain: l.plain ?? l.timed?.map(\.1).joined(separator: "\n"), provider: credit,
                           duration: duration, exact: exact)
    }

    nonisolated private static func lrcCache(_ i: Item) -> LyricsCache {
        LyricsCache(synced: i.syncedLyrics, plain: i.plainLyrics, name: i.trackName, artist: i.artistName,
                    instrumental: i.instrumental ?? false, provider: "LRCLIB", duration: i.duration)
    }

    nonisolated private static func lrclibExact(title: String, artist: String, duration: Double) async throws -> LyricsCache? {
        guard !title.isEmpty, !artist.isEmpty, duration > 0,
              let data = try await request("get", [
                  .init(name: "track_name", value: title), .init(name: "artist_name", value: artist),
                  .init(name: "duration", value: String(Int(duration.rounded()))),
              ]), let item = try? JSONDecoder().decode(Item.self, from: data) else { return nil }
        return lrcCache(item)
    }

    nonisolated private static func lrclibSearch(title: String, artist: String, duration: Double, query: String?) async throws -> LyricsCache? {
        func cache(_ i: Item) -> LyricsCache {
            LyricsCache(synced: i.syncedLyrics, plain: i.plainLyrics, name: i.trackName, artist: i.artistName,
                        instrumental: i.instrumental ?? false, provider: "LRCLIB", duration: i.duration)
        }
        // Tìm kiếm, ưu tiên bản có lời chạy theo nhạc và thời lượng gần nhất
        let q = query ?? "\(artist) \(title)".trimmed
        guard let data = try await request("search", [.init(name: "q", value: q)]),
              let items = try? JSONDecoder().decode([Item].self, from: data), !items.isEmpty else { return nil }
        let best = items.min { a, b in
            func score(_ i: Item) -> Double {
                let diff = duration > 0 ? abs((i.duration ?? 0) - duration) : 0
                return diff + (i.syncedLyrics?.isEmpty == false ? 0 : 30) + (i.instrumental == true ? 100 : 0)
            }
            return score(a) < score(b)
        }
        return best.map(cache)
    }
}

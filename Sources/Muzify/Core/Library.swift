import AVFoundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

private struct LibrarySnapshot: Codable {
    var tracks: [Track]
    var playlists: [Playlist]
    var artists: [Artist]?
}

// MARK: - Thư viện
//
// Mô hình giống Spotify:
// - "Thích" một bài = thêm vào thư viện (vẫn phát online, không tải).
// - "Tải xuống" = lưu tệp về máy để nghe offline; bỏ thích thì bản tải cũng bị xoá.
// - Bài chỉ nằm trong playlist (không thích) vẫn được giữ trong thư viện, ẩn khỏi "Bài hát đã thích".

@MainActor
final class MusicLibrary: ObservableObject {
    static let shared = MusicLibrary()

    enum ToolState: Equatable { case missing, installing(Double), ready }

    let dir: URL
    let tracksDir: URL
    let artDir: URL
    let binDir: URL
    private let indexURL: URL

    @Published var tracks: [Track] = [] { didSet { save() } }
    @Published var playlists: [Playlist] = [] { didSet { save() } }
    @Published var artists: [Artist] = [] { didSet { save() } }
    @Published var jobs: [DownloadJob] = []
    @Published private(set) var toolState: ToolState = .missing
    @Published var message: String?

    private var artCache: [String: PlatformImage] = [:]
    /// Bài online đang hiển thị / trong hàng đợi (chưa lưu vào thư viện).
    private var transient: [UUID: Track] = [:]
    private var resolved: [String: (url: URL, headers: [String: String], at: Date)] = [:]

    private init() {
        let fm = FileManager.default
        dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Muzify", isDirectory: true)
        tracksDir = dir.appendingPathComponent("Tracks", isDirectory: true)
        artDir = dir.appendingPathComponent("Artwork", isDirectory: true)
        binDir = dir.appendingPathComponent("bin", isDirectory: true)
        indexURL = dir.appendingPathComponent("library.json")
        for d in [tracksDir, artDir, binDir] { try? fm.createDirectory(at: d, withIntermediateDirectories: true) }

        if let data = try? Data(contentsOf: indexURL), let snap = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) {
            let tracksDir = tracksDir
            tracks = snap.tracks.compactMap { t in
                if t.file.isEmpty { return t.remoteURL == nil ? nil : t }
                if fm.fileExists(atPath: tracksDir.appendingPathComponent(t.file).path) { return t }
                // Tệp tải về đã mất nhưng bài vẫn phát online được.
                var r = t
                r.file = ""
                return r.remoteURL == nil ? nil : r
            }
            playlists = snap.playlists
            artists = snap.artists ?? []
        }
        toolState = ytdlpPath() == nil ? .missing : .ready
        repairDurations()
        warmUpTool()
        for i in tracks.indices where tracks[i].artworkURL == nil {
            if let u = Self.youTubeThumb(tracks[i].source) { tracks[i].artworkURL = u }
        }
    }

    private func save() {
        let snap = LibrarySnapshot(tracks: tracks, playlists: playlists, artists: artists)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    /// Sửa các bài đã tải trước đây bị sai thời lượng.
    private func repairDurations() {
        let items = tracks.filter { $0.file.lowercased().hasSuffix(".m4a") }.map { ($0.id, fileURL($0)) }
        guard !items.isEmpty else { return }
        Task {
            for (id, url) in items {
                await Self.fixDuration(url)
                let d = await Self.duration(of: url)
                if let i = tracks.firstIndex(where: { $0.id == id }), d > 0, abs(tracks[i].duration - d) > 0.5 {
                    tracks[i].duration = d
                }
            }
        }
    }

    // MARK: Tra cứu

    var liked: [Track] { tracks.filter(\.liked) }
    var downloaded: [Track] { tracks.filter(\.isDownloaded) }

    func track(_ id: UUID) -> Track? { tracks.first { $0.id == id } ?? transient[id] }
    func tracks(in playlist: Playlist) -> [Track] { playlist.trackIDs.compactMap(track) }
    func remember(_ list: [Track]) { for t in list where t.isRemote { transient[t.id] = t } }

    func fileURL(_ t: Track) -> URL {
        if t.isRemote, let r = t.remoteURL, let u = URL(string: r) { return u }
        return tracksDir.appendingPathComponent(t.file)
    }

    func libraryIndex(of t: Track) -> Int? { tracks.firstIndex { $0.isSame(as: t) } }
    func isLiked(_ t: Track) -> Bool { libraryIndex(of: t).map { tracks[$0].liked } ?? false }
    func isDownloaded(_ t: Track) -> Bool { libraryIndex(of: t).map { tracks[$0].isDownloaded } ?? t.isDownloaded }
    func isDownloading(_ t: Track) -> Bool {
        guard let i = libraryIndex(of: t) else { return false }
        let id = tracks[i].id
        return jobs.contains { $0.trackID == id && $0.status != .failed }
    }

    func artwork(_ t: Track?) -> PlatformImage? {
        guard let name = t?.artwork else { return RemoteArt.shared.image(t?.artworkURL) }
        if let img = artCache[name] { return img }
        guard let img = PlatformImage(contentsOfFile: artDir.appendingPathComponent(name).path) else { return RemoteArt.shared.image(t?.artworkURL) }
        artCache[name] = img
        return img
    }

    // MARK: Thích / bỏ thích

    func toggleLike(_ t: Track) { setLiked(t, !isLiked(t)) }

    func setLiked(_ t: Track, _ on: Bool) {
        if let i = libraryIndex(of: t) {
            guard !tracks[i].isLocalFile, tracks[i].liked != on else { return }
            tracks[i].liked = on
            if on { tracks[i].addedAt = .now } else { prune(tracks[i].id) }
        } else if on {
            var n = t
            n.liked = true
            n.addedAt = .now
            tracks.insert(n, at: 0)
        }
    }

    /// Đảm bảo bài có trong thư viện (để thêm vào playlist), trả về id trong thư viện.
    @discardableResult
    func persist(_ t: Track) -> UUID {
        if let i = libraryIndex(of: t) { return tracks[i].id }
        var n = t
        n.liked = false
        n.addedAt = .now
        tracks.insert(n, at: 0)
        return n.id
    }

    /// Bài không còn được thích và không thuộc playlist nào → bỏ khỏi thư viện (xoá cả bản tải).
    private func prune(_ id: UUID) {
        guard let i = tracks.firstIndex(where: { $0.id == id }), !tracks[i].liked, !tracks[i].isLocalFile,
              !playlists.contains(where: { $0.trackIDs.contains(id) }) else { return }
        var t = tracks[i]
        if t.isDownloaded {
            removeFiles(t)
            t.file = ""
            t.artwork = nil
        }
        if t.remoteURL != nil { transient[t.id] = t } // vẫn phát tiếp được nếu đang trong hàng đợi
        tracks.remove(at: i)
    }

    private func removeFiles(_ t: Track) {
        if !t.file.isEmpty { try? FileManager.default.removeItem(at: tracksDir.appendingPathComponent(t.file)) }
        if let art = t.artwork {
            try? FileManager.default.removeItem(at: artDir.appendingPathComponent(art))
            artCache[art] = nil
        }
    }

    // MARK: Nghệ sĩ theo dõi

    func isFollowing(_ name: String) -> Bool { artists.contains { $0.id == name.lowercased() } }

    func toggleFollow(_ name: String, art: String?) {
        if isFollowing(name) { artists.removeAll { $0.id == name.lowercased() } }
        else { artists.insert(Artist(name: name, art: art), at: 0) }
    }

    // MARK: Playlist

    @discardableResult
    func newPlaylist(_ name: String? = nil) -> UUID {
        let p = Playlist(name: name ?? L("Playlist của tôi #\(playlists.count + 1)"))
        playlists.insert(p, at: 0)
        return p.id
    }

    func add(_ list: [Track], to playlistID: UUID) {
        guard let pi = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        for t in list {
            let id = persist(t)
            if !playlists[pi].trackIDs.contains(id) { playlists[pi].trackIDs.append(id) }
        }
    }

    /// Thêm theo id (kéo thả) — bài online cần đang hiển thị / trong hàng đợi.
    func add(ids: [UUID], to playlistID: UUID) { add(ids.compactMap(track), to: playlistID) }

    func remove(_ trackID: UUID, from playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].trackIDs.removeAll { $0 == trackID }
        prune(trackID)
    }

    func deletePlaylist(_ id: UUID) {
        guard let p = playlists.first(where: { $0.id == id }) else { return }
        playlists.removeAll { $0.id == id }
        p.trackIDs.forEach(prune)
    }

    func renamePlaylist(_ id: UUID, to name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }), !name.trimmed.isEmpty else { return }
        playlists[i].name = name.trimmed
    }

    /// Kéo một bài trong playlist thả lên bài khác → chuyển tới trước bài đó.
    func move(_ trackID: UUID, before target: UUID, in playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }), trackID != target,
              let from = playlists[i].trackIDs.firstIndex(of: trackID) else { return }
        playlists[i].trackIDs.remove(at: from)
        let to = playlists[i].trackIDs.firstIndex(of: target) ?? playlists[i].trackIDs.count
        playlists[i].trackIDs.insert(trackID, at: to)
    }

    /// Lưu playlist online (YouTube Music, mix…) thành playlist trong thư viện.
    @discardableResult
    func savePlaylist(name: String, tracks list: [Track]) -> UUID {
        let id = newPlaylist(name)
        add(list, to: id)
        return id
    }

    // MARK: Sửa / xoá

    func rename(_ id: UUID, title: String, artist: String) {
        guard let i = tracks.firstIndex(where: { $0.id == id }) else { return }
        if !title.trimmed.isEmpty { tracks[i].title = title.trimmed }
        if !artist.trimmed.isEmpty { tracks[i].artist = artist.trimmed }
    }

    /// Xoá hẳn bài khỏi thư viện (dùng cho tệp nhập từ máy).
    func delete(_ id: UUID) {
        guard let t = track(id) else { return }
        MusicPlayer.shared.removeFromQueue(id)
        removeFiles(t)
        tracks.removeAll { $0.id == id }
        for i in playlists.indices { playlists[i].trackIDs.removeAll { $0 == id } }
    }

    /// Xoá bản tải về, bài vẫn ở trong thư viện và phát online.
    func removeDownload(_ t: Track) {
        guard let i = libraryIndex(of: t), tracks[i].isDownloaded, tracks[i].remoteURL != nil else { return }
        removeFiles(tracks[i])
        tracks[i].file = ""
        tracks[i].artwork = nil
    }

    // MARK: Phát online

    /// Bỏ link đã lưu (link hết hạn / không phát được) để lần sau lấy lại.
    func invalidateStream(_ t: Track) {
        if let r = t.remoteURL { resolved[r] = nil }
    }

    /// Link phát thật của bài online.
    func resolveStream(_ t: Track) async -> URL? { await streamInfo(t)?.url }

    /// Link phát thật + HTTP header cần gửi kèm (link YouTube chỉ mở được với đúng User-Agent yt-dlp đã dùng).
    /// Lưu 20 phút vì link có hạn.
    func streamInfo(_ t: Track) async -> (url: URL, headers: [String: String])? {
        guard let r = t.remoteURL else { return nil }
        if let c = resolved[r], Date().timeIntervalSince(c.at) < 1200 { return (c.url, c.headers) }
        var page: String?
        if r.hasPrefix("sc:") {
            if let url = await SoundCloudAPI.shared.stream(String(r.dropFirst(3))) {
                resolved[r] = (url, [:], .now)
                return (url, [:])
            }
            // Mã xác thực của SoundCloud đã hết hạn → nhờ yt-dlp lấy lại từ trang bài hát (Mac).
            page = t.source
        } else if r.hasPrefix("find:") {
            // Bài từ bảng xếp hạng (chỉ có tên) → phát bản tương ứng trên YouTube Music.
            page = await youTubePage(for: t)
        } else if r.hasPrefix("ytdlp:") {
            page = String(r.dropFirst(6))
        } else {
            return URL(string: r).map { ($0, [:]) }
        }
        guard let page else { return nil }
        // YouTube: lấy link trực tiếp bằng Swift (nhanh, chạy cả trên iOS); lỗi thì dùng yt-dlp (Mac).
        if let vid = YouTubeStream.videoID(from: page) {
            do {
                let a = try await YouTubeStream.shared.audio(videoID: vid)
                resolved[r] = (a.url, a.headers, .now)
                return (a.url, a.headers)
            } catch {
                Log.write("youtube native failed \(vid): \(error.localizedDescription)")
            }
        }
        return await ytdlpStream(page, key: r)
    }

    private var matchedPages: [String: String] = [:]

    /// Trang YouTube Music của bài "find:": tìm "nghệ sĩ tên bài", ưu tiên bài có thời lượng gần nhất.
    func youTubePage(for t: Track) async -> String? {
        guard let r = t.remoteURL, r.hasPrefix("find:") else { return nil }
        if let p = matchedPages[r] { return p }
        guard let found = try? await YTM.songs(of: String(r.dropFirst(5))), !found.isEmpty else { return nil }
        let best = t.duration > 0
            ? found.prefix(5).min { abs($0.duration - t.duration) < abs($1.duration - t.duration) } ?? found[0]
            : found[0]
        matchedPages[r] = best.source
        return best.source
    }

    private func ytdlpStream(_ page: String, key: String) async -> (url: URL, headers: [String: String])? {
        #if os(macOS)
        guard let tool = ytdlpPath() else { return nil }
        let fmt = "http_mp3_1_0/http_mp3_128/hls_mp3_1_0/hls_mp3_128/bestaudio[ext=mp3]/bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/best[ext=mp4]"
        let lines = await Self.outputLines(tool, ["--no-warnings", "--no-playlist", "-f", fmt,
                                                   "--print", "%(url)s", "--print", "%(http_headers)j", page])
        guard let first = lines.first, let url = URL(string: first) else { return nil }
        let headers = lines.count > 1
            ? ((try? JSONSerialization.jsonObject(with: Data(lines[1].utf8))) as? [String: String] ?? [:]) : [:]
        resolved[key] = (url, headers, .now)
        return (url, headers)
        #else
        return nil
        #endif
    }

    // MARK: Tải xuống

    /// Tải bài về máy (tự thích nếu chưa có trong thư viện).
    func download(_ t: Track) {
        if libraryIndex(of: t) == nil { setLiked(t, true) }
        guard let i = libraryIndex(of: t) else { return }
        let cur = tracks[i]
        guard !cur.isDownloaded, !jobs.contains(where: { $0.trackID == cur.id && $0.status != .failed }) else { return }
        jobs.removeAll { $0.trackID == cur.id }

        let job = DownloadJob(link: cur.source ?? cur.remoteURL ?? "", title: L("\(cur.title) — \(cur.artist)"), trackID: cur.id)
        jobs.insert(job, at: 0)
        let jobID = job.id
        Task {
            do {
                // Link âm thanh thật: YouTube (Swift), SoundCloud, bảng xếp hạng, hoặc link trực tiếp (API riêng).
                guard let source = await streamInfo(cur), !source.url.absoluteString.contains(".m3u8") else {
                    #if os(macOS)
                    if let page = cur.source, ytdlpPath() != nil {
                        jobs.removeAll { $0.id == jobID }
                        importLink(page, into: cur.id) // dự phòng: yt-dlp
                        return
                    }
                    #endif
                    throw MusicError.message(L("Không tải được bài này."))
                }
                updateJob(jobID) { $0.status = .downloading }
                var req = URLRequest(url: source.url)
                for (k, v) in source.headers { req.setValue(v, forHTTPHeaderField: k) }
                let (tmp, resp) = try await URLSession.shared.download(for: req)
                let http = resp as? HTTPURLResponse
                guard (200..<300).contains(http?.statusCode ?? 200) else {
                    throw MusicError.message(L("Máy chủ trả về lỗi \(http?.statusCode ?? 0)."))
                }
                let mime = http?.mimeType ?? ""
                let ext = mime.contains("mp4") || mime.contains("m4a") || mime.contains("aac") ? "m4a" : "mp3"
                let stem = UUID().uuidString
                let dest = tracksDir.appendingPathComponent("\(stem).\(ext)")
                try FileManager.default.moveItem(at: tmp, to: dest)
                updateJob(jobID) { $0.status = .converting }
                let playable = try await Self.ensurePlayable(dest, stem: stem)
                let art = await saveArtwork(from: cur.artworkURL, name: stem)
                let duration = await Self.duration(of: playable)
                if let j = tracks.firstIndex(where: { $0.id == cur.id }) {
                    tracks[j].file = playable.lastPathComponent
                    tracks[j].artwork = art
                    if duration > 0 { tracks[j].duration = duration }
                } else {
                    try? FileManager.default.removeItem(at: playable) // bài đã bị bỏ thích trong lúc tải
                }
                jobs.removeAll { $0.id == jobID }
            } catch {
                updateJob(jobID) { $0.status = .failed; $0.error = error.localizedDescription }
            }
        }
    }

    func downloadAll(_ list: [Track]) { list.filter { !isDownloaded($0) }.forEach(download) }

    // MARK: Công cụ

    #if os(macOS)
    /// Bản yt-dlp dạng thư mục: giải nén 1 lần nên khởi động ~0.2s (bản 1 tệp mất ~7s mỗi lần).
    var ytdlpDirPath: String { binDir.appendingPathComponent("ytdlp/yt-dlp_macos").path }

    func ytdlpPath() -> String? {
        let candidates = [ytdlpDirPath, "/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", binDir.appendingPathComponent("yt-dlp").path]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func ffmpegPath() -> String? {
        ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Chạy thử 1 lần lúc mở app để macOS quét xong, lần dùng thật sẽ nhanh.
    func warmUpTool() {
        guard let tool = ytdlpPath() else { return }
        Task.detached(priority: .background) { _ = await Self.firstLine(tool, ["--version"]) }
    }

    /// Tải bản yt-dlp chính thức (GitHub) vào thư mục riêng của Muzify.
    func installTool() {
        if case .installing = toolState { return }
        toolState = .installing(0)
        let src = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos.zip")!
        let dest = binDir.appendingPathComponent("ytdlp")
        Task {
            do {
                let (tmp, response) = try await URLSession.shared.download(from: src)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MusicError.message(L("GitHub trả về lỗi.")) }
                try? FileManager.default.removeItem(at: dest)
                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzip.arguments = ["-x", "-k", tmp.path, dest.path]
                try unzip.run()
                unzip.waitUntilExit()
                guard unzip.terminationStatus == 0, FileManager.default.isExecutableFile(atPath: ytdlpDirPath) else {
                    throw MusicError.message(L("Giải nén yt-dlp không thành công."))
                }
                toolState = .ready
                warmUpTool()
            } catch {
                toolState = ytdlpPath() == nil ? .missing : .ready
                message = L("Không cài được yt-dlp: \(error.localizedDescription)")
            }
        }
    }
    #else
    // iOS không chạy được yt-dlp — YouTube dùng YouTubeStream (Swift).
    func ytdlpPath() -> String? { nil }
    func ffmpegPath() -> String? { nil }
    func warmUpTool() {}
    func installTool() {}
    #endif

    // MARK: Nhập từ link

    /// Tải một link (YouTube, SoundCloud, Spotify track…) về máy.
    /// `into`: bài sẵn có trong thư viện cần gắn tệp tải về.
    func importLink(_ raw: String, into existing: UUID? = nil) {
        let link = raw.trimmed
        guard let url = URL(string: link), let host = url.host, url.scheme?.hasPrefix("http") == true else {
            message = L("Link không hợp lệ.")
            return
        }
        if host.contains("spotify.com"), !url.path.contains("/track/") {
            message = L("Hiện chỉ hỗ trợ link một bài hát Spotify (open.spotify.com/track/…).")
            return
        }
        if existing == nil, tracks.contains(where: { $0.source == link && $0.isDownloaded }) {
            message = L("Bài này đã có trong thư viện.")
            return
        }
        // Link YouTube / Spotify: nhập bằng Swift (chạy cả trên iOS), rồi tải như bài bình thường.
        if existing == nil, YouTubeStream.videoID(from: link) != nil || host.contains("spotify.com") {
            importNative(link, spotify: host.contains("spotify.com") ? url : nil)
            return
        }
        #if os(macOS)
        guard let tool = ytdlpPath() else {
            message = L("Cần cài yt-dlp trước khi tải từ link (Cài đặt → Thư viện).")
            return
        }
        let title = existing.flatMap(track).map { L("\($0.title) — \($0.artist)") } ?? link
        let job = DownloadJob(link: link, title: title, trackID: existing)
        jobs.insert(job, at: 0)
        let jobID = job.id
        let ffmpeg = ffmpegPath()
        let tracksDir = tracksDir

        Task {
            do {
                var target = link
                var meta: (title: String, artist: String, image: String?)?
                if host.contains("spotify.com") {
                    guard let info = await Self.spotifyInfo(url) else {
                        throw MusicError.message(L("Không đọc được thông tin bài hát từ Spotify."))
                    }
                    meta = info
                    updateJob(jobID) { $0.title = L("\(info.title) — \(info.artist)") }
                    // Nhạc Spotify có DRM: tìm bản tương ứng trên YouTube.
                    target = "ytsearch1:\(info.artist) - \(info.title) audio"
                }

                let stem = UUID().uuidString
                var args = ["--no-playlist", "--no-warnings", "--dump-json", "--no-simulate", "--progress", "--newline",
                            "--progress-template", "download:MUZIFY %(progress._percent_str)s",
                            "-o", tracksDir.appendingPathComponent("\(stem).%(ext)s").path]
                if let ffmpeg {
                    args += ["-f", "bestaudio/best", "-x", "--audio-format", "m4a", "--ffmpeg-location", ffmpeg]
                } else {
                    args += ["-f", "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio[ext=mp3]/best[ext=mp4]/best"]
                }
                args.append(target)

                updateJob(jobID) { $0.status = .downloading }
                let info = try await Self.run(tool, args) { [weak self] p in
                    Task { @MainActor in self?.updateJob(jobID) { $0.progress = p } }
                }

                let title = meta?.title ?? (info["track"] as? String) ?? (info["title"] as? String) ?? L("Không tên")
                let artist = meta?.artist ?? (info["artist"] as? String) ?? (info["uploader"] as? String)
                    ?? (info["channel"] as? String) ?? L("Không rõ")
                updateJob(jobID) { $0.title = L("\(title) — \(artist)"); $0.status = .converting }

                guard var file = try FileManager.default.contentsOfDirectory(atPath: tracksDir.path).first(where: { $0.hasPrefix(stem + ".") })
                else { throw MusicError.message(L("Không tìm thấy tệp đã tải.")) }
                file = try await Self.ensurePlayable(tracksDir.appendingPathComponent(file), stem: stem).lastPathComponent

                let duration = await Self.duration(of: tracksDir.appendingPathComponent(file))
                let thumb = meta?.image ?? (info["thumbnail"] as? String)
                let art = await saveArtwork(from: thumb, name: stem)
                let stream = "ytdlp:" + ((info["webpage_url"] as? String) ?? link)

                if let existing {
                    if let i = tracks.firstIndex(where: { $0.id == existing }) {
                        tracks[i].file = file
                        if let art { tracks[i].artwork = art }
                        if duration > 0 { tracks[i].duration = duration }
                        if tracks[i].remoteURL == nil { tracks[i].remoteURL = stream }
                    } else {
                        try? FileManager.default.removeItem(at: tracksDir.appendingPathComponent(file))
                    }
                } else {
                    var t = Track(title: title, artist: artist, duration: duration, file: file, artwork: art, source: link)
                    t.remoteURL = stream
                    t.artworkURL = thumb ?? Self.youTubeThumb(link)
                    t.catalog = host.contains("soundcloud") ? "SoundCloud" : host.contains("youtu") ? "YouTube" : host
                    tracks.insert(t, at: 0)
                }
                jobs.removeAll { $0.id == jobID }
            } catch {
                updateJob(jobID) { $0.status = .failed; $0.error = error.localizedDescription }
            }
        }
        #else
        message = L("Trên iPhone/iPad chỉ nhập được link YouTube, YouTube Music và Spotify.")
        #endif
    }

    private func importNative(_ link: String, spotify: URL?) {
        Task {
            do {
                var page = link
                var meta: (title: String, artist: String, image: String?)?
                if let spotify {
                    guard let info = await Self.spotifyInfo(spotify) else {
                        throw MusicError.message(L("Không đọc được thông tin bài hát từ Spotify."))
                    }
                    meta = info
                    // Nhạc Spotify có DRM: tìm bản tương ứng trên YouTube Music.
                    guard let hit = try await YTM.songs(of: "\(info.artist) \(info.title)").first, let p = hit.source else {
                        throw MusicError.message(L("Không tìm thấy “\(info.title)” trên YouTube Music để tải."))
                    }
                    page = p
                }
                guard let vid = YouTubeStream.videoID(from: page) else { throw MusicError.message(L("Link không hợp lệ.")) }
                let a = try await YouTubeStream.shared.audio(videoID: vid)
                let author = a.author?.replacingOccurrences(of: " - Topic", with: "")
                var t = Track(title: meta?.title ?? a.title ?? L("Không tên"), artist: meta?.artist ?? author ?? L("Không rõ"),
                              duration: a.duration ?? 0, file: "", source: link)
                t.remoteURL = "ytdlp:" + page
                t.artworkURL = meta?.image ?? Self.youTubeThumb(page) ?? a.thumbnail
                t.catalog = spotify == nil ? "YouTube" : "Spotify"
                setLiked(t, true)
                download(t)
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func updateJob(_ id: UUID, _ change: (inout DownloadJob) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[i])
    }

    func dismissJob(_ id: UUID) { jobs.removeAll { $0.id == id } }

    func retry(_ job: DownloadJob) {
        dismissJob(job.id)
        if let id = job.trackID, let t = track(id) { download(t) } else { importLink(job.link) }
    }

    private func saveArtwork(from urlString: String?, name: String) async -> String? {
        guard let s = urlString, let url = URL(string: s),
              let (data, _) = try? await URLSession.shared.data(from: url),
              PlatformImage(data: data) != nil else { return nil }
        let file = "\(name).img"
        try? data.write(to: artDir.appendingPathComponent(file))
        return file
    }

    // MARK: Nhập tệp trên máy

    func importFiles(_ urls: [URL]) {
        Task {
            for src in urls {
                let stem = UUID().uuidString
                let dest = tracksDir.appendingPathComponent("\(stem).\(src.pathExtension.lowercased())")
                // Tệp chọn từ app Tệp (iOS) cần xin quyền đọc tạm thời.
                let scoped = src.startAccessingSecurityScopedResource()
                defer { if scoped { src.stopAccessingSecurityScopedResource() } }
                do {
                    try FileManager.default.copyItem(at: src, to: dest)
                    let playable = try await Self.ensurePlayable(dest, stem: stem)
                    let asset = AVURLAsset(url: playable)
                    let items = (try? await asset.load(.commonMetadata)) ?? []
                    func string(_ key: AVMetadataKey) async -> String? {
                        guard let item = items.first(where: { $0.commonKey == key }) else { return nil }
                        return try? await item.load(.stringValue)
                    }
                    let title = await string(.commonKeyTitle) ?? src.deletingPathExtension().lastPathComponent
                    let artist = await string(.commonKeyArtist) ?? L("Không rõ")
                    var art: String?
                    if let item = items.first(where: { $0.commonKey == .commonKeyArtwork }),
                       let data = try? await item.load(.dataValue), PlatformImage(data: data) != nil {
                        art = "\(stem).img"
                        try? data.write(to: artDir.appendingPathComponent(art!))
                    }
                    let duration = await Self.duration(of: playable)
                    tracks.insert(Track(title: title, artist: artist, duration: duration,
                                        file: playable.lastPathComponent, artwork: art), at: 0)
                } catch {
                    try? FileManager.default.removeItem(at: dest)
                    message = L("Không nhập được \(src.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
    }

    #if os(macOS)
    func importWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Movie]
        panel.allowsMultipleSelection = true
        panel.prompt = L("Thêm vào Muzify")
        panel.begin { [weak self] in
            if $0 == .OK { self?.importFiles(panel.urls) }
        }
    }

    #endif

    // MARK: Ảnh bìa công khai (Discord)

    private var artworkLookups = Set<UUID>()

    /// Link ảnh bìa công khai. Bài trên máy không có link → tìm ảnh bìa trên iTunes theo tên + nghệ sĩ.
    func publicArtworkURL(_ t: Track) async -> String? {
        if let u = t.artworkURL, u.hasPrefix("http") { return u }
        if let yt = Self.youTubeThumb(t.source) { setArtworkURL(t.id, yt); return yt }
        guard !artworkLookups.contains(t.id) else { return nil }
        artworkLookups.insert(t.id)
        let terms = LyricsStore.searchTerms(for: t)
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [.init(name: "term", value: "\(terms.artist) \(terms.title)"), .init(name: "media", value: "music"),
                        .init(name: "entity", value: "song"), .init(name: "limit", value: "1")]
        guard let url = c.url, let (data, _) = try? await URLSession.shared.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (obj["results"] as? [[String: Any]])?.first,
              let art = (first["artworkUrl100"] as? String)?.replacingOccurrences(of: "100x100bb", with: "512x512bb")
        else { return nil }
        setArtworkURL(t.id, art)
        return art
    }

    private func setArtworkURL(_ id: UUID, _ url: String) {
        if let i = tracks.firstIndex(where: { $0.id == id }) { tracks[i].artworkURL = url }
        else if var t = transient[id] { t.artworkURL = url; transient[id] = t }
    }

    // MARK: Hàm phụ (chạy ngoài main thread)

    #if os(macOS)
    nonisolated static func outputLines(_ tool: String, _ args: [String]) async -> [String] {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { _ in
                let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                cont.resume(returning: text.split(separator: "\n").map(String.init))
            }
            do { try p.run() } catch { cont.resume(returning: []) }
        }
    }

    nonisolated static func firstLine(_ tool: String, _ args: [String]) async -> String? {
        await outputLines(tool, args).first
    }
    #endif

    /// Ảnh thumbnail công khai của video YouTube (luôn tồn tại bản hqdefault).
    nonisolated static func youTubeThumb(_ source: String?) -> String? {
        guard let s = source, let u = URL(string: s), let host = u.host?.lowercased() else { return nil }
        var id: String?
        if host.hasSuffix("youtu.be") {
            id = u.pathComponents.dropFirst().first
        } else if host.contains("youtube.com") {
            if let v = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value {
                id = v
            } else if let i = u.pathComponents.firstIndex(where: { $0 == "shorts" || $0 == "embed" || $0 == "live" }),
                      i + 1 < u.pathComponents.count {
                id = u.pathComponents[i + 1]
            }
        }
        guard let id, id.count >= 6, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"
    }

    #if os(macOS)
    /// Chạy yt-dlp, trả về JSON thông tin bài; báo tiến độ 0…1.
    nonisolated static func run(_ tool: String, _ args: [String],
                                progress: @escaping @Sendable (Double) -> Void) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err

            /// Bộ đệm dùng chung giữa các luồng đọc (có khoá).
            final class State: @unchecked Sendable {
                let lock = NSLock()
                var buffer = ""
                var json: [String: Any]?
                var errText = ""

                func feed(_ chunk: String, progress: (Double) -> Void, flush: Bool = false) {
                    lock.lock()
                    buffer += chunk
                    var lines = buffer.components(separatedBy: "\n")
                    buffer = flush ? "" : lines.removeLast()
                    lock.unlock()
                    for line in lines {
                        if line.hasPrefix("MUZIFY ") {
                            let pct = Double(line.dropFirst(7).trimmingCharacters(in: .whitespaces)
                                .replacingOccurrences(of: "%", with: "")) ?? 0
                            progress(min(1, pct / 100))
                        } else if line.hasPrefix("{"), let d = line.data(using: .utf8),
                                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                            lock.lock(); json = obj; lock.unlock()
                        }
                    }
                }
            }
            let state = State()

            out.fileHandleForReading.readabilityHandler = { h in
                state.feed(String(decoding: h.availableData, as: UTF8.self), progress: progress)
            }
            err.fileHandleForReading.readabilityHandler = { h in
                let chunk = String(decoding: h.availableData, as: UTF8.self)
                state.lock.lock(); state.errText += chunk; state.lock.unlock()
            }
            p.terminationHandler = { proc in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                let rest = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                state.feed(rest, progress: progress, flush: true)
                let restErr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                state.lock.lock(); state.errText += restErr
                let j = state.json; let e = state.errText; state.lock.unlock()
                if proc.terminationStatus == 0, let j {
                    cont.resume(returning: j)
                } else {
                    let msg = e.split(separator: "\n").last { $0.contains("ERROR") }.map(String.init) ?? e.trimmed
                    cont.resume(throwing: MusicError.message(msg.isEmpty ? L("yt-dlp lỗi (mã \(proc.terminationStatus)).") : msg))
                }
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }

    #endif

    /// Tệp video (mp4/mov) → tách âm thanh ra m4a bằng AVFoundation.
    nonisolated static func ensurePlayable(_ url: URL, stem: String) async throws -> URL {
        let ext = url.pathExtension.lowercased()
        if ["m4a", "aac"].contains(ext) { await fixDuration(url); return url }
        if ["mp3", "wav", "aiff", "aif", "flac", "caf"].contains(ext) { return url }
        let asset = AVURLAsset(url: url)
        guard (try? await asset.load(.isPlayable)) == true else {
            try? FileManager.default.removeItem(at: url)
            throw MusicError.message(L("Định dạng .\(ext) không phát được. Cài ffmpeg (brew install ffmpeg) để Muzify tự chuyển đổi."))
        }
        guard ["mp4", "m4v", "mov"].contains(ext),
              let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return url }
        let out = url.deletingLastPathComponent().appendingPathComponent("\(stem).m4a")
        session.outputURL = out
        session.outputFileType = .m4a
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { c.resume() }
        }
        guard session.status == .completed else { return url }
        try? FileManager.default.removeItem(at: url)
        return out
    }

    nonisolated static func duration(of url: URL) async -> Double {
        if let real = realDuration(url) { return real }
        let d = (try? await AVURLAsset(url: url).load(.duration))?.seconds ?? 0
        return d.isFinite ? d : 0
    }

    /// Độ dài thật = số khung âm thanh / tần số lấy mẫu (không tin phần đầu tệp).
    nonisolated static func realDuration(_ url: URL) -> Double? {
        guard let f = try? AVAudioFile(forReading: url), f.fileFormat.sampleRate > 0, f.length > 0 else { return nil }
        let d = Double(f.length) / f.fileFormat.sampleRate
        return d.isFinite ? d : nil
    }

    /// m4a dạng DASH (YouTube, tải không có ffmpeg) ghi sai tổng thời lượng — thường gấp đôi.
    /// Đóng gói lại (không mã hoá lại) với đúng độ dài thật. Trả về true nếu đã sửa.
    @discardableResult
    nonisolated static func fixDuration(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let real = realDuration(url),
              let reported = try? await asset.load(.duration).seconds, reported.isFinite,
              reported > real + 1,
              let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
        else { return false }
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".fix-\(UUID().uuidString).m4a")
        session.outputURL = tmp
        session.outputFileType = .m4a
        session.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: real, preferredTimescale: 44100))
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { c.resume() }
        }
        guard session.status == .completed,
              let fixed = try? await AVURLAsset(url: tmp).load(.duration).seconds, abs(fixed - real) < 1 else {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        return true
    }

    /// Đọc tên bài, nghệ sĩ, ảnh bìa từ trang open.spotify.com.
    nonisolated static func spotifyInfo(_ url: URL) async -> (title: String, artist: String, image: String?)? {
        var req = URLRequest(url: url)
        req.setValue(Catalog.browserUA, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        func meta(_ key: String) -> String? {
            for pattern in ["property=\"\(key)\" content=\"", "name=\"\(key)\" content=\""] {
                if let r = html.range(of: pattern), let end = html[r.upperBound...].firstIndex(of: "\"") {
                    return decodeEntities(String(html[r.upperBound..<end]))
                }
            }
            return nil
        }
        guard let title = meta("og:title") else { return nil }
        var artist = meta("music:musician_description")
        if artist == nil, let desc = meta("og:description") {
            let parts = desc.components(separatedBy: " · ")
            artist = parts.count >= 3 ? (parts[0].contains("Spotify") ? parts[1] : parts[0]) : parts.first
        }
        return (title, artist ?? "", meta("og:image"))
    }

    nonisolated private static func decodeEntities(_ s: String) -> String {
        var r = s
        for (k, v) in ["&amp;": "&", "&quot;": "\"", "&#x27;": "'", "&#39;": "'", "&lt;": "<", "&gt;": ">"] {
            r = r.replacingOccurrences(of: k, with: v)
        }
        return r
    }
}

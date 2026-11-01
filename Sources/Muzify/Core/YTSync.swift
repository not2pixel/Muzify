import Foundation

// MARK: - Đồng bộ với tài khoản YouTube Music — chỉ khi người dùng bấm nút (Cài đặt → Tài khoản)
//
// Dữ liệu trên máy là chính. Khi bấm "Đồng bộ ngay":
// - Mục chỉ có trên YouTube: mới xuất hiện từ lần đồng bộ trước → thêm vào máy;
//   đã đồng bộ trước đó (tức đã bị xoá trên máy) → xoá luôn trên YouTube.
// - Mục chỉ có trên máy → đưa lên YouTube (kể cả mục đã bị xoá trên YouTube — máy thắng).
// "Đã đồng bộ trước đó" = syncedLikes / syncedArtists / syncedPlaylists (lưu sau mỗi lần đồng bộ).
//
// "Thay bằng dữ liệu YouTube": sao lưu rồi bỏ toàn bộ dữ liệu trên máy, chỉ giữ dữ liệu kéo từ YouTube.

@MainActor
final class YTSync: ObservableObject {
    static let shared = YTSync()
    private let d = UserDefaults.standard

    @Published private(set) var syncing = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var summary: String?
    @Published private(set) var error: String?
    /// Ghi bài nghe trên Muzify vào lịch sử YouTube (tắt mặc định).
    @Published var sendHistory: Bool { didSet { d.set(sendHistory, forKey: "ytSendHistory") } }

    private var syncedLikes: Set<String> { didSet { d.set(Array(syncedLikes), forKey: "ytSyncedLikes") } }
    private var syncedArtists: Set<String> { didSet { d.set(Array(syncedArtists), forKey: "ytSyncedArtists") } }
    private var syncedPlaylists: Set<String> { didSet { d.set(Array(syncedPlaylists), forKey: "ytSyncedPlaylists") } }

    private var lib: MusicLibrary { MusicLibrary.shared }

    private init() {
        sendHistory = d.object(forKey: "ytSendHistory") as? Bool ?? false
        syncedLikes = Set(d.stringArray(forKey: "ytSyncedLikes") ?? [])
        syncedArtists = Set(d.stringArray(forKey: "ytSyncedArtists") ?? [])
        syncedPlaylists = Set(d.stringArray(forKey: "ytSyncedPlaylists") ?? [])
        lastSync = d.object(forKey: "ytLastSync") as? Date
    }

    /// Đăng xuất: quên trạng thái đồng bộ (dữ liệu trên máy giữ nguyên).
    func stop() {
        syncedLikes = []
        syncedArtists = []
        syncedPlaylists = []
        lastSync = nil
        summary = nil
        error = nil
        d.removeObject(forKey: "ytLastSync")
    }

    func syncNow() { Task { await run(replace: false) } }

    /// Sao lưu + bỏ dữ liệu trên máy, rồi chỉ dùng dữ liệu từ YouTube.
    func replaceWithYouTube() { Task { await run(replace: true) } }

    private func run(replace: Bool) async {
        guard YTAccount.isSignedIn, !syncing else { return }
        syncing = true
        error = nil
        Log.write("ytsync: start replace=\(replace)")
        do {
            // Tải hết dữ liệu YouTube trước — lỗi mạng thì không đụng vào dữ liệu trên máy.
            let likes = try await remoteLikes()
            let subs = try await remoteArtists()
            var lists: [(id: String, title: String, tracks: [Track])] = []
            for p in try await remotePlaylists() { lists.append((p.id, p.title, try await playlistTracks(p.id))) }

            if replace {
                let backup = lib.resetAll()
                Log.write("ytsync: local data backed up to \(backup.path)")
                syncedLikes = []
                syncedArtists = []
                syncedPlaylists = []
            }
            await mergeLikes(likes)
            await mergeArtists(subs)
            await mergePlaylists(lists)

            lastSync = .now
            d.set(lastSync, forKey: "ytLastSync")
            summary = L("\(lib.liked.count) bài đã thích · \(lib.playlists.count) playlist · \(lib.artists.count) nghệ sĩ")
            Log.write("ytsync: done likes=\(lib.liked.count) playlists=\(lib.playlists.count) artists=\(lib.artists.count)")
            MusicHome.shared.load(force: true)
        } catch {
            self.error = error.localizedDescription
            Log.write("ytsync: failed \(error.localizedDescription)")
        }
        syncing = false
    }

    // MARK: Kéo từ YouTube

    private func remoteLikes() async throws -> [Track] {
        var out: [Track] = []
        for page in try await YTM.browseAll("VLLM") {
            out += YTM.all("musicResponsiveListItemRenderer", in: page).compactMap(YTM.song(row:))
        }
        var seen = Set<String>()
        return out.filter { YTM.videoID(of: $0).map { seen.insert($0).inserted } ?? false }
    }

    private func remoteArtists() async throws -> [Artist] {
        var out: [Artist] = []
        for page in try await YTM.browseAll("FEmusic_library_corpus_artists") {
            for r in YTM.all("musicResponsiveListItemRenderer", in: page) {
                guard let id = YTM.all("browseEndpoint", in: r).first?["browseId"] as? String, id.hasPrefix("UC"),
                      !out.contains(where: { $0.channelID == id }) else { continue }
                let cols = (r["flexColumns"] as? [[String: Any]]) ?? []
                let name = cols.first.map { YTM.runs(($0["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"]) } ?? ""
                if !name.isEmpty { out.append(Artist(name: name, art: YTM.thumb(r["thumbnail"], size: 544), channelID: id)) }
            }
        }
        return out
    }

    private func remotePlaylists() async throws -> [(id: String, title: String)] {
        var out: [(id: String, title: String)] = []
        for page in try await YTM.browseAll("FEmusic_liked_playlists") {
            for r in YTM.all("musicTwoRowItemRenderer", in: page) {
                guard let b = ((r["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any])?["browseId"] as? String,
                      b.hasPrefix("VL"), b != "VLLM", b != "VLSE" else { continue }
                let id = String(b.dropFirst(2))
                if !out.contains(where: { $0.id == id }) { out.append((id, YTM.runs(r["title"]))) }
            }
        }
        return out
    }

    private func playlistTracks(_ id: String) async throws -> [Track] {
        var out: [Track] = []
        for page in try await YTM.browseAll("VL" + id) {
            out += YTM.all("musicResponsiveListItemRenderer", in: page).compactMap(YTM.song(row:))
        }
        return out
    }

    // MARK: Gộp (máy là chính)

    private func mergeLikes(_ remote: [Track]) async {
        let remoteIDs = Set(remote.compactMap(YTM.videoID(of:)))
        var local: [String: Track] = [:]
        for t in lib.liked { if let v = YTM.videoID(of: t) { local[v] = t } }

        var add: [Track] = []
        for t in remote {
            guard let v = YTM.videoID(of: t), local[v] == nil else { continue }
            if syncedLikes.contains(v) {
                _ = try? await YTM.call("like/removelike", ["target": ["videoId": v]]) // đã bỏ thích trên máy
            } else {
                add.append(t)
            }
        }
        lib.applyRemoteLikes(add)
        for v in local.keys where !remoteIDs.contains(v) {
            _ = try? await YTM.call("like/like", ["target": ["videoId": v]])
        }
        syncedLikes = Set(lib.liked.compactMap(YTM.videoID(of:)))
    }

    private func mergeArtists(_ remote: [Artist]) async {
        for a in remote {
            if let i = lib.artists.firstIndex(where: { $0.channelID == a.channelID || $0.id == a.id }) {
                lib.artists[i].channelID = a.channelID
                if lib.artists[i].art == nil { lib.artists[i].art = a.art }
            } else if let c = a.channelID, syncedArtists.contains(c) {
                _ = try? await YTM.call("subscription/unsubscribe", ["channelIds": [c]]) // đã bỏ theo dõi trên máy
            } else {
                lib.artists.append(a)
            }
        }
        let remoteIDs = Set(remote.compactMap(\.channelID))
        for a in lib.artists where !(a.channelID.map(remoteIDs.contains) ?? false) {
            guard let c = try? await channelID(for: a) else { continue }
            if let i = lib.artists.firstIndex(where: { $0.id == a.id }) { lib.artists[i].channelID = c }
            _ = try? await YTM.call("subscription/subscribe", ["channelIds": [c]])
        }
        syncedArtists = Set(lib.artists.compactMap(\.channelID))
    }

    private func mergePlaylists(_ remote: [(id: String, title: String, tracks: [Track])]) async {
        for p in remote {
            if lib.playlists.contains(where: { $0.ytID == p.id }) { continue }
            if syncedPlaylists.contains(p.id) {
                // Đã xoá trên máy → xoá trên YouTube (playlist của người khác thì bỏ khỏi thư viện).
                if (try? await YTM.call("playlist/delete", ["playlistId": p.id])) == nil {
                    _ = try? await YTM.call("like/removelike", ["target": ["playlistId": p.id]])
                }
            } else {
                lib.applyRemotePlaylist(ytID: p.id, name: p.title, tracks: p.tracks)
            }
        }
        // Playlist trên máy: đưa nội dung lên YouTube (máy thắng); chưa có trên YouTube thì tạo mới.
        let remoteByID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for p in lib.playlists {
            let localIDs = await videoIDs(lib.tracks(in: p))
            if let yt = p.ytID, let r = remoteByID[yt] {
                let remoteIDs = r.tracks.compactMap(YTM.videoID(of:))
                if r.title != p.name {
                    _ = try? await YTM.call("browse/edit_playlist", ["playlistId": yt,
                                                                   "actions": [["action": "ACTION_SET_PLAYLIST_NAME", "playlistName": p.name]]])
                }
                let missing = localIDs.filter { !remoteIDs.contains($0) }
                if !missing.isEmpty {
                    _ = try? await YTM.call("browse/edit_playlist", ["playlistId": yt,
                                                                   "actions": missing.map { ["action": "ACTION_ADD_VIDEO", "addedVideoId": $0] }])
                }
                let extra = Set(remoteIDs).subtracting(localIDs)
                if !extra.isEmpty { await removeFromRemote(yt, videoIDs: extra) }
            } else if let obj = try? await YTM.call("playlist/create", ["title": p.name, "description": "Muzify",
                                                                         "privacyStatus": "PRIVATE", "videoIds": localIDs]),
                      let yt = (obj as? [String: Any])?["playlistId"] as? String,
                      let i = lib.playlists.firstIndex(where: { $0.id == p.id }) {
                lib.playlists[i].ytID = yt
            }
        }
        syncedPlaylists = Set(lib.playlists.compactMap(\.ytID))
    }

    /// Xoá bài khỏi playlist trên YouTube (cần setVideoId của từng dòng).
    private func removeFromRemote(_ yt: String, videoIDs: Set<String>) async {
        var actions: [[String: Any]] = []
        for page in (try? await YTM.browseAll("VL" + yt)) ?? [] {
            for r in YTM.all("musicResponsiveListItemRenderer", in: page) {
                guard let t = YTM.song(row: r), let v = YTM.videoID(of: t), videoIDs.contains(v),
                      let s = (r["playlistItemData"] as? [String: Any])?["playlistSetVideoId"] as? String else { continue }
                actions.append(["action": "ACTION_REMOVE_VIDEO", "setVideoId": s, "removedVideoId": v])
            }
        }
        if !actions.isEmpty { _ = try? await YTM.call("browse/edit_playlist", ["playlistId": yt, "actions": actions]) }
    }

    // MARK: Lịch sử nghe

    /// Ghi bài vào lịch sử YouTube (gọi khi đã nghe ≥ 30 giây, chỉ khi bật trong Cài đặt).
    func reportPlay(_ t: Track) {
        guard YTAccount.isSignedIn, sendHistory else { return }
        Task {
            guard let v = await videoID(for: t),
                  let obj = try? await YTM.call("player", ["videoId": v]),
                  let base = (((obj as? [String: Any])?["playbackTracking"] as? [String: Any])?["videostatsPlaybackUrl"]
                    as? [String: Any])?["baseUrl"] as? String else { return }
            let cpn = String((0..<16).map { _ in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_".randomElement()! })
            guard let url = URL(string: base + "&ver=2&c=WEB_REMIX&cpn=" + cpn) else { return }
            var req = URLRequest(url: url)
            req.setValue(Catalog.browserUA, forHTTPHeaderField: "User-Agent")
            for (k, val) in YTAccount.authHeaders() ?? [:] { req.setValue(val, forHTTPHeaderField: k) }
            let code = ((try? await URLSession.shared.data(for: req))?.1 as? HTTPURLResponse)?.statusCode ?? 0
            Log.write("ytsync: history \(v) -> \(code)")
        }
    }

    // MARK: Hàm phụ

    private func videoIDs(_ list: [Track]) async -> [String] {
        var out: [String] = []
        for t in list { if let v = await videoID(for: t), !out.contains(v) { out.append(v) } }
        return out
    }

    /// ID video YouTube của bài (bài bảng xếp hạng "find:" → tìm trên YouTube Music trước).
    private func videoID(for t: Track) async -> String? {
        if let v = YTM.videoID(of: t) { return v }
        if let page = await lib.youTubePage(for: t) { return YouTubeStream.videoID(from: page) }
        return nil
    }

    /// ID kênh của nghệ sĩ: có sẵn, hoặc tìm theo tên trên YouTube Music.
    private func channelID(for a: Artist) async throws -> String? {
        if let c = a.channelID { return c }
        return try await YTM.artist(name: a.name)?.channelID
    }
}

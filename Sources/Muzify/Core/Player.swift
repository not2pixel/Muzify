import AVFoundation
import SwiftUI
import Combine
import MediaPlayer

// MARK: - Trình phát

extension Notification.Name {
    static let skippedNonMusic = Notification.Name("muzify.skippedNonMusic")
}

@MainActor
final class MusicPlayer: ObservableObject {
    static let shared = MusicPlayer()

    enum RepeatMode: String { case off, all, one }

    @Published private(set) var queue: [UUID] = []
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var time: Double = 0
    @Published private(set) var duration: Double = 0
    /// Đang lấy link phát (YouTube, SoundCloud…) hoặc đang tìm bài để tự động phát tiếp.
    @Published private(set) var isResolving = false
    /// Đang phát từ đâu ("Bài hát đã thích", tên playlist…) — hiện ở khung Đang phát.
    @Published private(set) var contextTitle: String?
    /// Khoá nhận diện nguồn phát (để sidebar hiện biểu tượng loa).
    @Published private(set) var contextKey: String?

    @Published var shuffle = UserDefaults.standard.bool(forKey: "shuffle") {
        didSet {
            guard shuffle != oldValue else { return }
            UserDefaults.standard.set(shuffle, forKey: "shuffle")
            reshuffle()
        }
    }
    @Published var repeatMode = RepeatMode(rawValue: UserDefaults.standard.string(forKey: "repeat") ?? "") ?? .off {
        didSet { UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeat") }
    }
    @Published var volume: Float {
        didSet {
            player.volume = volume
            UserDefaults.standard.set(volume, forKey: "volume")
        }
    }

    /// Nghe gần đây (mới nhất trước) — dùng cho trang chủ & gợi ý.
    @Published private(set) var history: [Track] = UserDefaults.standard.data(forKey: "history")
        .flatMap { try? JSONDecoder().decode([Track].self, from: $0) } ?? []

    private let player = AVPlayer()
    /// Cho nút chọn loa AirPlay.
    var avPlayer: AVPlayer { player }
    /// Đoạn không phải nhạc của bài đang phát (SponsorBlock).
    private var skipSegments: [ClosedRange<Double>] = []
    /// Độ dài đoạn intro bị cắt ở đầu bài (0 nếu không có) — để canh lại lời bài hát.
    @Published private(set) var introSkip: Double = 0
    /// Tổng độ dài các đoạn bị cắt (intro + outro…).
    @Published private(set) var skippedTotal: Double = 0
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    /// Thứ tự gốc trước khi trộn (để tắt trộn thì trả lại).
    private var unshuffled: [UUID]?
    private var extending = false
    private var itemWatch: Set<AnyCancellable> = []
    private var statusWatch: AnyCancellable?
    /// Số lần đã thử lại bài hiện tại (lấy link mới) khi lỗi / kẹt.
    private var retries = 0
    /// Lần cuối thời gian còn chạy (để phát hiện kẹt).
    private var lastProgress = Date()
    private var lastTime: Double = -1
    /// Đang chờ tải dữ liệu (mạng chậm) — hiện vòng xoay.
    @Published private(set) var isBuffering = false

    private init() {
        #if os(iOS)
        // Phát nhạc khi khoá màn hình / chuyển app; tôn trọng nút gạt im lặng như các app nhạc khác.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        volume = UserDefaults.standard.object(forKey: "volume") as? Float ?? 0.8
        var seen = Set<String>()
        history = history.filter { seen.insert(Catalog.key($0)).inserted } // bỏ bài trùng (cùng bài, khác nguồn)
        player.volume = volume
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.time = t.seconds.isFinite ? t.seconds : 0
                if self.isPlaying, AudioSettings.shared.skipNonMusic,
                   let seg = self.skipSegments.first(where: { $0.contains(self.time) }) {
                    self.skipSegments.removeAll { $0 == seg }
                    Log.write("sponsorblock skip \(seg)")
                    if seg.upperBound >= self.duration - 1 { self.next() } else { self.seek(to: seg.upperBound) }
                    NotificationCenter.default.post(name: .skippedNonMusic, object: nil)
                    return
                }
                let known = self.current?.duration ?? 0
                if let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 {
                    // Luồng m4a dạng DASH có thể báo gấp đôi — tin thời lượng từ kho nhạc nếu có.
                    self.duration = known > 0 && d > known * 1.3 ? known : d
                }
                if self.isPlaying, known > 0, self.current?.isRemote == true, self.time >= known - 0.3,
                   (self.player.currentItem?.duration.seconds ?? 0) > known * 1.3 {
                    self.trackEnded()
                }
                self.updateNowPlaying()
                self.watchdog()
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated {
                guard let self, (n.object as? AVPlayerItem) === self.player.currentItem else { return }
                self.trackEnded()
            }
        }
        setupRemoteCommands()
        statusWatch = player.publisher(for: \.timeControlStatus).receive(on: RunLoop.main).sink { [weak self] s in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isBuffering = s == .waitingToPlayAtSpecifiedRate
                Log.write("player: \(["paused", "waiting", "playing"][s.rawValue]) \(self.player.reasonForWaitingToPlay?.rawValue ?? "")")
            }
        }
    }

    /// Kẹt: báo đang phát nhưng thời gian không chạy quá 12 giây → lấy link mới và thử lại (1 lần).
    private func watchdog() {
        guard isPlaying, !isResolving, current != nil else { lastProgress = .now; return }
        if abs(time - lastTime) > 0.05 { lastTime = time; lastProgress = .now; return }
        if player.timeControlStatus == .paused, player.currentItem?.status == .readyToPlay {
            // Bị dừng từ bên ngoài (tai nghe, AirPlay…) trong khi app vẫn báo đang phát → phát lại.
            Log.write("watchdog: player paused unexpectedly -> play()")
            player.play()
        }
        if Date().timeIntervalSince(lastProgress) > 12 {
            lastProgress = .now
            recover(reason: "stalled \(player.reasonForWaitingToPlay?.rawValue ?? "")")
        }
    }

    private func recover(reason: String) {
        guard let t = current else { return }
        Log.write("recover(\(reason)) '\(t.title)' retries=\(retries)")
        guard retries < 1, t.isRemote else {
            isPlaying = false
            player.pause()
            MusicLibrary.shared.message = L("Không phát được “\(t.title)”. Thử lại sau hoặc chọn bài khác.")
            return
        }
        retries += 1
        MusicLibrary.shared.invalidateStream(t)
        let at = time
        load(at: index, autoplay: true, keepRetries: true)
        if at > 1 { pendingSeek = at }
    }

    private var pendingSeek: Double?

    /// Theo dõi trạng thái bài vừa nạp: lỗi → thử lại; sẵn sàng → tua tới chỗ cũ nếu đang phục hồi.
    private func watch(_ item: AVPlayerItem, _ t: Track) {
        itemWatch = []
        item.publisher(for: \.status).receive(on: RunLoop.main).sink { [weak self] s in
            MainActor.assumeIsolated {
                guard let self, self.player.currentItem === item else { return }
                switch s {
                case .readyToPlay:
                    Log.write("item ready '\(t.title)'")
                    if let at = self.pendingSeek { self.pendingSeek = nil; self.seek(to: at) }
                    if self.isPlaying { self.player.play() }
                case .failed:
                    Log.write("item failed '\(t.title)': \(item.error?.localizedDescription ?? "?")")
                    self.recover(reason: "failed")
                default: break
                }
            }
        }.store(in: &itemWatch)
        NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item)
            .receive(on: RunLoop.main).sink { [weak self] n in
                MainActor.assumeIsolated {
                    let e = n.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                    Log.write("failedToPlayToEnd '\(t.title)': \(e?.localizedDescription ?? "?")")
                    self?.recover(reason: "failedToPlayToEnd")
                }
            }.store(in: &itemWatch)
    }

    var current: Track? { queue.indices.contains(index) ? MusicLibrary.shared.track(queue[index]) : nil }

    /// Các bài tiếp theo trong hàng đợi.
    var upNext: [(index: Int, track: Track)] {
        guard !queue.isEmpty else { return [] }
        return queue.indices.filter { $0 > index }.compactMap { i in
            MusicLibrary.shared.track(queue[i]).map { (i, $0) }
        }
    }

    func isCurrent(_ t: Track) -> Bool { current?.isSame(as: t) ?? false }

    // MARK: Điều khiển

    /// Phát danh sách, bắt đầu từ bài `startAt`.
    /// `context`: (khoá, tên hiển thị) của nơi phát — vd ("liked", "Bài hát đã thích").
    func play(_ tracks: [Track], startAt id: UUID? = nil, context: (key: String, title: String)? = nil) {
        guard !tracks.isEmpty else { return }
        MusicLibrary.shared.remember(tracks)
        var ids = tracks.map(\.id)
        var start = id.flatMap { ids.firstIndex(of: $0) } ?? (shuffle ? Int.random(in: ids.indices) : 0)
        unshuffled = shuffle ? ids : nil
        if shuffle {
            let first = ids.remove(at: start)
            ids.shuffle()
            ids.insert(first, at: 0)
            start = 0
        }
        queue = ids
        contextKey = context?.key
        contextTitle = context?.title
        load(at: start, autoplay: true)
    }

    func toggle() {
        guard current != nil else { return }
        Log.write(isPlaying ? "pause" : "play")
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        updateNowPlaying()
    }

    func next() {
        guard !queue.isEmpty else { return }
        if index + 1 < queue.count { load(at: index + 1, autoplay: true) }
        else if repeatMode == .all { load(at: 0, autoplay: true) }
        else if let cur = current, canAutoplay { autoplay(after: cur) }
        else { stopAtEnd() }
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if time > 3 || index == 0 { seek(to: 0) } else { load(at: index - 1, autoplay: isPlaying) }
    }

    func seek(to t: Double) {
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600))
        time = t
        updateNowPlaying()
    }

    func skip(by seconds: Double) { seek(to: min(max(time + seconds, 0), max(duration - 1, 0))) }

    func cycleRepeat() {
        repeatMode = switch repeatMode { case .off: .all; case .all: .one; case .one: .off }
    }

    func changeVolume(by delta: Float) { volume = min(max(volume + delta, 0), 1) }

    func stop() {
        player.replaceCurrentItem(with: nil)
        queue = []
        unshuffled = nil
        index = 0
        isPlaying = false
        time = 0
        duration = 0
        contextKey = nil
        contextTitle = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Hàng đợi

    func playQueueItem(at i: Int) { load(at: i, autoplay: true) }

    /// Phát ngay sau bài hiện tại.
    func playNext(_ t: Track) {
        MusicLibrary.shared.remember([t])
        guard !queue.isEmpty else { play([t]); return }
        queue.insert(t.id, at: index + 1)
        if let cur = current, var u = unshuffled {
            u.insert(t.id, at: (u.firstIndex(of: cur.id) ?? u.count - 1) + 1)
            unshuffled = u
        }
    }

    /// Thêm vào cuối danh sách chờ.
    func addToQueue(_ list: [Track]) {
        guard !list.isEmpty else { return }
        MusicLibrary.shared.remember(list)
        guard !queue.isEmpty else { play(list); return }
        queue += list.map(\.id)
        unshuffled? += list.map(\.id)
    }

    func removeUpcoming(at i: Int) {
        guard i > index, queue.indices.contains(i) else { return }
        let id = queue.remove(at: i)
        if var u = unshuffled, let j = u.lastIndex(of: id) { u.remove(at: j); unshuffled = u }
    }

    func clearUpcoming() {
        guard !queue.isEmpty else { return }
        queue = Array(queue.prefix(index + 1))
        unshuffled = shuffle ? queue : nil
    }

    func removeFromQueue(_ id: UUID) {
        unshuffled?.removeAll { $0 == id }
        guard let i = queue.firstIndex(of: id) else { return }
        let wasCurrent = i == index
        queue.remove(at: i)
        if i < index { index -= 1 }
        if wasCurrent {
            if queue.isEmpty { stop() } else { load(at: min(index, queue.count - 1), autoplay: isPlaying) }
        }
    }

    private func reshuffle() {
        guard queue.indices.contains(index) else { unshuffled = nil; return }
        let cur = queue[index]
        if shuffle {
            unshuffled = queue
            var rest = queue
            rest.remove(at: index)
            queue = [cur] + rest.shuffled()
            index = 0
        } else if let orig = unshuffled {
            queue = orig
            index = orig.firstIndex(of: cur) ?? 0
            unshuffled = nil
        }
    }

    // MARK: Tự động phát (hết danh sách → phát tiếp bài cùng gu, giống Spotify Autoplay)

    private var canAutoplay: Bool {
        MusicSettings.shared.autoplay && MusicSettings.shared.provider != .off
    }

    private func autoplay(after t: Track) {
        guard !extending else { return }
        extending = true
        isResolving = true
        Task {
            let more = (try? await YTM.related(to: t)) ?? []
            extending = false
            let played = Set(queue.compactMap { MusicLibrary.shared.track($0) }.map { $0.title.lowercased() })
            let fresh = more.filter { !played.contains($0.title.lowercased()) }
            guard !fresh.isEmpty, current?.id == t.id, index == queue.count - 1 else {
                isResolving = false
                if current?.id == t.id { stopAtEnd() }
                return
            }
            MusicLibrary.shared.remember(fresh)
            queue += fresh.map(\.id)
            unshuffled? += fresh.map(\.id)
            load(at: index + 1, autoplay: true)
        }
    }

    private func stopAtEnd() {
        player.pause()
        isPlaying = false
        seek(to: 0)
    }

    // MARK: Nạp bài

    private func load(at i: Int, autoplay: Bool, keepRetries: Bool = false) {
        guard queue.indices.contains(i) else { return }
        index = i
        guard let t = current else { removeFromQueue(queue[i]); return }
        if !keepRetries { retries = 0; pendingSeek = nil }
        lastProgress = .now
        lastTime = -1
        Log.write("load '\(t.title)' \(t.isRemote ? (t.remoteURL ?? "").prefix(60) : "file") autoplay=\(autoplay)")
        if autoplay { addToHistory(t) }
        loadSkipSegments(t)
        time = 0
        duration = t.duration
        isPlaying = autoplay
        if t.isRemote, let r = t.remoteURL, !r.hasPrefix("http") {
            player.replaceCurrentItem(with: nil)
            isResolving = true
            updateNowPlaying()
            Task {
                let info = await MusicLibrary.shared.streamInfo(t)
                guard queue.indices.contains(index), queue[index] == t.id else { return }
                isResolving = false
                Log.write(info == nil ? "resolve FAILED '\(t.title)'" : "resolve ok '\(t.title)' \(info!.url.host ?? "")")
                guard let info else {
                    MusicLibrary.shared.message = L("Không lấy được bài “\(t.title)” từ \(t.catalog ?? "nguồn").")
                    isPlaying = false
                    return
                }
                let asset = AVURLAsset(url: info.url, options: info.headers.isEmpty ? nil
                                       : ["AVURLAssetHTTPHeaderFieldsKey": info.headers])
                let item = AVPlayerItem(asset: asset)
                Equalizer.attach(to: item)
                player.replaceCurrentItem(with: item)
                watch(item, t)
                if isPlaying { player.play() }
            }
            return
        }
        isResolving = false
        let item = AVPlayerItem(url: MusicLibrary.shared.fileURL(t))
        Equalizer.attach(to: item)
        player.replaceCurrentItem(with: item)
        watch(item, t)
        if autoplay { player.play() }
        updateNowPlaying()
    }

    private func loadSkipSegments(_ t: Track) {
        skipSegments = []
        introSkip = 0
        skippedTotal = 0
        guard AudioSettings.shared.skipNonMusic, let id = YTM.videoID(of: t) else { return }
        Task {
            let segs = await SponsorBlock.shared.segments(videoID: id)
            guard current?.id == t.id else { return }
            skipSegments = segs
            introSkip = segs.first { $0.lowerBound < 1 }?.upperBound ?? 0
            skippedTotal = segs.reduce(0) { $0 + $1.upperBound - $1.lowerBound }
        }
    }

    private func trackEnded() {
        if repeatMode == .one { seek(to: 0); player.play() } else { next() }
    }

    private func addToHistory(_ t: Track) {
        let key = Catalog.key(t)
        history.removeAll { $0.isSame(as: t) || Catalog.key($0) == key }
        history.insert(t, at: 0)
        if history.count > 50 { history.removeLast(history.count - 50) }
        UserDefaults.standard.set(try? JSONEncoder().encode(history), forKey: "history")
    }

    // MARK: Phím media, Trung tâm điều khiển

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { if self?.isPlaying == false { self?.toggle() } }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { if self?.isPlaying == true { self?.toggle() } }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.toggle() }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.previous() }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.seek(to: e.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let t = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: time,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let img = MusicLibrary.shared.artwork(t) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
}

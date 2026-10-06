#if os(macOS)
import AppKit
import Darwin

// MARK: - Kết nối Discord qua IPC cục bộ ($TMPDIR/discord-ipc-N)

/// Giao thức: mỗi gói = opcode (Int32 LE) + độ dài (Int32 LE) + JSON.
/// op 0 = handshake, op 1 = frame (lệnh), op 2 = close.
/// Chỉ dùng trên hàng đợi riêng của `Presence` nên an toàn giữa các luồng.
final class DiscordIPC: @unchecked Sendable {
    private var fd: Int32 = -1
    private(set) var connected = false

    deinit { close() }

    func connect(clientID: String) -> Bool {
        close()
        let dirs = [ProcessInfo.processInfo.environment["TMPDIR"], NSTemporaryDirectory(), "/tmp/"].compactMap { $0 }
        for dir in dirs {
            for i in 0..<10 {
                let path = (dir as NSString).appendingPathComponent("discord-ipc-\(i)")
                guard FileManager.default.fileExists(atPath: path), open(path) else { continue }
                if handshake(clientID) { connected = true; return true }
                close()
            }
        }
        return false
    }

    private func open(_ path: String) -> Bool {
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return false }
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8.prefix(MemoryLayout.size(ofValue: addr.sun_path) - 1))
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        if !ok { Darwin.close(s); return false }
        fd = s
        return true
    }

    private func handshake(_ clientID: String) -> Bool {
        guard send(op: 0, ["v": 1, "client_id": clientID]),
              let reply = receive(), (reply["evt"] as? String) == "READY" else { return false }
        return true
    }

    /// nil = xoá trạng thái.
    @discardableResult
    func setActivity(_ activity: [String: Any]?) -> Bool {
        let ok = send(op: 1, [
            "cmd": "SET_ACTIVITY",
            "args": ["pid": Int(getpid()), "activity": activity ?? NSNull()] as [String: Any],
            "nonce": UUID().uuidString,
        ])
        if ok { _ = receive() } else { close() }
        return ok
    }

    func close() {
        if fd >= 0 { Darwin.close(fd) }
        fd = -1
        connected = false
    }

    private func send(op: Int32, _ payload: [String: Any]) -> Bool {
        guard fd >= 0, let json = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        var packet = Data()
        withUnsafeBytes(of: op.littleEndian) { packet.append(contentsOf: $0) }
        withUnsafeBytes(of: Int32(json.count).littleEndian) { packet.append(contentsOf: $0) }
        packet.append(json)
        let written = packet.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, packet.count) }
        return written == packet.count
    }

    private func receive() -> [String: Any]? {
        guard fd >= 0 else { return nil }
        var header = [UInt8](repeating: 0, count: 8)
        guard Darwin.read(fd, &header, 8) == 8 else { return nil }
        let length = Int(header[4]) | Int(header[5]) << 8 | Int(header[6]) << 16 | Int(header[7]) << 24
        guard length > 0, length < 1 << 20 else { return nil }
        var body = [UInt8](repeating: 0, count: length)
        var got = 0
        while got < length {
            let n = body.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress! + got, length - got) }
            if n <= 0 { return nil }
            got += n
        }
        return (try? JSONSerialization.jsonObject(with: Data(body))) as? [String: Any]
    }
}

// MARK: - "Đang nghe…" trên Discord

@MainActor
final class Presence: ObservableObject {
    static let shared = Presence()
    private let d = UserDefaults.standard

    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "rpcEnabled"); restart() } }
    @Published var appID: String { didSet { d.set(appID, forKey: "rpcAppID"); restart() } }
    @Published private(set) var status = L("Chưa bật")
    @Published private(set) var preview: (details: String, state: String)?

    private let ipc = DiscordIPC()
    private let queue = DispatchQueue(label: "muzify.discord")
    private var ticker: Timer?
    private var lastKey = ""
    private var lastSent = Date.distantPast

    private init() {
        enabled = d.bool(forKey: "rpcEnabled")
        appID = d.string(forKey: "rpcAppID") ?? ""
    }

    func start() { restart() }

    private func restart() {
        ticker?.invalidate()
        lastKey = ""
        let clear = !enabled || appID.trimmed.isEmpty
        queue.async { [ipc] in
            if ipc.connected { ipc.setActivity(nil) }
            if clear { ipc.close() }
        }
        guard !clear else { status = enabled ? L("Chưa nhập Application ID") : L("Chưa bật"); preview = nil; return }
        status = L("Đang kết nối…")
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.push() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
        push()
    }

    /// Gửi trạng thái mới nếu có thay đổi (Discord giới hạn ~5 lần / 20 giây).
    func push() {
        guard enabled, !appID.trimmed.isEmpty else { return }
        let activity = buildActivity()
        let details = activity?["details"] as? String ?? ""
        let state = activity?["state"] as? String ?? ""
        preview = activity == nil ? nil : (details, state)
        let ts = activity?["timestamps"] as? [String: Int]
        let key = "\(details)|\(state)|\((ts?["start"] ?? 0) / 10)"
        let now = Date()
        guard key != lastKey || now.timeIntervalSince(lastSent) > 60, now.timeIntervalSince(lastSent) > 4 else { return }
        lastKey = key
        lastSent = now

        let id = appID.trimmed
        queue.async { [weak self, ipc] in
            if !ipc.connected { _ = ipc.connect(clientID: id) }
            let ok = ipc.connected && ipc.setActivity(activity)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.status = ok ? L("Đã kết nối") : L("Không thấy Discord — hãy mở app Discord")
                    if !ok { self?.lastKey = "" }
                }
            }
        }
    }

    /// nil khi không phát nhạc (xoá trạng thái trên Discord).
    private func buildActivity() -> [String: Any]? {
        let player = MusicPlayer.shared
        guard player.isPlaying, let t = player.current else { return nil }
        let now = Int(Date().timeIntervalSince1970)
        var assets: [String: Any] = ["large_image": "logo", "large_text": "Muzify", "small_image": "logo", "small_text": "Muzify"]
        if let art = t.artworkURL, art.hasPrefix("http") {
            assets["large_image"] = art
        } else {
            // Chưa có link ảnh công khai → tìm rồi cập nhật lại ngay.
            Task { [weak self] in
                if await MusicLibrary.shared.publicArtworkURL(t) != nil { self?.lastKey = ""; self?.push() }
            }
        }
        assets["large_text"] = String(t.title.prefix(120))
        let start = now - Int(player.time)
        return [
            "type": 2, // Listening
            "details": String(t.title.prefix(120)),
            "state": L("của \(t.artist)").prefix(120).description,
            "timestamps": ["start": start, "end": start + Int(max(player.duration, t.duration))],
            "assets": assets,
        ]
    }
}
#endif

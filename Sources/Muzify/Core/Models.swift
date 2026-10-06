import Foundation

// MARK: - Bài hát

struct Track: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var artist: String
    var duration: Double = 0
    /// Tên tệp trong thư mục Tracks/ (rỗng = chưa tải về, phát online).
    var file: String
    /// Ảnh bìa đã lưu trong Artwork/.
    var artwork: String?
    /// Trang gốc (YouTube Music, SoundCloud, link người dùng dán…).
    var source: String?
    var addedAt = Date()
    /// Link phát online: "ytdlp:<trang>", "sc:<coding>|<auth>" hoặc link âm thanh trực tiếp.
    var remoteURL: String?
    /// Ảnh bìa trên mạng (dùng cho bài online và Discord).
    var artworkURL: String?
    /// Tên kho nhạc (YouTube Music, SoundCloud…).
    var catalog: String?
    /// Nằm trong "Bài hát đã thích".
    var liked = true

    /// Chưa tải về, phát trực tiếp từ mạng.
    var isRemote: Bool { file.isEmpty && remoteURL != nil }
    var isDownloaded: Bool { !file.isEmpty }
    /// Tệp người dùng tự nhập từ máy (không có nguồn online).
    var isLocalFile: Bool { !file.isEmpty && source == nil }

    var sourceHost: String? {
        guard let s = source, let host = URL(string: s)?.host else { return nil }
        return host.replacingOccurrences(of: "www.", with: "").replacingOccurrences(of: "m.", with: "")
    }

    /// Cùng một bài (cùng id, hoặc cùng trang nguồn — bài tìm thấy nhiều lần có id khác nhau).
    func isSame(as o: Track) -> Bool { id == o.id || (source != nil && source == o.source) }
}

struct Playlist: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var trackIDs: [UUID] = []
    var createdAt = Date()
}

struct Artist: Identifiable, Codable, Hashable {
    var name: String
    var art: String?
    var id: String { name.lowercased() }
}

struct DownloadJob: Identifiable {
    enum Status { case fetching, downloading, converting, failed }
    let id = UUID()
    let link: String
    var title: String
    /// Bài trong thư viện đang được tải về (nil = thêm bài mới).
    var trackID: UUID?
    var progress: Double = 0
    var status: Status = .fetching
    var error: String?
}

enum MusicError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m } else { return nil } }
}

func formatTime(_ t: Double) -> String {
    guard t.isFinite, t >= 0 else { return "0:00" }
    let s = Int(t.rounded())
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

/// "1 giờ 5 phút" / "3 phút 20 giây".
func formatLength(_ total: Double) -> String {
    let t = Int(total)
    let h = t / 3600, m = t / 60 % 60, s = t % 60
    return h > 0 ? L("\(h) giờ \(m) phút") : L("\(m) phút \(s) giây")
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}


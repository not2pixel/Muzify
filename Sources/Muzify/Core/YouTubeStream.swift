import Foundation

// MARK: - Lấy link phát YouTube trực tiếp (không cần yt-dlp) — chạy được cả trên iOS
//
// Cách làm giống yt-dlp (client "visionos"): lấy VISITOR_DATA từ trang youtube.com rồi gọi
// /youtubei/v1/player với client VISIONOS → link m4a phát trọn bài, không cần giải mã chữ ký hay PO token.
// YouTube đổi cách chặn thì sửa ở đây (trên Mac còn yt-dlp làm dự phòng).

actor YouTubeStream {
    static let shared = YouTubeStream()

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    private var visitor: (id: String, at: Date)?

    struct Audio {
        var url: URL
        var headers: [String: String]
        var title: String?
        var author: String?
        var duration: Double?
        var thumbnail: String?
    }

    /// ID khách (lưu 6 giờ).
    private func visitorData(refresh: Bool = false) async throws -> String {
        if !refresh, let v = visitor, Date().timeIntervalSince(v.at) < 6 * 3600 { return v.id }
        var req = URLRequest(url: URL(string: "https://www.youtube.com/")!)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("PREF=hl=en&tz=UTC; SOCS=CAI", forHTTPHeaderField: "Cookie")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        let html = String(decoding: data, as: UTF8.self)
        guard let r = html.range(of: #""VISITOR_DATA":"([^"]+)""#, options: .regularExpression) else {
            throw MusicError.message(L("YouTube: không lấy được mã khách."))
        }
        let id = String(html[r].dropFirst(16).dropLast(1))
        visitor = (id, .now)
        return id
    }

    /// Link âm thanh m4a tốt nhất của một video (AVPlayer không phát được opus/webm).
    func audio(videoID: String) async throws -> Audio {
        for attempt in 0..<2 {
            let vis = try await visitorData(refresh: attempt > 0)
            let body: [String: Any] = [
                "context": ["client": [
                    "clientName": "VISIONOS", "clientVersion": "1.02", "deviceMake": "Apple", "deviceModel": "RealityDevice17,1",
                    "userAgent": Self.userAgent, "osName": "visionOS", "osVersion": "26.5.23O471", "hl": "en",
                ]],
                "videoId": videoID, "contentCheckOk": true, "racyCheckOk": true,
            ]
            var req = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!)
            req.httpMethod = "POST"
            req.timeoutInterval = 15
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            for (k, v) in ["Content-Type": "application/json", "User-Agent": Self.userAgent, "X-Youtube-Client-Name": "101",
                           "X-Youtube-Client-Version": "1.02", "Origin": "https://www.youtube.com", "X-Goog-Visitor-Id": vis] {
                req.setValue(v, forHTTPHeaderField: k)
            }
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let status = (obj["playabilityStatus"] as? [String: Any])?["status"] as? String
            let formats = ((obj["streamingData"] as? [String: Any])?["adaptiveFormats"] as? [[String: Any]]) ?? []
            let audio = formats.filter { ($0["mimeType"] as? String)?.hasPrefix("audio/mp4") == true && $0["url"] != nil }
            guard let best = audio.max(by: { ($0["bitrate"] as? Int ?? 0) < ($1["bitrate"] as? Int ?? 0) }),
                  let s = best["url"] as? String, let url = URL(string: s) else {
                if status == "LOGIN_REQUIRED", attempt == 0 { continue } // mã khách hết hạn → lấy mã mới
                let reason = (obj["playabilityStatus"] as? [String: Any])?["reason"] as? String
                throw MusicError.message(reason ?? "YouTube: \(status ?? "?")")
            }
            let d = obj["videoDetails"] as? [String: Any]
            let thumbs = ((d?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]) ?? []
            return Audio(url: url, headers: ["User-Agent": Self.userAgent],
                         title: d?["title"] as? String, author: d?["author"] as? String,
                         duration: Double(d?["lengthSeconds"] as? String ?? ""), thumbnail: thumbs.last?["url"] as? String)
        }
        throw MusicError.message(L("YouTube từ chối phát video này."))
    }

    /// ID video từ link YouTube / YouTube Music (watch?v=, youtu.be/, shorts/, embed/).
    nonisolated static func videoID(from link: String) -> String? {
        guard let u = URL(string: link), let host = u.host?.lowercased() else { return nil }
        var id: String?
        if host.hasSuffix("youtu.be") { id = u.pathComponents.dropFirst().first }
        else if host.contains("youtube.com") {
            if let v = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value { id = v }
            else if let i = u.pathComponents.firstIndex(where: { ["shorts", "embed", "live"].contains($0) }), i + 1 < u.pathComponents.count {
                id = u.pathComponents[i + 1]
            }
        }
        guard let id, id.count == 11 else { return nil }
        return id
    }
}

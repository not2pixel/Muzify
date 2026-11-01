import CryptoKit
import Foundation
import Security

// MARK: - Tài khoản YouTube (gợi ý, bài đã thích, playlist theo tài khoản của bạn)
//
// Người dùng tự đăng nhập Google trong cửa sổ web của app; Muzify chỉ giữ cookie youtube.com
// (lưu trong Keychain, chỉ gửi tới youtube.com) và ký mỗi yêu cầu InnerTube bằng SAPISIDHASH
// — giống ytmusicapi. Không lưu mật khẩu.

enum YTAccount {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cookie: String? = Keychain.read()

    static var isSignedIn: Bool { lock.withLock { cookie != nil } }

    /// Lưu cookie (từ cửa sổ đăng nhập). Trả về false nếu chưa có cookie đăng nhập.
    @discardableResult
    static func save(_ cookies: [HTTPCookie]) -> Bool {
        let yt = cookies.filter { $0.domain.hasSuffix("youtube.com") }
        guard yt.contains(where: { $0.name == "SAPISID" || $0.name == "__Secure-3PAPISID" }) else { return false }
        return save(header: yt.map { "\($0.name)=\($0.value)" }.joined(separator: "; "))
    }

    /// Lưu chuỗi "Cookie:" dán từ trình duyệt.
    @discardableResult
    static func save(header raw: String) -> Bool {
        var h = raw.trimmed
        if h.lowercased().hasPrefix("cookie:") { h = String(h.dropFirst(7)).trimmed }
        guard value("SAPISID", in: h) != nil || value("__Secure-3PAPISID", in: h) != nil else { return false }
        lock.withLock { cookie = h }
        Keychain.write(h)
        return true
    }

    static func signOut() {
        lock.withLock { cookie = nil }
        Keychain.delete()
    }

    /// Header cần gửi kèm yêu cầu InnerTube (nil khi chưa đăng nhập).
    static func authHeaders(origin: String = "https://music.youtube.com") -> [String: String]? {
        guard let c = lock.withLock({ cookie }) else { return nil }
        let ts = Int(Date().timeIntervalSince1970)
        func hash(_ secret: String) -> String {
            let digest = Insecure.SHA1.hash(data: Data("\(ts) \(secret) \(origin)".utf8))
            return "\(ts)_" + digest.map { String(format: "%02x", $0) }.joined()
        }
        var parts: [String] = []
        if let s = value("SAPISID", in: c) ?? value("__Secure-3PAPISID", in: c) { parts.append("SAPISIDHASH \(hash(s))") }
        if let s = value("__Secure-1PAPISID", in: c) { parts.append("SAPISID1PHASH \(hash(s))") }
        if let s = value("__Secure-3PAPISID", in: c) { parts.append("SAPISID3PHASH \(hash(s))") }
        guard !parts.isEmpty else { return nil }
        return ["Cookie": c, "Authorization": parts.joined(separator: " "), "X-Origin": origin, "X-Goog-AuthUser": "0"]
    }

    private static func value(_ name: String, in header: String) -> String? {
        for part in header.components(separatedBy: ";") {
            let kv = part.trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2, kv[0] == name { return kv[1] }
        }
        return nil
    }

    /// Tên + ảnh đại diện của tài khoản đang đăng nhập.
    static func profile() async -> (name: String, photo: String?)? {
        guard isSignedIn, let obj = try? await YTM.call("account/account_menu", [:]),
              let header = YTM.all("activeAccountHeaderRenderer", in: obj).first else { return nil }
        return (YTM.runs(header["accountName"]).nilIfEmpty ?? "YouTube", YTM.thumb(header["accountPhoto"], size: 120))
    }
}

/// Lưu cookie trong Keychain (mã hoá bởi hệ thống, chỉ app này đọc được).
private enum Keychain {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                       kSecAttrService as String: "com.products.muzify.youtube",
                                       kSecAttrAccount as String: "cookie"]

    static func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func write(_ s: String) {
        delete()
        var q = query
        q[kSecValueData as String] = Data(s.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete() { SecItemDelete(query as CFDictionary) }
}

// MARK: - Trạng thái cho giao diện

@MainActor
final class AccountState: ObservableObject {
    static let shared = AccountState()
    @Published private(set) var signedIn = YTAccount.isSignedIn
    @Published private(set) var name: String?
    @Published private(set) var photo: String?

    private init() {
        if signedIn { refresh() }
    }

    func refresh() {
        signedIn = YTAccount.isSignedIn
        guard signedIn else { name = nil; photo = nil; return }
        Task {
            if let p = await YTAccount.profile() { name = p.name; photo = p.photo }
        }
    }

    /// Sau khi đăng nhập / đăng xuất: tải lại trang chủ theo tài khoản.
    func changed() {
        refresh()
        MusicHome.shared.reset()
        MusicHome.shared.load(force: true)
    }

    func signOut() {
        YTAccount.signOut()
        YTSync.shared.stop()
        changed()
    }
}

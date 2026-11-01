import SwiftUI
import WebKit

// MARK: - Đăng nhập YouTube (dùng chung Mac + iPhone/iPad)
//
// Trang đăng nhập của Google mở trong cửa sổ web riêng (không dùng chung cookie với Safari).
// Khi về tới music.youtube.com với cookie đăng nhập → lưu cookie (YTAccount) rồi đóng.

struct YouTubeLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manual = false
    @State private var pasted = ""
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Đăng nhập YouTube Music")).font(.system(size: 16, weight: .bold))
                    Text(L("Gợi ý, bài đã thích và playlist sẽ theo tài khoản của bạn. Muzify không lưu mật khẩu."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Huỷ")) { dismiss() }
            }
            .padding(14)

            if manual {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Mở music.youtube.com trong trình duyệt đã đăng nhập → Công cụ nhà phát triển → Network → chọn một yêu cầu tới music.youtube.com → copy giá trị header “Cookie” rồi dán vào đây."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    TextEditor(text: $pasted)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(minHeight: 140)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.4)))
                    if failed {
                        Text(L("Cookie không có thông tin đăng nhập (SAPISID). Kiểm tra lại.")).font(.caption).foregroundStyle(.red)
                    }
                    HStack {
                        Button(L("Quay lại đăng nhập")) { manual = false }
                        Spacer()
                        Button(L("Lưu")) {
                            if YTAccount.save(header: pasted) { finish() } else { failed = true }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pasted.trimmed.isEmpty)
                    }
                }
                .padding(14)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                GoogleLoginWebView { cookies in
                    if YTAccount.save(cookies) { finish() }
                }
                HStack {
                    Text(L("Google báo trình duyệt không an toàn?")).font(.system(size: 12)).foregroundStyle(.secondary)
                    Button(L("Dán cookie thay thế")) { manual = true }.font(.system(size: 12))
                    Spacer()
                }
                .padding(10)
            }
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 620, idealHeight: 700)
    }

    private func finish() {
        AccountState.shared.changed()
        UIState.shared.show(toast: L("Đã đăng nhập YouTube"))
        dismiss()
    }
}

/// Cửa sổ web đăng nhập Google → chuyển tới music.youtube.com.
struct GoogleLoginWebView {
    let onCookies: ([HTTPCookie]) -> Void

    static let start = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&passive=true&continue="
        + "https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Ddesktop%26next%3Dhttps%253A%252F%252Fmusic.youtube.com%252F")!

    func makeCoordinator() -> Coordinator { Coordinator(onCookies) }

    fileprivate func makeWebView(_ c: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        // Google chặn đăng nhập trong "trình duyệt nhúng" → tự nhận là Safari.
        web.customUserAgent = YouTubeStream.userAgent
        web.navigationDelegate = c
        web.load(URLRequest(url: Self.start))
        return web
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCookies: ([HTTPCookie]) -> Void
        private var done = false
        init(_ f: @escaping ([HTTPCookie]) -> Void) { onCookies = f }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !done, webView.url?.host?.contains("youtube.com") == true else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.done,
                      cookies.contains(where: { $0.domain.hasSuffix("youtube.com") && ($0.name == "SAPISID" || $0.name == "__Secure-3PAPISID") })
                else { return }
                self.done = true
                DispatchQueue.main.async { self.onCookies(cookies) }
            }
        }
    }
}

#if os(macOS)
extension GoogleLoginWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateNSView(_ v: WKWebView, context: Context) {}
}
#else
extension GoogleLoginWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateUIView(_ v: WKWebView, context: Context) {}
}
#endif

/// Dòng tài khoản trong Cài đặt: đăng nhập / tên tài khoản + đăng xuất.
struct AccountRow: View {
    @ObservedObject private var account = AccountState.shared
    @State private var login = false

    var body: some View {
        HStack(spacing: 12) {
            if account.signedIn {
                RemoteImage(url: account.photo, placeholder: "person.fill")
                    .frame(width: 36, height: 36).clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name ?? "YouTube").font(.system(size: 14, weight: .semibold))
                    Text(L("Gợi ý theo tài khoản YouTube của bạn")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Đăng xuất"), role: .destructive) { account.signOut() }
            } else {
                Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 26)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Chưa đăng nhập")).font(.system(size: 14, weight: .semibold))
                    Text(L("Đăng nhập để có gợi ý, bài đã thích và playlist như trên YouTube Music.")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Đăng nhập")) { login = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .sheet(isPresented: $login) { YouTubeLoginSheet() }
    }
}

/// Lời mời đăng nhập ở trang chủ (ẩn khi đã đăng nhập).
struct AccountPrompt: View {
    @ObservedObject private var account = AccountState.shared
    @AppStorage("hideAccountPrompt") private var hidden = false
    @State private var login = false

    var body: some View {
        if !account.signedIn && !hidden {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 22)).foregroundStyle(Brand.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Gợi ý giống tài khoản YouTube của bạn")).font(.system(size: 14, weight: .bold))
                    Text(L("Đăng nhập YouTube Music để trang chủ có Chọn nhanh, mix dành riêng, bài đã thích và playlist của bạn."))
                        .font(.system(size: 12)).foregroundStyle(MZ.subtext)
                }
                Spacer(minLength: 8)
                Button { login = true } label: {
                    Text(L("Đăng nhập")).font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 14).padding(.vertical, 7).background(Brand.accent, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                Button { hidden = true } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(MZ.subtext) }
                    .buttonStyle(.plain)
            }
            .padding(14)
            .background(MZ.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .sheet(isPresented: $login) { YouTubeLoginSheet() }
        }
    }
}

/// Đồng bộ với tài khoản YouTube (Cài đặt) — chỉ chạy khi bấm nút, dữ liệu trên máy là chính.
struct SyncStatusView: View {
    @ObservedObject private var account = AccountState.shared
    @ObservedObject private var sync = YTSync.shared
    @State private var confirmReplace = false

    var body: some View {
        if account.signedIn {
            HStack(spacing: 10) {
                if sync.syncing { ProgressView().controlSize(.small) }
                else { Image(systemName: sync.error == nil ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle.fill")
                    .foregroundStyle(sync.error == nil ? Brand.accent : .orange) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(sync.syncing ? L("Đang đồng bộ…")
                         : sync.lastSync.map { L("Đồng bộ lúc \($0.formatted(.dateTime.day().month().hour().minute().locale(.app)))") } ?? L("Chưa đồng bộ"))
                        .font(.system(size: 13, weight: .semibold))
                    if let e = sync.error { Text(e).font(.caption).foregroundStyle(.orange) }
                    else if let s = sync.summary { Text(s).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Button(L("Đồng bộ ngay")) { sync.syncNow() }.disabled(sync.syncing)
            }
            Button(L("Thay dữ liệu trên máy bằng dữ liệu YouTube…"), role: .destructive) { confirmReplace = true }
                .disabled(sync.syncing)
                .confirmationDialog(L("Thay dữ liệu trên máy bằng dữ liệu YouTube?"), isPresented: $confirmReplace) {
                    Button(L("Thay bằng dữ liệu YouTube"), role: .destructive) { sync.replaceWithYouTube() }
                    Button(L("Huỷ"), role: .cancel) {}
                } message: {
                    Text(L("Bài đã thích, playlist, nghệ sĩ, nhạc đã tải và lịch sử nghe trên máy sẽ được sao lưu rồi xoá; Muzify chỉ giữ dữ liệu từ tài khoản YouTube."))
                }
            Toggle(L("Ghi bài nghe trên Muzify vào lịch sử YouTube"), isOn: $sync.sendHistory)
        }
    }
}

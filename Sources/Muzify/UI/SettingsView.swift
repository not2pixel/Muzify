import SwiftUI

// MARK: - Cửa sổ Cài đặt

struct SettingsView: View {
    var body: some View {
        TabView {
            PlaybackSettings().tabItem { Label(L("Phát nhạc"), systemImage: "play.circle") }
            AudioSettingsView().tabItem { Label(L("Âm thanh"), systemImage: "slider.vertical.3") }
            LibrarySettings().tabItem { Label(L("Thư viện"), systemImage: "books.vertical") }
            DiscordSettings().tabItem { Label("Discord", systemImage: "bubble.left.and.bubble.right") }
        }
        .frame(width: 560)
    }
}

private struct PlaybackSettings: View {
    @ObservedObject private var settings = MusicSettings.shared

    var body: some View {
        Form {
            LanguageSection()

            Section {
                Picker(L("Kho nhạc"), selection: $settings.provider) {
                    ForEach(CatalogProvider.allCases) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.title)
                            Text(p.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(p)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text(L("Tìm kiếm & nghe online"))
            }

            if settings.provider == .custom {
                Section(L("API riêng")) {
                    TextField(L("Địa chỉ tìm kiếm"), text: $settings.customURL,
                              prompt: Text("https://api.example.com/search?q={query}"))
                    Text(L("""
                    Muzify gọi GET tới địa chỉ trên ({query} = từ khoá) và đọc mảng JSON \
                    (hoặc {"results": [...]}). Mỗi bài cần: "title", "artist", "url" (link âm thanh mp3/m4a), \
                    tuỳ chọn "artwork", "duration" (giây).
                    """))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle(L("Tự động phát"), isOn: $settings.autoplay)
            } footer: {
                Text(L("Hết danh sách thì tự phát tiếp bài tương tự."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 480)
    }
}

private struct LibrarySettings: View {
    @ObservedObject private var lib = MusicLibrary.shared

    var body: some View {
        Form {
            Section(L("Thư viện")) {
                LabeledContent(L("Bài hát đã thích"), value: "\(lib.liked.count)")
                LabeledContent(L("Đã tải xuống"), value: "\(lib.downloaded.count)")
                LabeledContent("Playlist", value: "\(lib.playlists.count)")
                Button(L("Mở thư mục nhạc trong Finder")) { NSWorkspace.shared.open(lib.dir) }
            }

            Section {
                LabeledContent("yt-dlp") {
                    switch lib.toolState {
                    case .ready: Text(L("Đã sẵn sàng")).foregroundStyle(.secondary)
                    case .installing: ProgressView().controlSize(.small)
                    case .missing: Button(L("Cài đặt"), action: lib.installTool)
                    }
                }
                if lib.toolState == .ready {
                    Button(L("Cập nhật yt-dlp lên bản mới nhất"), action: lib.installTool)
                }
                LabeledContent("ffmpeg", value: lib.ffmpegPath() == nil ? L("Không có (tuỳ chọn)") : L("Đã có"))
            } header: {
                Text(L("Công cụ"))
            } footer: {
                Text(L("""
                YouTube Music phát và tải trực tiếp, không cần cài gì thêm. yt-dlp (mã nguồn mở, tuỳ chọn) chỉ là dự phòng khi YouTube đổi cách chặn, và dùng để tải link từ trang web khác. ffmpeg (brew install ffmpeg) giúp tệp tải về chuẩn hơn.
                """))
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 480)
    }
}

private struct DiscordSettings: View {
    @ObservedObject private var rpc = Presence.shared

    var body: some View {
        Form {
            Section {
                Toggle(L("Hiện “Đang nghe…” trên Discord"), isOn: $rpc.enabled)
                TextField("Application ID", text: $rpc.appID, prompt: Text("VD: 1234567890123456789"))
                    .disabled(!rpc.enabled)
                LabeledContent(L("Trạng thái")) {
                    HStack(spacing: 6) {
                        Circle().fill(rpc.status == L("Đã kết nối") ? Color.green : .secondary).frame(width: 8, height: 8)
                        Text(rpc.status)
                    }
                }
                if let p = rpc.preview, rpc.enabled {
                    LabeledContent(L("Đang hiển thị")) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(p.details)
                            if !p.state.isEmpty { Text(p.state).foregroundStyle(.secondary) }
                        }
                    }
                }
            } footer: {
                Text(L("""
                Cách lấy Application ID (1 lần, miễn phí):
                1. Vào discord.com/developers/applications → New Application, đặt tên “Muzify” (tên này hiện trên Discord).
                2. Mục Rich Presence → Art Assets: tải ảnh icon lên với tên “logo”.
                3. Copy Application ID ở mục General Information và dán vào ô trên.
                Cần mở app Discord trên máy.
                """))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section {
                Link(L("Mở Discord Developer Portal"), destination: URL(string: "https://discord.com/developers/applications")!)
            }
        }
        .formStyle(.grouped)
        .frame(height: 480)
    }
}

private struct LanguageSection: View {
    @State private var language = AppLanguage.selected
    private let initial = AppLanguage.selected

    var body: some View {
        Section {
            Picker(L("Ngôn ngữ"), selection: $language) {
                ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: language) { _, v in AppLanguage.selected = v }
            if language != initial {
                HStack {
                    Text(L("Mở lại Muzify để đổi ngôn ngữ.")).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Mở lại ngay"), action: relaunch)
                }
            }
        }
    }

    private func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; open \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }
}

private struct AudioSettingsView: View {
    @ObservedObject private var audio = AudioSettings.shared
    @AppStorage("menuBarPlayer") private var menuBarPlayer = true

    var body: some View {
        Form {
            Section {
                Toggle(L("Bộ chỉnh âm (EQ)"), isOn: $audio.eqEnabled)
                Picker(L("Kiểu"), selection: Binding(get: { audio.preset }, set: { if let p = $0 { audio.apply(p) } })) {
                    ForEach(AudioSettings.Preset.allCases) { Text($0.title).tag(Optional($0)) }
                    if audio.preset == nil { Text(L("Tuỳ chỉnh")).tag(AudioSettings.Preset?.none) }
                }
                .disabled(!audio.eqEnabled)
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<10, id: \.self) { i in band(i) }
                }
                .frame(height: 170)
                .disabled(!audio.eqEnabled)
                .opacity(audio.eqEnabled ? 1 : 0.4)
            } footer: {
                Text(L("Áp dụng cho bài trên máy và bài YouTube Music; một số luồng SoundCloud không hỗ trợ."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(L("Tự cân âm lượng"), isOn: $audio.normalize)
                Toggle(L("Bỏ qua đoạn không phải nhạc"), isOn: $audio.skipNonMusic)
            } footer: {
                Text(L("Tự cân âm lượng giúp các bài to nhỏ đều nhau. Đoạn không phải nhạc (intro, đoạn nói trong MV…) lấy từ cộng đồng SponsorBlock."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(L("Hiện mini player trên thanh menu"), isOn: $menuBarPlayer)
            }
        }
        .formStyle(.grouped)
        .frame(height: 560)
    }

    private func band(_ i: Int) -> some View {
        let f = AudioSettings.frequencies[i]
        return VStack(spacing: 6) {
            Text(String(format: "%+.0f", audio.gains[i])).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(audio.gains[i]) }, set: { audio.gains[i] = Float(($0 * 2).rounded() / 2) }), in: -12...12)
                .rotationEffect(.degrees(-90))
                .frame(width: 110, height: 24)
                .frame(width: 40, height: 110)
            Text(f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))").font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

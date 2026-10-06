<p align="center">
  <img src="docs/images/icon.png" width="128" alt="Muzify">
</p>

<h1 align="center">Muzify</h1>

<p align="center">
  Trình phát nhạc miễn phí cho <b>macOS</b>, <b>iPhone</b> và <b>iPad</b>, giao diện kiểu Spotify.<br>
  Swift &amp; SwiftUI thuần · không cần tài khoản · thư viện nằm trên máy bạn.
</p>

<p align="center"><a href="README.md">English</a></p>

![Muzify trên macOS](docs/images/macos-home.png)

## Nền tảng

| Nền tảng | Trạng thái | Bố cục |
|---|---|---|
| **macOS 14+** (Apple Silicon & Intel) | Hỗ trợ | Bố cục Spotify desktop: Thư viện bên trái · nội dung · khung Đang phát · thanh phát, mini player trên thanh menu, cửa sổ nổi |
| **iPhone (iOS 17+)** | Hỗ trợ | Thanh tab (Trang chủ · Tìm kiếm · Thư viện), mini player trên thanh tab, màn Đang phát toàn màn hình |
| **iPad (iPadOS 17+)** | Hỗ trợ | Cột bên trái kiểu Spotify + nội dung, mini player, màn Đang phát toàn màn hình |

Bản iOS chạy độc lập, không cần app trên Mac.

## Tính năng

- **Tìm một lần, đủ mọi nguồn** — nhạc trên máy + YouTube Music trong một danh sách, bỏ bài trùng. Có thêm SoundCloud và API riêng.
- **Thích ≠ Tải xuống** (giống Spotify): ⊕ lưu bài vào thư viện và vẫn phát online; tải về để nghe offline là việc riêng, từng bài hoặc cả playlist.
- **Trang chủ**: mix theo nhạc bạn nghe, gợi ý, kệ nhạc YouTube Music, **bảng xếp hạng** (Apple Music Việt Nam, Deezer toàn cầu — dự phòng Apple Music Mỹ). Nguồn nào tải xong thì hiện trước.
- **Lời bài hát chạy theo nhạc** — ưu tiên YouTube Music (khớp đúng video đang phát), dự phòng LRCLIB, sáng từng dòng như karaoke, bấm vào dòng để tua. Tự canh lại khi intro bị bỏ qua.
- **Bỏ qua đoạn không phải nhạc** trong MV (intro, outro, đoạn nói) nhờ SponsorBlock.
- **Âm thanh**: EQ 10 dải có sẵn các kiểu, tự cân âm lượng, chọn loa AirPlay.
- **Danh sách chờ & tự động phát**: phát tiếp theo, thêm vào danh sách chờ, trộn bài (xếp lại ngay khi bật), lặp lại, hết danh sách thì phát tiếp bài tương tự.
- **Thư viện**: playlist (kéo để sắp xếp trên Mac), nghệ sĩ theo dõi, nhập tệp nhạc, dán link YouTube / YouTube Music / bài Spotify để tải.
- **Thẻ nghệ sĩ** có ảnh, số người hâm mộ (Deezer) và tiểu sử (Wikipedia).
- **Riêng Mac**: mini player trên thanh menu, cửa sổ nổi luôn ở trên, chế độ toàn màn hình, phím media, phím tắt kiểu Spotify (Space, ⌘← / ⌘→, ⌘↑ / ⌘↓, ⌘K…), trạng thái “Đang nghe…” trên Discord.
- **Tiếng Việt & English** — theo ngôn ngữ hệ thống hoặc chọn trong Cài đặt.

![Trang nghệ sĩ](docs/images/macos-artist.png)

## Build

### macOS

Chỉ cần Command Line Tools:

```bash
xcode-select --install        # nếu chưa có
git clone https://github.com/not2pixel/Muzify.git
cd Muzify
./build.sh --install          # build universal, cài vào /Applications
```

Chạy `./build.sh` (không kèm tham số) sẽ tạo `build/Muzify.app` và `build/Muzify.zip`. `swift run` để chạy nhanh khi phát triển.

### iPhone / iPad

Cần **Xcode** có bộ iOS. Cài một lần:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -downloadPlatform iOS
```

Rồi:

```bash
Scripts/build_ios.sh          # build/Muzify.ipa (chưa ký)
Scripts/build_ios.sh --sim    # build/Muzify-sim.app cho Simulator
Scripts/build_ios.sh --check  # kiểm tra kiểu mã iOS trên Mac, không cần Xcode
```

File `.ipa` chưa ký: cài bằng **PlayCover** (Mac Apple Silicon), **AltStore** hoặc **Sideloadly** (iPhone/iPad, Apple ID miễn phí thì 7 ngày ký lại một lần).

## Cách phát nhạc

Muzify đọc dữ liệu (tìm kiếm, trang chủ, bảng xếp hạng, playlist, lời bài hát) từ API web của YouTube Music và phát âm thanh từ link trực tiếp của YouTube, lấy bằng Swift (`Sources/Muzify/Core/YouTubeStream.swift`). Trên macOS có thể cài thêm [yt-dlp](https://github.com/yt-dlp/yt-dlp) (mã nguồn mở) trong Cài đặt làm dự phòng và để tải link từ trang web khác. ffmpeg (`brew install ffmpeg`) là tuỳ chọn.

## Cấu trúc

```
Sources/Muzify/          app macOS (Swift Package)
  Core/                  dùng chung với iOS: thư viện, trình phát, kho nhạc, lời bài hát, EQ, link YouTube…
  UI/                    giao diện macOS (Theme, AppState, Tracks dùng chung với iOS)
  App/                   điểm vào macOS, menu, phím tắt
Sources/MuzifyMobile/    giao diện iPhone / iPad
Resources/               Info.plist, icon, bản dịch (en.lproj, vi.lproj), iOS/
Scripts/                 build_ios.sh, l10n.py, en_strings.py, make_icon.swift
docs/                    ghi chú kiến trúc, ảnh chụp màn hình
```

Chi tiết: [docs/ARCHITECTURE.vi.md](docs/ARCHITECTURE.vi.md).

## Dữ liệu & quyền riêng tư

- Mọi thứ nằm trên máy: `~/Library/Application Support/Muzify/` trên macOS, thư mục của app trên iOS (xem được trong app Tệp). Không tài khoản, không máy chủ riêng, không thu thập dữ liệu.
- Cài đặt nằm trong `UserDefaults` (`com.products.muzify` / `com.products.muzify.ios`).
- Nhật ký phát nhạc để tìm lỗi: `~/Library/Logs/Muzify.log`.
- Chỉ kết nối mạng khi bạn dùng: YouTube Music / YouTube, SoundCloud, lời bài hát (LRCLIB), bảng xếp hạng (Apple Music RSS, Deezer), thông tin nghệ sĩ (Deezer, Wikipedia), SponsorBlock, Discord (IPC trên máy).

## Đóng góp

Muzify song ngữ. Chữ hiển thị viết tiếng Việt trong `L("…")`, bản tiếng Anh thêm vào `Scripts/en_strings.py`; tài liệu luôn đi đôi (`TEN.md` tiếng Anh + `TEN.vi.md` tiếng Việt). Trước khi gửi thay đổi:

```bash
python3 Scripts/l10n.py check     # thiếu 0 bản dịch
swift build                       # build macOS được
Scripts/build_ios.sh --check      # mã iOS hợp lệ
```

Quy tắc đầy đủ cho agent và người đóng góp: [CLAUDE.md](CLAUDE.md) (bản sao: [AGENTS.md](AGENTS.md)).

## Lưu ý

Muzify dùng giao diện web không chính thức của YouTube Music, YouTube và SoundCloud; các dịch vụ này có thể thay đổi bất cứ lúc nào. Chỉ tải nội dung bạn có quyền sử dụng. Lời bài hát từ [LRCLIB](https://lrclib.net) và YouTube Music; đoạn cần bỏ qua từ [SponsorBlock](https://sponsor.ajay.app).

Muzify là dự án cá nhân, không liên kết với Spotify, Apple, Google, SoundCloud, Deezer hay Discord.

## Giấy phép

[MIT](LICENSE)

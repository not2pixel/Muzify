# Kiến trúc Muzify

[English](ARCHITECTURE.md)

Muzify là app SwiftUI thuần. Bản macOS là một Swift Package (không có dự án Xcode); bản iOS được biên dịch từ cùng phần lõi bằng `swiftc` qua `Scripts/build_ios.sh`.

```
                 ┌──────────────────────── Lõi (macOS + iOS) ───────────────────────────┐
 Giao diện ──────┤ MusicLibrary  MusicPlayer  Catalog/YTM  LyricsStore  Equalizer  …  │
 (Mac / iOS)     └──────┬─────────────┬──────────────┬─────────────┬─────────────────────┘
                        │             │              │             │
                 library.json   AVPlayer + tap   YouTube Music   LRCLIB / YouTube Music
                 Tracks/        MPNowPlaying     link YouTube     (lời bài hát)
                 Artwork/       AirPlay          SoundCloud API
```

## Lõi (`Sources/Muzify/Core`) — dùng chung macOS và iOS

| Tệp | Nhiệm vụ |
|---|---|
| `Models.swift` | `Track`, `Playlist`, `Artist`, `DownloadJob`, hàm định dạng |
| `Library.swift` | `MusicLibrary`: bài đã thích, tải xuống, playlist, nghệ sĩ theo dõi, lấy link phát, nhập tệp & link. Phần yt-dlp nằm trong `#if os(macOS)` |
| `Player.swift` | `MusicPlayer`: AVPlayer, hàng đợi, trộn/lặp, tự động phát, bỏ đoạn SponsorBlock, tự phục hồi khi kẹt, phím media / Now Playing, audio session trên iOS |
| `YouTubeStream.swift` | Link âm thanh YouTube trực tiếp: lấy visitor ID từ youtube.com + `/youtubei/v1/player` với client VISIONOS → m4a phát trọn bài, không cần yt-dlp |
| `YTMusic.swift` | InnerTube của YouTube Music: tìm kiếm, bài tương tự ("radio"), playlist, kệ trang chủ, lời bài hát có/không mốc thời gian; `MusicHome` (trang chủ hiện dần + lưu bảng xếp hạng) |
| `Catalog.swift` | Các kho nhạc (tất cả nguồn, YouTube Music, SoundCloud, API riêng), tìm kiếm gộp bỏ trùng, bộ nhớ ảnh `RemoteArt`, SoundCloud API v2 |
| `Lyrics.swift` | `LyricsStore`: ưu tiên YouTube Music, dự phòng LRCLIB, đọc LRC, lưu đệm, tự bù lệch khi intro bị bỏ qua |
| `Equalizer.swift` | `AudioSettings` + `MTAudioProcessingTap`: EQ biquad 10 dải, tự cân âm lượng, chống vỡ tiếng |
| `Extras.swift` | Đoạn SponsorBlock, thông tin nghệ sĩ (Deezer + Wikipedia), bảng xếp hạng (Apple Music RSS, Deezer) |
| `Discord.swift` | Discord Rich Presence qua IPC cục bộ (chỉ macOS) |
| `Localization.swift` | `L("…")`, chọn ngôn ngữ app |
| `Platform.swift` | Khác biệt macOS/iOS: `PlatformImage`, mở link, sao chép |
| `Log.swift` | Nhật ký phát nhạc (`~/Library/Logs/Muzify.log`) |

### Nguồn của bài hát

`Track` có `file` rỗng thì phát từ `remoteURL`:

| Tiền tố | Ý nghĩa | Lấy link bằng |
|---|---|---|
| `ytdlp:<trang>` | Trang YouTube / YouTube Music (giữ tên cũ cho tương thích) | `YouTubeStream` → dự phòng yt-dlp trên macOS |
| `find:<nghệ sĩ> <tên bài>` | Bài trong bảng xếp hạng, chỉ có thông tin | Tìm trên YouTube Music (thời lượng gần nhất) → `YouTubeStream` |
| `sc:<coding>\|<auth>` | Bản phát của SoundCloud | SoundCloud API v2 → dự phòng yt-dlp trên macOS |
| `http…` | Link âm thanh trực tiếp (API riêng) | dùng luôn |

Thích một bài = thêm vào thư viện (vẫn phát online); tải xuống = lưu tệp vào `Tracks/` và giữ `remoteURL` để bỏ thích thì quay về phát online.

## Giao diện

- **macOS** — `Sources/Muzify/UI` + `App/MuzifyApp.swift`: thanh trên có Quay lại/Tiến tới và ô tìm kiếm, Thư viện bên trái, nội dung theo `Router`, khung Đang phát / Danh sách chờ, thanh phát, lời bài hát, toàn màn hình, mini player trên thanh menu và cửa sổ nổi, cửa sổ Cài đặt.
- **iPhone / iPad** — `Sources/MuzifyMobile`: thanh tab trên iPhone, `NavigationSplitView` trên iPad, mini player, màn Đang phát toàn màn hình, lời bài hát và danh sách chờ dạng sheet, Cài đặt. Điều hướng đẩy trang vào ngăn của từng tab (`MobileNav`); `Router.handler` chuyển các lệnh từ code dùng chung (vd "Chuyển tới nghệ sĩ") sang đó.
- **Giao diện dùng chung** — `UI/Theme.swift` (màu, nút, ảnh bìa, thanh tua), `UI/AppState.swift` (điều hướng, thông báo, tìm kiếm, thể loại), `UI/Tracks.swift` (nút thích, menu bài hát, thẻ).
- Modifier chỉ có trên iOS đi qua `MuzifyMobile/Compat.swift`, nhờ vậy `Scripts/build_ios.sh --check` kiểm tra kiểu được toàn bộ giao diện iOS ngay trên Mac, không cần iOS SDK.

## Song ngữ

Tiếng Việt là ngôn ngữ gốc: mọi chữ hiển thị là `L("…")` viết tiếng Việt, giá trị chèn vào thành `%@`. Bản tiếng Anh nằm trong `Scripts/en_strings.py`, sinh ra `Resources/en.lproj/Localizable.strings`. `Scripts/l10n.py check` dừng build nếu thiếu bản dịch hoặc chuỗi chưa bọc. Xem [CLAUDE.md](../CLAUDE.md).

## Lưu trữ

```
~/Library/Application Support/Muzify/      (iOS: thư mục của app)
  library.json     bài hát, playlist, nghệ sĩ theo dõi
  Tracks/          nhạc đã tải
  Artwork/         ảnh bìa đã tải
  Lyrics/          lời bài hát đã lưu
  charts.json      bảng xếp hạng lần trước (hiện ngay khi mở app)
  bin/ytdlp/       yt-dlp tuỳ chọn (macOS)
```

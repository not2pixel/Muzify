<!-- Bản sao của CLAUDE.md cho các agent khác (Codex, Cursor…). Sửa CLAUDE.md rồi chép lại: cp CLAUDE.md AGENTS.md -->
# Muzify — quy tắc cho agent / Agent rules

Muzify là app song ngữ **Tiếng Việt (gốc) + English**. Mọi thay đổi phải luôn có **đủ 2 bản**.
Muzify is bilingual: **Vietnamese (source) + English**. Every change must always ship **both versions**.

## 1. Chuỗi hiển thị trong app / UI strings

- Viết chuỗi gốc bằng **tiếng Việt** trong `L("…")` — kể cả trong `Text`, `Button`, `.help`, thông báo lỗi, toast, menu.
  Write the source string in **Vietnamese** inside `L("…")` — including `Text`, `Button`, `.help`, errors, toasts, menus.
- Không dùng chuỗi tiếng Việt trần (không bọc `L`) và không dùng `String(localized:)` / `LocalizedStringKey` cho chuỗi mới.
  No bare Vietnamese literals, and don't use `String(localized:)` / `LocalizedStringKey` for new strings.
- Thêm bản tiếng Anh vào `Scripts/en_strings.py` (khoá = chuỗi tiếng Việt, mỗi `\(…)` thành `%@`; đổi thứ tự thì dùng `%1$@`, `%2$@`), rồi chạy:
  Add the English text to `Scripts/en_strings.py` (key = Vietnamese string, each `\(…)` becomes `%@`; use `%1$@`, `%2$@` to reorder), then run:

  ```bash
  python3 Scripts/en_strings.py   # sinh Resources/en.lproj/Localizable.strings
  python3 Scripts/l10n.py check   # phải báo: thiếu 0 · chưa bọc 0 · sai %@ 0
  ```

- Cùng chữ tiếng Việt nhưng tiếng Anh khác nhau → thêm ngữ cảnh: `L("Nghệ sĩ##một người")` (phần `##…` không hiện ra).
  Same Vietnamese text but different English → add a context: `L("Nghệ sĩ##một người")` (the `##…` part is never shown).
- Chuỗi là **dữ liệu** (tìm kiếm, phân tích phản hồi YouTube Music…) không được dịch: ghi `// l10n:skip` cuối dòng.
  Strings that are **data** (search queries, parsing YouTube Music responses…) must not be translated: end the line with `// l10n:skip`.
- Ngày giờ dùng `Locale.app`, không cố định `vi_VN`. Dates use `Locale.app`, never a hard-coded locale.
- Không sửa tay `Resources/en.lproj/Localizable.strings` — nó được sinh từ `Scripts/en_strings.py`.
  Never hand-edit `Resources/en.lproj/Localizable.strings` — it's generated from `Scripts/en_strings.py`.

`./build.sh` tự chạy `l10n.py check` và **dừng build** nếu thiếu bản dịch.
`./build.sh` runs `l10n.py check` and **stops the build** if a translation is missing.

## 2. Tài liệu / Docs

- Mỗi tài liệu có 2 bản: `README.md` (English — bản GitHub hiển thị) và `README.vi.md` (Tiếng Việt). Sửa bản này thì sửa luôn bản kia trong cùng thay đổi.
  Every doc has two versions: `README.md` (English — shown on GitHub) and `README.vi.md` (Vietnamese). Update both in the same change.
- Tài liệu mới cũng vậy: `TEN.md` (English) + `TEN.vi.md`, vd `docs/ARCHITECTURE.md` + `docs/ARCHITECTURE.vi.md`.
  New docs follow the same pattern: `NAME.md` (English) + `NAME.vi.md`, e.g. `docs/ARCHITECTURE.md` + `docs/ARCHITECTURE.vi.md`.
- Ghi chú trong mã (comment) viết tiếng Việt như phần còn lại của mã nguồn.
  Code comments stay in Vietnamese, matching the rest of the codebase.

## 3. Mac + iPhone/iPad

- `Sources/Muzify/Core/*` và `UI/Theme.swift`, `UI/AppState.swift`, `UI/Tracks.swift` dùng chung cho Mac **và** iOS:
  không `import AppKit` trần, không dùng `NS…`; dùng `PlatformImage`, `Platform.open/copy` (`Core/Platform.swift`) hoặc `#if os(macOS)`.
  Shared files must build on both: no bare `import AppKit` or `NS…` types — use `PlatformImage`, `Platform.open/copy` or `#if os(macOS)`.
- Không gọi `Process` / yt-dlp ngoài `#if os(macOS)`. YouTube phát qua `YouTubeStream` trên cả hai nền tảng.
  Never call `Process` / yt-dlp outside `#if os(macOS)`. YouTube playback goes through `YouTubeStream` on both platforms.
- Giao diện iOS ở `Sources/MuzifyMobile/`; modifier chỉ có trên iOS phải đi qua `Compat.swift` để `--check` chạy được trên Mac.
  iOS UI lives in `Sources/MuzifyMobile/`; iOS-only modifiers go through `Compat.swift` so `--check` works on the Mac.
- Tính năng mới cho người dùng: làm cho cả Mac lẫn iPhone/iPad, hoặc ghi rõ lý do chỉ có trên một bên.
  New user-facing features: build them for both Mac and iPhone/iPad, or state why one side is excluded.

## 4. Kiểm tra trước khi xong / Before finishing

1. `python3 Scripts/l10n.py check` → thiếu 0 / missing 0
2. `swift build` không lỗi / builds cleanly
3. `Scripts/build_ios.sh --check` → mã iOS hợp lệ / iOS code type-checks
4. Nếu đổi giao diện: chạy thử cả 2 ngôn ngữ / if UI changed, try both languages:

   ```bash
   open build/Muzify.app --args -AppleLanguages "(en)"
   ```

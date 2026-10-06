# Muzify architecture

[Tiếng Việt](ARCHITECTURE.vi.md)

Muzify is a pure SwiftUI app. The macOS app is a Swift Package (no Xcode project); the iOS app is compiled from the same core with `swiftc` by `Scripts/build_ios.sh`.

```
                 ┌──────────────────────── Core (macOS + iOS) ─────────────────────────┐
 UI (Mac / iOS) ─┤ MusicLibrary  MusicPlayer  Catalog/YTM  LyricsStore  Equalizer  …  │
                 └──────┬─────────────┬──────────────┬─────────────┬─────────────────────┘
                        │             │              │             │
                 library.json   AVPlayer + tap   YouTube Music   LRCLIB / YouTube Music
                 Tracks/        MPNowPlaying     YouTube streams  (lyrics)
                 Artwork/       AirPlay          SoundCloud API
```

## Core (`Sources/Muzify/Core`) — shared by macOS and iOS

| File | Responsibility |
|---|---|
| `Models.swift` | `Track`, `Playlist`, `Artist`, `DownloadJob`, formatting helpers |
| `Library.swift` | `MusicLibrary`: liked songs, downloads, playlists, followed artists, stream resolution, file & link import. yt-dlp code is `#if os(macOS)` |
| `Player.swift` | `MusicPlayer`: AVPlayer, queue, shuffle/repeat, autoplay, SponsorBlock skipping, stall recovery, media keys / Now Playing, iOS audio session |
| `YouTubeStream.swift` | Direct YouTube audio URLs: visitor ID from youtube.com + `/youtubei/v1/player` with the VISIONOS client → full-length m4a streams, no yt-dlp |
| `YTMusic.swift` | YouTube Music InnerTube: search, related ("radio"), playlists, home shelves, timed/plain lyrics; `MusicHome` (progressive home page + cached charts) |
| `Catalog.swift` | Catalog providers (all sources, YouTube Music, SoundCloud, custom API), merged search with de-duplication, `RemoteArt` image cache, SoundCloud API v2 |
| `Lyrics.swift` | `LyricsStore`: YouTube Music first, LRCLIB fallback, LRC parsing, cache, automatic offset when an intro was skipped |
| `Equalizer.swift` | `AudioSettings` + `MTAudioProcessingTap`: 10-band biquad EQ, volume normalization, clipping guard |
| `Extras.swift` | SponsorBlock segments, artist info (Deezer + Wikipedia), charts (Apple Music RSS, Deezer) |
| `Discord.swift` | Discord Rich Presence over local IPC (macOS only) |
| `Localization.swift` | `L("…")` lookup, app language selection |
| `Platform.swift` | macOS/iOS differences: `PlatformImage`, open URL, copy to clipboard |
| `Log.swift` | Playback log (`~/Library/Logs/Muzify.log`) |

### Track sources

A `Track` with an empty `file` streams from `remoteURL`:

| Prefix | Meaning | Resolved by |
|---|---|---|
| `ytdlp:<page>` | YouTube / YouTube Music page (name kept for compatibility) | `YouTubeStream` → yt-dlp fallback on macOS |
| `find:<artist> <title>` | Chart entry with metadata only | YouTube Music search (closest duration) → `YouTubeStream` |
| `sc:<coding>\|<auth>` | SoundCloud transcoding | SoundCloud API v2 → yt-dlp fallback on macOS |
| `http…` | Direct audio URL (custom API) | used as is |

Liking a song inserts it into the library (still streaming); downloading stores the file in `Tracks/` and keeps `remoteURL` so unliking can fall back to streaming.

## User interface

- **macOS** — `Sources/Muzify/UI` + `App/MuzifyApp.swift`: top bar with back/forward and search, library sidebar, routed main view (`Router`), Now Playing / Queue panel, player bar, lyrics, full-screen player, menu-bar and floating mini players, Settings window.
- **iPhone / iPad** — `Sources/MuzifyMobile`: tab bar on iPhone, `NavigationSplitView` on iPad, mini player, full-screen Now Playing, lyrics and queue sheets, Settings. Navigation pushes onto per-tab stacks (`MobileNav`); `Router.handler` redirects shared code (e.g. "Go to artist") to it.
- **Shared UI** — `UI/Theme.swift` (colors, buttons, artwork, scrub bar), `UI/AppState.swift` (router, toasts, search model, genres), `UI/Tracks.swift` (like button, track menu, cards).
- iOS-only SwiftUI modifiers go through `MuzifyMobile/Compat.swift`, so `Scripts/build_ios.sh --check` can type-check the whole iOS UI on a Mac without the iOS SDK.

## Localization

Vietnamese is the source language: every UI string is `L("…")` with Vietnamese text, interpolations become `%@`. English lives in `Scripts/en_strings.py` and is generated into `Resources/en.lproj/Localizable.strings`. `Scripts/l10n.py check` fails the build on missing or unwrapped strings. See [CLAUDE.md](../CLAUDE.md).

## Storage

```
~/Library/Application Support/Muzify/      (iOS: app container)
  library.json     tracks, playlists, followed artists
  Tracks/          downloaded audio
  Artwork/         downloaded cover art
  Lyrics/          lyrics cache
  charts.json      last charts (shown instantly on launch)
  bin/ytdlp/       optional yt-dlp (macOS)
```

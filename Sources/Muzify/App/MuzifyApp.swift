import AppKit
import SwiftUI

@main
struct MuzifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage("menuBarPlayer") private var menuBarPlayer = true

    var body: some Scene {
        Window("Muzify", id: "main") {
            RootView()
                .frame(minWidth: 1000, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 880)
        .commands { MuzifyCommands() }

        // Cửa sổ nổi (mini player) — mở từ thanh phát hoặc thanh menu.
        Window("Muzify Mini", id: "mini") {
            MiniPlayerView(style: .window).preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        MenuBarExtra(isInserted: $menuBarPlayer) {
            MiniPlayerView(style: .menuBar).preferredColorScheme(.dark)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.appearance = NSAppearance(named: .darkAqua)
            _ = MusicLibrary.shared
            _ = MusicPlayer.shared
            Presence.shared.start()
        }
        // Phím cách = phát/tạm dừng (khi không gõ chữ), giống Spotify.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
            guard e.keyCode == 49, mods.isEmpty, !(NSApp.keyWindow?.firstResponder is NSText),
                  NSApp.keyWindow?.attachedSheet == nil else { return e }
            MainActor.assumeIsolated { MusicPlayer.shared.toggle() }
            return nil
        }
    }

    /// Đóng cửa sổ vẫn phát nhạc; bấm icon trên Dock thì mở lại.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

// MARK: - Menu

struct MuzifyCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(L("Playlist mới")) { UIState.shared.newPlaylist() }
                .keyboardShortcut("n")
            Button(L("Nhập tệp nhạc…")) { MusicLibrary.shared.importWithPanel() }
                .keyboardShortcut("o")
        }

        CommandMenu(L("Phát lại")) {
            Button(L("Phát / Tạm dừng")) { MusicPlayer.shared.toggle() }
                .keyboardShortcut(.space, modifiers: .option)
            Button(L("Bài tiếp")) { MusicPlayer.shared.next() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button(L("Bài trước")) { MusicPlayer.shared.previous() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button(L("Tua tới 10 giây")) { MusicPlayer.shared.skip(by: 10) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            Button(L("Tua lùi 10 giây")) { MusicPlayer.shared.skip(by: -10) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
            Divider()
            Button(L("Tăng âm lượng")) { MusicPlayer.shared.changeVolume(by: 0.1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button(L("Giảm âm lượng")) { MusicPlayer.shared.changeVolume(by: -0.1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Divider()
            Button(L("Trộn bài")) { MusicPlayer.shared.shuffle.toggle() }
                .keyboardShortcut("s")
            Button(L("Lặp lại")) { MusicPlayer.shared.cycleRepeat() }
                .keyboardShortcut("r")
            Divider()
            Button(L("Thích bài đang phát")) {
                if let t = MusicPlayer.shared.current { UIState.shared.toggleLike(t) }
            }
            .keyboardShortcut("b", modifiers: [.option, .shift])
        }

        CommandMenu(L("Đi tới")) {
            Button(L("Trang chủ")) { Router.shared.go(.home) }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Button(L("Tìm kiếm")) {
                Router.shared.go(.search)
                NotificationCenter.default.post(name: .focusSearch, object: nil)
            }
            .keyboardShortcut("k")
            Button(L("Bài hát đã thích")) { Router.shared.go(.liked) }
                .keyboardShortcut("s", modifiers: [.option, .shift])
            Divider()
            Button(L("Quay lại")) { Router.shared.back() }
                .keyboardShortcut("[")
            Button(L("Tiến tới")) { Router.shared.forward() }
                .keyboardShortcut("]")
            Divider()
            Button(L("Lời bài hát")) { UIState.shared.toggleLyrics() }
                .keyboardShortcut("l", modifiers: [.option, .command])
            Button(L("Danh sách chờ")) { UIState.shared.toggle(.queue) }
                .keyboardShortcut("q", modifiers: [.option, .command])
            Button(L("Khung đang phát")) { UIState.shared.toggle(.nowPlaying) }
                .keyboardShortcut("r", modifiers: [.option, .shift])
            Button(L("Thu gọn / mở rộng Thư viện")) { withAnimation(Brand.spring) { UIState.shared.libraryWide.toggle() } }
                .keyboardShortcut("l", modifiers: [.option, .shift])
        }
    }
}

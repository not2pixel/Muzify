import SwiftUI

// MARK: - Bố cục chính: thanh trên · Thư viện | Nội dung | Đang phát · thanh phát

struct RootView: View {
    @ObservedObject private var router = Router.shared
    @ObservedObject private var ui = UIState.shared
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var lib = MusicLibrary.shared

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            HStack(alignment: .top, spacing: 8) {
                LibrarySidebar()
                    .frame(width: ui.libraryWide ? 320 : 72)

                main
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(minWidth: 420)

                if ui.rightPanel != .none, player.current != nil {
                    RightPanelView()
                        .frame(width: 320)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 8)
            .animation(Brand.spring, value: ui.rightPanel)
            .animation(Brand.spring, value: ui.libraryWide)
            .animation(Brand.spring, value: player.current == nil)

            PlayerBar()
        }
        .background(MZ.base)
        .overlay(alignment: .bottom) {
            if let text = ui.toast {
                Text(text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(MZ.hex(0x2E77D0), in: RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if ui.fullScreen, player.current != nil {
                FullScreenPlayer().transition(.opacity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .skippedNonMusic)) { _ in
            ui.show(toast: L("Đã bỏ qua đoạn không phải nhạc"))
        }
        .onAppear {
            // Không tự focus ô tìm kiếm lúc mở app (để phím cách dùng phát/tạm dừng).
            DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
        }
        .sheet(item: $ui.renaming) { RenamePlaylistSheet(playlist: $0) }
        .sheet(item: $ui.editing) { EditTrackSheet(track: $0) }
        .alert("Muzify", isPresented: Binding(get: { lib.message != nil }, set: { if !$0 { lib.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lib.message ?? "")
        }
    }

    @ViewBuilder
    private var main: some View {
        ZStack {
            Group {
                switch router.current {
                case .home: HomeView()
                case .search: SearchView()
                case .liked: CollectionView(kind: .liked)
                case .playlist(let id): CollectionView(kind: .playlist(id)).id(id)
                case .remote(let target): RemotePageView(target: target).id(target)
                }
            }
            .transition(.opacity)

            if ui.showLyrics, player.current != nil {
                LyricsView()
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MZ.panel)
        .animation(Brand.spring, value: ui.showLyrics)
    }
}

// MARK: - Hộp thoại

struct RenamePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("Sửa thông tin chi tiết")).font(.system(size: 22, weight: .bold))
            HStack(alignment: .top, spacing: 16) {
                PlaylistCover(playlist: playlist, size: 140)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Tên")).font(.system(size: 11, weight: .bold)).foregroundStyle(MZ.subtext)
                    TextField(L("Thêm tên"), text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(10)
                        .background(MZ.elevatedHover, in: RoundedRectangle(cornerRadius: 4))
                        .onSubmit(save)
                }
            }
            HStack {
                Spacer()
                Button(L("Huỷ")) { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.plain).foregroundStyle(MZ.subtext)
                Button(action: save) {
                    Text(L("Lưu")).font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 28).padding(.vertical, 10).background(.white, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmed.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(MZ.elevated)
        .onAppear { name = playlist.name }
    }

    private func save() {
        MusicLibrary.shared.renamePlaylist(playlist.id, to: name)
        dismiss()
    }
}

struct EditTrackSheet: View {
    @Environment(\.dismiss) private var dismiss
    let track: Track
    @State private var title = ""
    @State private var artist = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ArtworkView(track: track, size: 56)
                Text(L("Sửa thông tin bài hát")).font(.headline)
            }
            TextField(L("Tên bài"), text: $title).textFieldStyle(.roundedBorder)
            TextField(L("Nghệ sĩ##một người"), text: $artist).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button(L("Huỷ")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Lưu")) {
                    MusicLibrary.shared.rename(track.id, title: title, artist: artist)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { title = track.title; artist = track.artist }
    }
}

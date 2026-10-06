import SwiftUI

// MARK: - Thanh trên cùng: ← → · Trang chủ + Tìm kiếm · Cài đặt

struct TopBar: View {
    @ObservedObject private var router = Router.shared

    var body: some View {
        ZStack {
            WindowDragArea()
            HStack(spacing: 8) {
                Color.clear.frame(width: 70, height: 1) // chừa chỗ cho nút đóng / thu nhỏ / phóng to
                NavArrow(symbol: "chevron.left", enabled: router.canGoBack, action: router.back)
                    .help(L("Quay lại"))
                NavArrow(symbol: "chevron.right", enabled: router.canGoForward, action: router.forward)
                    .help(L("Tiến tới"))
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                        .foregroundStyle(MZ.subtext)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(PressScaleStyle())
                .help(L("Cài đặt"))
                Text("M")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(MZ.hex(0xF573A0), in: Circle())
                    .padding(8)
                    .background(MZ.elevated, in: Circle())
                    .help("Muzify")
            }
            .padding(.horizontal, 12)

            HStack(spacing: 8) {
                HoverCircle(symbol: router.current == .home ? "house.fill" : "house", size: 48) { router.go(.home) }
                    .help(L("Trang chủ"))
                SearchCapsule()
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 200)
        }
        .frame(height: 64)
    }
}

private struct NavArrow: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(enabled ? MZ.text : MZ.subtext.opacity(0.5))
                .frame(width: 32, height: 32)
                .background(hovering && enabled ? MZ.elevatedHover : MZ.base.opacity(0.7), in: Circle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}

/// Ô "Bạn muốn phát nội dung gì?" — gõ để tìm, dán link để tải.
private struct SearchCapsule: View {
    @ObservedObject private var search = SearchModel.shared
    @ObservedObject private var router = Router.shared
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(hovering || router.current == .search ? MZ.text : MZ.subtext)
            PlainTextField(placeholder: L("Bạn muốn phát nội dung gì?"), text: $search.query, fontSize: 15,
                           focusOn: .focusSearch,
                           onBegin: { if router.current != .search { router.go(.search) } },
                           onSubmit: search.submit,
                           onEscape: { search.query = "" })
            if !search.query.isEmpty {
                if Catalog.looksLikeLink(search.query) {
                    Button(action: search.submit) {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 22)).foregroundStyle(Brand.accent)
                    }
                    .buttonStyle(PressScaleStyle())
                    .help(L("Tải bài hát từ link này"))
                    .transition(.scale.combined(with: .opacity))
                }
                Button { search.query = "" } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(MZ.subtext)
                }
                .buttonStyle(PressScaleStyle())
                .help(L("Xoá"))
            }
            Rectangle().fill(MZ.subtext.opacity(0.5)).frame(width: 1, height: 24)
            Button {
                search.query = ""
                router.go(.search)
            } label: {
                Image(systemName: router.current == .search ? "square.grid.2x2.fill" : "square.grid.2x2")
                    .font(.system(size: 18))
                    .foregroundStyle(router.current == .search ? MZ.text : MZ.subtext)
            }
            .buttonStyle(PressScaleStyle())
            .help(L("Duyệt tìm"))
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(hovering ? MZ.elevatedHover : MZ.elevated, in: Capsule())
        .overlay(Capsule().strokeBorder(router.current == .search ? MZ.text.opacity(0.9) : .clear, lineWidth: 2))
        .onHover { h in withAnimation(Brand.quick) { hovering = h } }
        .animation(Brand.quick, value: search.query.isEmpty)
    }
}

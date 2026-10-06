import AVKit
import SwiftUI

// MARK: - Bổ trợ iOS
// Các modifier chỉ có trên iOS được gói lại ở đây; trên Mac là "không làm gì" để có thể
// kiểm tra kiểu toàn bộ giao diện iOS ngay trên Mac (Scripts/build_ios.sh --check).

extension View {
    /// Tiêu đề nhỏ trên thanh điều hướng.
    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Tiêu đề lớn kiểu iOS.
    func largeTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }

    /// Thanh điều hướng trong suốt trên nền tối.
    func darkBars() -> some View {
        #if os(iOS)
        toolbarBackground(MZ.base, for: .navigationBar)
            .toolbarBackground(MZ.base.opacity(0.98), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        #else
        self
        #endif
    }

    /// Màn che toàn màn hình (iOS) / sheet (Mac).
    func fullCover<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }

    /// Không tự viết hoa / sửa chính tả (ô tìm kiếm, ô dán link).
    func plainInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self
        #endif
    }
}

#if os(iOS)
/// Nút chọn loa AirPlay / Bluetooth.
struct AirPlayRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor(white: 0.75, alpha: 1)
        v.activeTintColor = UIColor(red: 0x1E / 255, green: 0xD7 / 255, blue: 0x60 / 255, alpha: 1)
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}
#else
struct AirPlayRouteButton: View {
    var body: some View { Image(systemName: "airplayaudio") }
}
#endif

/// Rung nhẹ khi bấm (iOS).
@MainActor func haptic() {
    #if os(iOS)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    #endif
}

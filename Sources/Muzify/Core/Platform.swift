import SwiftUI
#if canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

// MARK: - Khác biệt Mac / iOS gom về một chỗ

extension Image {
    init(platformImage img: PlatformImage) {
        #if canImport(AppKit)
        self.init(nsImage: img)
        #else
        self.init(uiImage: img)
        #endif
    }
}

extension PlatformImage {
    var cgImageValue: CGImage? {
        #if canImport(AppKit)
        cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        cgImage
        #endif
    }
}

enum Platform {
    static var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    @MainActor static func open(_ url: URL) {
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    @MainActor static func copy(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

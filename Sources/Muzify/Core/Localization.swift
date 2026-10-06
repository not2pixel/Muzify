import Foundation

// MARK: - Song ngữ Tiếng Việt / English
//
// Chuỗi gốc viết bằng tiếng Việt trong `L("…")`; bản tiếng Anh nằm ở Resources/en.lproj/Localizable.strings.
// Mọi giá trị chèn vào (\(…)) đều thành %@ trong khoá, nên khoá luôn đoán được từ mã nguồn.
// Cùng chữ tiếng Việt nhưng tiếng Anh khác nhau → thêm ngữ cảnh sau "##", vd L("Nghệ sĩ##một người");
// phần "##…" không hiện ra khi chưa có bản dịch (tiếng Việt).
// Kiểm tra thiếu bản dịch: python3 Scripts/l10n.py check

struct LocalizedText: ExpressibleByStringInterpolation {
    var key: String
    var args: [String]

    init(stringLiteral value: String) {
        key = value.replacingOccurrences(of: "%", with: "%%")
        args = []
    }

    init(stringInterpolation s: Interpolation) {
        key = s.key
        args = s.args
    }

    struct Interpolation: StringInterpolationProtocol {
        var key = ""
        var args: [String] = []
        init(literalCapacity: Int, interpolationCount: Int) {}
        mutating func appendLiteral(_ literal: String) { key += literal.replacingOccurrences(of: "%", with: "%%") }
        mutating func appendInterpolation<T>(_ value: T) {
            key += "%@"
            args.append(String(describing: value))
        }
    }
}

/// Chuỗi hiển thị đã dịch theo ngôn ngữ của app.
func L(_ text: LocalizedText) -> String {
    let fallback = text.key.components(separatedBy: "##").first ?? text.key
    let format = Bundle.main.localizedString(forKey: text.key, value: fallback, table: nil)
    return String(format: format, arguments: text.args.map { $0 as CVarArg })
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, vi, en
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L("Theo hệ thống")
        case .vi: "Tiếng Việt"
        case .en: "English"
        }
    }

    /// Lựa chọn trong Cài đặt (áp dụng sau khi mở lại app).
    static var selected: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "appLanguage")
            if newValue == .system { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
            else { UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages") }
        }
    }

    /// Ngôn ngữ đang hiển thị: "vi" hoặc "en".
    static var current: String { Bundle.main.preferredLocalizations.first == "en" ? "en" : "vi" }
}

extension Locale {
    /// Định dạng ngày giờ theo ngôn ngữ của app.
    static var app: Locale { Locale(identifier: AppLanguage.current == "en" ? "en_US" : "vi_VN") }
}

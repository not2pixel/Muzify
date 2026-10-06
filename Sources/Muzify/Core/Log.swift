import Foundation

// MARK: - Nhật ký phát nhạc: ~/Library/Logs/Muzify.log (giữ ~1 MB gần nhất)

enum Log {
    private static let queue = DispatchQueue(label: "muzify.log")
    static let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/Muzify.log")

    static func write(_ message: String) {
        let line = "\(Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second().secondFraction(.fractional(3)))) \(message)\n"
        queue.async {
            let fm = FileManager.default
            if let size = try? fm.attributesOfItem(atPath: url.path)[.size] as? Int, size > 1_000_000 {
                try? fm.removeItem(at: url)
            }
            if !fm.fileExists(atPath: url.path) {
                try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                fm.createFile(atPath: url.path, contents: nil)
            }
            guard let h = try? FileHandle(forWritingTo: url) else { return }
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        }
    }
}

import Foundation

struct LiDARLabStorage {
    static let shared = LiDARLabStorage()

    let rootURL: URL
    let capturesURL: URL
    let roomsURL: URL
    let recordingsURL: URL
    let exportsURL: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        rootURL = documents.appendingPathComponent("LiDARLab", isDirectory: true)
        capturesURL = rootURL.appendingPathComponent("Captures", isDirectory: true)
        roomsURL = rootURL.appendingPathComponent("Rooms", isDirectory: true)
        recordingsURL = rootURL.appendingPathComponent("Recordings", isDirectory: true)
        exportsURL = rootURL.appendingPathComponent("Exports", isDirectory: true)
        try? ensureDirectories()
    }

    func ensureDirectories() throws {
        for url in [rootURL, capturesURL, roomsURL, recordingsURL, exportsURL] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    func timestampedName(prefix: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "\(prefix)-\(formatter.string(from: date))"
    }

    func sanitizedName(_ value: String, fallback: String = "Item") -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let parts = value.components(separatedBy: invalid)
        let result = parts.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? fallback : String(result.prefix(80))
    }

    func recursiveFiles(at url: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey])
            if values?.isRegularFile == true, values?.isHidden != true {
                files.append(fileURL)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    func directorySize(at url: URL) -> Int64 {
        recursiveFiles(at: url).reduce(0) { partial, fileURL in
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return partial + Int64(size)
        }
    }

    func modificationDate(at url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        return values?.contentModificationDate ?? values?.creationDate ?? .distantPast
    }
}

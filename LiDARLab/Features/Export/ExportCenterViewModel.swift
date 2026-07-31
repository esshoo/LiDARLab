import Combine
import Foundation

struct ExportCenterItem: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Identifiable {
        case capture
        case room
        case recording
        case report

        var id: String { rawValue }
        var title: String {
            switch self {
            case .capture: "صور العمق"
            case .room: "مسح الغرف"
            case .recording: "الجلسات"
            case .report: "التقارير"
            }
        }
        var systemImage: String {
            switch self {
            case .capture: "camera.filters"
            case .room: "house.lodge.fill"
            case .recording: "record.circle.fill"
            case .report: "doc.text.fill"
            }
        }
    }

    let url: URL
    let kind: Kind
    let modifiedAt: Date
    let sizeBytes: Int64
    let fileCount: Int

    var id: String { url.path }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var shareItems: [Any] {
        let files = LiDARLabStorage.shared.recursiveFiles(at: url)
        if !files.isEmpty { return files }
        return [url]
    }
}

private struct ExportCatalog: Codable {
    let generatedAt: Date
    let appVersion: String
    let itemCount: Int
    let totalSizeBytes: Int64
    let items: [ExportCatalogEntry]
}

private struct ExportCatalogEntry: Codable {
    let category: String
    let name: String
    let modifiedAt: Date
    let sizeBytes: Int64
    let fileCount: Int
    let relativePath: String
}

final class ExportCenterViewModel: ObservableObject {
    @Published private(set) var items: [ExportCenterItem] = []
    @Published private(set) var latestCatalogItems: [Any] = []
    @Published private(set) var statusMessage = "يعرض هذا المركز كل النتائج المحفوظة داخل التطبيق."
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?

    init() {
        refresh()
    }

    var totalSize: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    var totalFiles: Int { items.reduce(0) { $0 + $1.fileCount } }

    func refresh() {
        let storage = LiDARLabStorage.shared
        do {
            try storage.ensureDirectories()
            var scanned: [ExportCenterItem] = []
            scanned += scan(root: storage.capturesURL, kind: .capture)
            scanned += scan(root: storage.roomsURL, kind: .room)
            scanned += scan(root: storage.recordingsURL, kind: .recording)
            scanned += scan(root: storage.exportsURL, kind: .report)
            items = scanned.sorted { $0.modifiedAt > $1.modifiedAt }
            statusMessage = items.isEmpty
                ? "لا توجد ملفات محفوظة بعد."
                : "تم العثور على \(items.count) عنصر و\(totalFiles) ملف."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ item: ExportCenterItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(_ item: ExportCenterItem, to proposedName: String) {
        let storage = LiDARLabStorage.shared
        let cleanName = storage.sanitizedName(proposedName, fallback: item.name)
        let isDirectory = (try? item.url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let extensionPart = isDirectory ? "" : item.url.pathExtension
        let finalName = extensionPart.isEmpty ? cleanName : "\(cleanName).\(extensionPart)"
        let destination = item.url.deletingLastPathComponent()
            .appendingPathComponent(finalName, isDirectory: isDirectory)
        guard destination != item.url else { return }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            errorMessage = "يوجد عنصر آخر بالاسم نفسه."
            return
        }
        do {
            try FileManager.default.moveItem(at: item.url, to: destination)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createCatalog() {
        guard !isWorking else { return }
        isWorking = true
        latestCatalogItems = []
        let sourceItems = items.filter { $0.kind != .report }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let storage = LiDARLabStorage.shared
                try storage.ensureDirectories()
                let folder = storage.exportsURL.appendingPathComponent(
                    storage.timestampedName(prefix: "Catalog"),
                    isDirectory: true
                )
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

                let entries = sourceItems.map { item in
                    ExportCatalogEntry(
                        category: item.kind.title,
                        name: item.name,
                        modifiedAt: item.modifiedAt,
                        sizeBytes: item.sizeBytes,
                        fileCount: item.fileCount,
                        relativePath: item.url.path.replacingOccurrences(of: storage.rootURL.path + "/", with: "")
                    )
                }
                let catalog = ExportCatalog(
                    generatedAt: Date(),
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                    itemCount: entries.count,
                    totalSizeBytes: entries.reduce(0) { $0 + $1.sizeBytes },
                    items: entries
                )

                let jsonURL = folder.appendingPathComponent("catalog.json")
                let csvURL = folder.appendingPathComponent("catalog.csv")
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(catalog).write(to: jsonURL, options: .atomic)
                try self.makeCSV(entries).write(to: csvURL, atomically: true, encoding: .utf8)

                DispatchQueue.main.async {
                    self.isWorking = false
                    self.latestCatalogItems = [jsonURL, csvURL]
                    self.statusMessage = "تم إنشاء فهرس JSON وCSV ويمكن مشاركته الآن."
                    self.refresh()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func clearError() { errorMessage = nil }

    private func scan(root: URL, kind: ExportCenterItem.Kind) -> [ExportCenterItem] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
            guard values?.isDirectory == true || values?.isRegularFile == true else { return nil }
            let files = values?.isDirectory == true ? LiDARLabStorage.shared.recursiveFiles(at: url) : [url]
            let size: Int64 = values?.isDirectory == true
                ? LiDARLabStorage.shared.directorySize(at: url)
                : Int64(values?.fileSize ?? 0)
            return ExportCenterItem(
                url: url,
                kind: kind,
                modifiedAt: LiDARLabStorage.shared.modificationDate(at: url),
                sizeBytes: size,
                fileCount: files.count
            )
        }
    }

    private func makeCSV(_ entries: [ExportCatalogEntry]) -> String {
        var lines = ["category,name,modified_at,size_bytes,file_count,relative_path"]
        let formatter = ISO8601DateFormatter()
        for entry in entries {
            let values = [
                entry.category,
                entry.name,
                formatter.string(from: entry.modifiedAt),
                String(entry.sizeBytes),
                String(entry.fileCount),
                entry.relativePath
            ].map(csvEscape)
            lines.append(values.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

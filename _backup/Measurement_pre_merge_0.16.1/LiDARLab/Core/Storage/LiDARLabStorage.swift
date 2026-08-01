import Combine
import Foundation

enum ThreeEStorageSource: String {
    case appGroup
    case filesFolder
    case privateSandbox

    var title: String {
        switch self {
        case .appGroup: "App Group"
        case .filesFolder: "مجلد 3E في Files"
        case .privateSandbox: "مساحة التطبيق المؤقتة"
        }
    }

    var isShared: Bool {
        self != .privateSandbox
    }
}

enum ThreeEStorageError: LocalizedError {
    case selectedFolderIsNotThreeE
    case securityScopeUnavailable
    case bookmarkUnavailable
    case sharedFolderNotConnected
    case invalidRelativePath
    case pathOutsideRoot

    var errorDescription: String? {
        switch self {
        case .selectedFolderIsNotThreeE:
            return "اختر مجلد 3E نفسه، وليس مجلدًا داخله أو مجلدًا آخر."
        case .securityScopeUnavailable:
            return "تعذر الحصول على صلاحية دائمة لمجلد 3E. اختر المجلد من Files مرة أخرى."
        case .bookmarkUnavailable:
            return "تعذر حفظ صلاحية مجلد 3E."
        case .sharedFolderNotConnected:
            return "اربط مجلد 3E من Files أولًا لفتح هذا المسار المشترك."
        case .invalidRelativePath:
            return "المسار المطلوب غير صالح."
        case .pathOutsideRoot:
            return "تم رفض المسار لأنه يخرج خارج مجلد 3E."
        }
    }
}

final class LiDARLabStorage: ObservableObject {
    static let shared = LiDARLabStorage()

    @Published private(set) var source: ThreeEStorageSource = .privateSandbox
    @Published private(set) var needsFolderReselection = false
    @Published private(set) var statusMessage = "يعمل التطبيق حاليًا داخل مساحته الخاصة."
    @Published private(set) var lastErrorMessage: String?

    private struct StorageContext {
        let source: ThreeEStorageSource
        let threeERootURL: URL?
        let appRootURL: URL
    }

    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard
    private let contextLock = NSLock()
    private var context: StorageContext
    private var securityScopedURL: URL?
    private var securityScopeActive = false

    private init() {
        let privateRoot = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LiDARLab", isDirectory: true)
        context = StorageContext(
            source: .privateSandbox,
            threeERootURL: nil,
            appRootURL: privateRoot
        )
        bootstrapStorage()
    }

    deinit {
        releaseSecurityScope()
    }

    var rootURL: URL { currentContext().appRootURL }
    var threeERootURL: URL? { currentContext().threeERootURL }
    var capturesURL: URL { rootURL.appendingPathComponent("Captures", isDirectory: true) }
    var roomsURL: URL { rootURL.appendingPathComponent("Rooms", isDirectory: true) }
    var recordingsURL: URL { rootURL.appendingPathComponent("Recordings", isDirectory: true) }
    var exportsURL: URL { rootURL.appendingPathComponent("Exports", isDirectory: true) }
    var projectsURL: URL { rootURL.appendingPathComponent("Projects", isDirectory: true) }

    var isSharedFolderConnected: Bool {
        source.isShared && threeERootURL != nil
    }

    func connectToSelectedThreeEFolder(_ selectedURL: URL) throws {
        guard selectedURL.lastPathComponent.caseInsensitiveCompare("3E") == .orderedSame else {
            throw ThreeEStorageError.selectedFolderIsNotThreeE
        }

        let didStart = selectedURL.startAccessingSecurityScopedResource()
        guard didStart else {
            throw ThreeEStorageError.securityScopeUnavailable
        }

        do {
            let bookmark = try selectedURL.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: [.isDirectoryKey, .nameKey],
                relativeTo: nil
            )
            guard !bookmark.isEmpty else {
                throw ThreeEStorageError.bookmarkUnavailable
            }

            let newContext = StorageContext(
                source: .filesFolder,
                threeERootURL: selectedURL,
                appRootURL: selectedURL.appendingPathComponent(ThreeEStorageConstants.appRelativePath, isDirectory: true)
            )
            try prepare(context: newContext)

            let oldURL = securityScopedURL
            let oldWasActive = securityScopeActive
            setContext(newContext)
            securityScopedURL = selectedURL
            securityScopeActive = true
            defaults.set(bookmark, forKey: ThreeEStorageConstants.bookmarkDefaultsKey)

            if oldWasActive, let oldURL {
                oldURL.stopAccessingSecurityScopedResource()
            }

            needsFolderReselection = false
            lastErrorMessage = nil
            statusMessage = "تم ربط مجلد 3E وتسجيل تطبيق 3ELiDAR بنجاح."
        } catch {
            selectedURL.stopAccessingSecurityScopedResource()
            throw error
        }
    }

    func ensureDirectories() throws {
        try prepare(context: currentContext())
    }

    func clearLastError() {
        lastErrorMessage = nil
    }

    func clearFolderReselectionRequest() {
        needsFolderReselection = false
    }

    func urlForValidatedRelativePath(_ relativePath: String) throws -> URL {
        guard let sharedRoot = threeERootURL else {
            throw ThreeEStorageError.sharedFolderNotConnected
        }
        return try Self.safeURL(relativePath: relativePath, under: sharedRoot)
    }

    func relativePath(for url: URL) -> String? {
        if let sharedRoot = threeERootURL,
           let relative = Self.relativePath(of: url, under: sharedRoot) {
            return relative
        }
        return Self.relativePath(of: url, under: rootURL)
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
        guard let enumerator = fileManager.enumerator(
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

    private func bootstrapStorage() {
        if let groupRoot = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: ThreeEStorageConstants.futureAppGroupIdentifier
        ) {
            let groupContext = StorageContext(
                source: .appGroup,
                threeERootURL: groupRoot,
                appRootURL: groupRoot.appendingPathComponent(ThreeEStorageConstants.appRelativePath, isDirectory: true)
            )
            if (try? prepare(context: groupContext)) != nil {
                setContext(groupContext)
                source = .appGroup
                statusMessage = "يستخدم التطبيق App Group المشترك."
                return
            }
        }

        if restoreFilesBookmark() {
            return
        }

        let restoreFailed = needsFolderReselection
        do {
            try prepare(context: context)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        source = .privateSandbox
        if !restoreFailed {
            statusMessage = "يعمل التطبيق داخل مساحته الخاصة مؤقتًا حتى تختار مجلد 3E."
        }
    }

    private func restoreFilesBookmark() -> Bool {
        guard let bookmark = defaults.data(forKey: ThreeEStorageConstants.bookmarkDefaultsKey) else {
            return false
        }

        do {
            var isStale = false
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            guard resolvedURL.lastPathComponent.caseInsensitiveCompare("3E") == .orderedSame else {
                throw ThreeEStorageError.selectedFolderIsNotThreeE
            }
            guard resolvedURL.startAccessingSecurityScopedResource() else {
                throw ThreeEStorageError.securityScopeUnavailable
            }

            do {
                let restoredContext = StorageContext(
                    source: .filesFolder,
                    threeERootURL: resolvedURL,
                    appRootURL: resolvedURL.appendingPathComponent(ThreeEStorageConstants.appRelativePath, isDirectory: true)
                )
                try prepare(context: restoredContext)
                setContext(restoredContext)
                securityScopedURL = resolvedURL
                securityScopeActive = true
                source = .filesFolder
                statusMessage = "تمت استعادة صلاحية مجلد 3E تلقائيًا."
                needsFolderReselection = false

                if isStale {
                    let refreshedBookmark = try resolvedURL.bookmarkData(
                        options: [.minimalBookmark],
                        includingResourceValuesForKeys: [.isDirectoryKey, .nameKey],
                        relativeTo: nil
                    )
                    defaults.set(refreshedBookmark, forKey: ThreeEStorageConstants.bookmarkDefaultsKey)
                }
                return true
            } catch {
                resolvedURL.stopAccessingSecurityScopedResource()
                throw error
            }
        } catch {
            defaults.removeObject(forKey: ThreeEStorageConstants.bookmarkDefaultsKey)
            needsFolderReselection = true
            lastErrorMessage = error.localizedDescription
            statusMessage = "تعذر استعادة مجلد 3E. اختر المجلد نفسه من Files مرة أخرى."
            return false
        }
    }

    private func prepare(context: StorageContext) throws {
        if let sharedRoot = context.threeERootURL {
            try fileManager.createDirectory(at: sharedRoot, withIntermediateDirectories: true)
            try fileManager.createDirectory(
                at: sharedRoot.appendingPathComponent("Apps", isDirectory: true),
                withIntermediateDirectories: true
            )
            for relativePath in ThreeEStorageConstants.sharedSubdirectories {
                let url = relativePath.split(separator: "/").reduce(sharedRoot) {
                    $0.appendingPathComponent(String($1), isDirectory: true)
                }
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }

        try fileManager.createDirectory(at: context.appRootURL, withIntermediateDirectories: true)
        for directoryName in ThreeEStorageConstants.appSubdirectories {
            try fileManager.createDirectory(
                at: context.appRootURL.appendingPathComponent(directoryName, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        if let sharedRoot = context.threeERootURL {
            try ThreeERegistry.registerLiDARApp(in: sharedRoot)
        }
    }

    private func currentContext() -> StorageContext {
        contextLock.lock()
        defer { contextLock.unlock() }
        return context
    }

    private func setContext(_ newContext: StorageContext) {
        contextLock.lock()
        context = newContext
        contextLock.unlock()
        source = newContext.source
    }

    private func releaseSecurityScope() {
        if securityScopeActive, let securityScopedURL {
            securityScopedURL.stopAccessingSecurityScopedResource()
        }
        securityScopeActive = false
        securityScopedURL = nil
    }

    private static func safeURL(relativePath: String, under rootURL: URL) throws -> URL {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("\\"),
              !trimmed.contains("\\"),
              !trimmed.contains(":") else {
            throw ThreeEStorageError.invalidRelativePath
        }

        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ThreeEStorageError.invalidRelativePath
        }

        let candidate = components.reduce(rootURL.standardizedFileURL) {
            $0.appendingPathComponent($1)
        }.standardizedFileURL

        let canonicalRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let canonicalCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        guard canonicalCandidate == canonicalRoot || canonicalCandidate.path.hasPrefix(rootPath) else {
            throw ThreeEStorageError.pathOutsideRoot
        }
        return candidate
    }

    private static func relativePath(of url: URL, under rootURL: URL) -> String? {
        let root = rootURL.standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        guard candidate == root || candidate.hasPrefix(root + "/") else { return nil }
        if candidate == root { return "" }
        return String(candidate.dropFirst(root.count + 1))
    }
}

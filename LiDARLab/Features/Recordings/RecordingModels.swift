import Foundation

struct RecordedFrameMetadata: Codable, Identifiable, Hashable {
    let index: Int
    let relativeTimestamp: Double
    let colorFile: String
    let heatMapFile: String
    let depthFile: String
    let depthWidth: Int
    let depthHeight: Int
    let centerDistanceMeters: Float?
    let minimumDistanceMeters: Float?
    let maximumDistanceMeters: Float?
    let cameraTransformColumnMajor: [Float]
    let cameraIntrinsicsColumnMajor: [Float]
    let trackingState: String

    var id: Int { index }
}

struct RecordedSessionManifest: Codable, Hashable {
    let formatVersion: Int
    let name: String
    let createdAt: Date
    let endedAt: Date
    let requestedFramesPerSecond: Double
    let smoothedDepth: Bool
    let droppedFrames: Int
    let frames: [RecordedFrameMetadata]

    var duration: TimeInterval {
        frames.last?.relativeTimestamp ?? max(0, endedAt.timeIntervalSince(createdAt))
    }
}

struct RecordedSessionSummary: Identifiable, Hashable {
    let folderURL: URL
    let manifestURL: URL
    let manifest: RecordedSessionManifest
    let sizeBytes: Int64

    var id: String { folderURL.path }
    var title: String { manifest.name }
    var createdAt: Date { manifest.createdAt }
    var frameCount: Int { manifest.frames.count }
    var duration: TimeInterval { manifest.duration }

    var shareItems: [Any] {
        let files = LiDARLabStorage.shared.recursiveFiles(at: folderURL)
        return files.isEmpty ? [folderURL] : files
    }

    static func load(from folderURL: URL) throws -> RecordedSessionSummary {
        let manifestURL = folderURL.appendingPathComponent("session.json")
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(RecordedSessionManifest.self, from: data)
        return RecordedSessionSummary(
            folderURL: folderURL,
            manifestURL: manifestURL,
            manifest: manifest,
            sizeBytes: LiDARLabStorage.shared.directorySize(at: folderURL)
        )
    }

    static func loadAll() -> [RecordedSessionSummary] {
        let storage = LiDARLabStorage.shared
        try? storage.ensureDirectories()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: storage.recordingsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            return try? load(from: url)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }
}

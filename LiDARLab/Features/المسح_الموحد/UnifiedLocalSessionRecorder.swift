import Foundation

actor UnifiedLocalSessionRecorder {
    enum RecorderError: LocalizedError {
        case documentsUnavailable
        case notStarted

        var errorDescription: String? {
            switch self {
            case .documentsUnavailable: "تعذر الوصول إلى مجلد Documents."
            case .notStarted: "لم يبدأ تسجيل جلسة محلية."
            }
        }
    }

    private var fileHandle: FileHandle?
    private var sessionDirectory: URL?
    private var metadata: [String: Any] = [:]
    private var packetCount: UInt64 = 0
    private var byteCount: UInt64 = 0
    private var flushEveryPackets = 30
    private var packetsSinceFlush = 0
    private var synchronizeOnFlush = false

    func start(
        sessionID: UInt64,
        role: UnifiedDeviceRole,
        scanMode: UnifiedScanMode,
        flushEveryPackets: Int,
        synchronizeOnFlush: Bool,
        captureSettings: [String: Any] = [:]
    ) throws -> URL {
        try closeHandleIfNeeded()
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw RecorderError.documentsUnavailable
        }
        let root = documents
            .appendingPathComponent("3ELiDAR", isDirectory: true)
            .appendingPathComponent("Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let baseName = "\(formatter.string(from: Date()))_\(sessionID)"
        var directory = root.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 1
        while FileManager.default.fileExists(atPath: directory.path) {
            directory = root.appendingPathComponent("\(baseName)_\(suffix)", isDirectory: true)
            suffix += 1
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let rawURL = directory.appendingPathComponent("raw_stream.3eld")
        FileManager.default.createFile(atPath: rawURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: rawURL)
        sessionDirectory = directory
        packetCount = 0
        byteCount = 0
        packetsSinceFlush = 0
        self.flushEveryPackets = max(1, flushEveryPackets)
        self.synchronizeOnFlush = synchronizeOnFlush
        metadata = [
            "format": "3ELiDAR Session",
            "format_version": 1,
            "protocol_version": 1,
            "session_id": sessionID,
            "role": role.rawValue,
            "scan_mode": scanMode.rawValue,
            "state": "recording",
            "started_at": ISO8601DateFormatter().string(from: Date()),
            "raw_stream_file": "raw_stream.3eld",
            "capture_settings": captureSettings
        ]
        try writeMetadata()
        return directory
    }

    func append(_ packet: Data) throws {
        guard let fileHandle else { throw RecorderError.notStarted }
        try fileHandle.write(contentsOf: packet)
        packetCount &+= 1
        byteCount &+= UInt64(packet.count)
        packetsSinceFlush += 1
        if packetsSinceFlush >= flushEveryPackets {
            if synchronizeOnFlush {
                try fileHandle.synchronize()
            }
            packetsSinceFlush = 0
        }
    }

    func markState(_ state: String) throws {
        metadata["state"] = state
        try writeMetadata()
    }

    func finish(reason: String) throws -> URL? {
        guard sessionDirectory != nil else { return nil }
        metadata["state"] = "finished"
        metadata["finish_reason"] = reason
        metadata["finished_at"] = ISO8601DateFormatter().string(from: Date())
        metadata["packet_count"] = packetCount
        metadata["byte_count"] = byteCount
        try fileHandle?.synchronize()
        try fileHandle?.close()
        fileHandle = nil
        try writeMetadata()
        return sessionDirectory
    }

    func currentDirectory() -> URL? {
        sessionDirectory
    }

    func counters() -> (packets: UInt64, bytes: UInt64) {
        (packetCount, byteCount)
    }

    private func writeMetadata() throws {
        guard let sessionDirectory else { return }
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: sessionDirectory.appendingPathComponent("session.json"), options: .atomic)
    }

    private func closeHandleIfNeeded() throws {
        if let fileHandle {
            try fileHandle.synchronize()
            try fileHandle.close()
        }
        fileHandle = nil
    }
}

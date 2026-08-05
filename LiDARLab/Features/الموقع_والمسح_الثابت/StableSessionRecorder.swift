import Foundation

struct StableRecorderSnapshot: Sendable {
    let packets: UInt64
    let bytes: UInt64
}

final class StableSessionRecorder: @unchecked Sendable {
    enum RecorderError: LocalizedError {
        case documentsUnavailable
        case sessionAlreadyOpen
        case sessionNotOpen

        var errorDescription: String? {
            switch self {
            case .documentsUnavailable: "تعذر الوصول إلى مجلد Documents."
            case .sessionAlreadyOpen: "هناك جلسة تسجيل مفتوحة بالفعل."
            case .sessionNotOpen: "لا توجد جلسة تسجيل مفتوحة."
            }
        }
    }

    private let queue = DispatchQueue(label: "com.essam.3elidar.stable-recorder", qos: .userInitiated)
    private var fileHandle: FileHandle?
    private var sessionDirectory: URL?
    private var metadata: [String: Any] = [:]
    private var packetCount: UInt64 = 0
    private var byteCount: UInt64 = 0
    private var packetsSinceSync = 0
    private var writeError: Error?

    var onStatistics: (@Sendable (StableRecorderSnapshot) -> Void)?
    var onError: (@Sendable (String) -> Void)?

    func start(
        sessionID: UInt64,
        mode: StableScanMode,
        captureSettings: [String: Any]
    ) throws -> URL {
        try queue.sync {
            guard fileHandle == nil else { throw RecorderError.sessionAlreadyOpen }
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
            packetsSinceSync = 0
            writeError = nil
            metadata = [
                "format": "3ELiDAR Session",
                "format_version": 1,
                "protocol_version": 1,
                "stable_core_version": "0.5.0",
                "session_id": sessionID,
                "scan_mode": mode.rawValue,
                "state": "recording",
                "started_at": ISO8601DateFormatter().string(from: Date()),
                "raw_stream_file": "raw_stream.3eld",
                "capture_settings": captureSettings,
                "data_policy": "append_only_no_silent_deletion"
            ]
            try writeMetadataLocked()
            return directory
        }
    }

    /// Enqueues an append on a dedicated serial queue. Capture never waits for disk I/O.
    func append(_ packet: Data) {
        queue.async { [weak self] in
            guard let self, self.writeError == nil, let fileHandle = self.fileHandle else { return }
            do {
                try fileHandle.write(contentsOf: packet)
                self.packetCount &+= 1
                self.byteCount &+= UInt64(packet.count)
                self.packetsSinceSync += 1

                // Synchronisation changes durability only; no packet is removed or truncated.
                if self.packetsSinceSync >= 60 {
                    try fileHandle.synchronize()
                    self.packetsSinceSync = 0
                }

                if self.packetCount.isMultiple(of: 15) {
                    self.onStatistics?(StableRecorderSnapshot(packets: self.packetCount, bytes: self.byteCount))
                }
            } catch {
                self.writeError = error
                self.onError?(error.localizedDescription)
            }
        }
    }

    func markState(_ state: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.metadata["state"] = state
            try? self.writeMetadataLocked()
        }
    }

    func finish(
        reason: String,
        diagnostics: [String: Any],
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                if let writeError = self.writeError { throw writeError }
                guard let directory = self.sessionDirectory, let fileHandle = self.fileHandle else {
                    throw RecorderError.sessionNotOpen
                }

                self.metadata["state"] = "finished"
                self.metadata["finish_reason"] = reason
                self.metadata["finished_at"] = ISO8601DateFormatter().string(from: Date())
                self.metadata["packet_count"] = self.packetCount
                self.metadata["byte_count"] = self.byteCount
                self.metadata["diagnostics"] = diagnostics

                try fileHandle.synchronize()
                try fileHandle.close()
                self.fileHandle = nil
                try self.writeMetadataLocked()
                self.onStatistics?(StableRecorderSnapshot(packets: self.packetCount, bytes: self.byteCount))
                completion(.success(directory))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func abort() {
        queue.async { [weak self] in
            guard let self else { return }
            try? self.fileHandle?.synchronize()
            try? self.fileHandle?.close()
            self.fileHandle = nil
            self.metadata["state"] = "aborted"
            self.metadata["finished_at"] = ISO8601DateFormatter().string(from: Date())
            try? self.writeMetadataLocked()
        }
    }

    func currentSnapshot() -> StableRecorderSnapshot {
        queue.sync { StableRecorderSnapshot(packets: packetCount, bytes: byteCount) }
    }

    private func writeMetadataLocked() throws {
        guard let sessionDirectory else { return }
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: sessionDirectory.appendingPathComponent("session.json"), options: .atomic)
    }
}

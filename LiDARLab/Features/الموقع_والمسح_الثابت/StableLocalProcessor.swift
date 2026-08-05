import Foundation
import simd

final class StableLocalProcessor: @unchecked Sendable {
    enum ProcessorError: LocalizedError {
        case rawFileMissing
        case truncatedStream
        case invalidPacket
        case invalidPose
        case invalidScan

        var errorDescription: String? {
            switch self {
            case .rawFileMissing: "ملف raw_stream.3eld غير موجود."
            case .truncatedStream: "نهاية ملف الجلسة غير مكتملة."
            case .invalidPacket: "تم العثور على حزمة غير صالحة داخل الجلسة."
            case .invalidPose: "حزمة Pose غير صالحة."
            case .invalidScan: "حزمة Depth 2D غير صالحة."
            }
        }
    }

    private struct PacketHeader {
        let type: UInt16
        let flags: UInt32
        let frameID: UInt64
        let timestampNanoseconds: UInt64
        let payloadSize: Int
    }

    private struct CellKey: Hashable {
        let ix: Int
        let iz: Int
    }

    private struct Evidence {
        var hits = 0
        var frameCount = 0
        var lastFrameID: UInt64 = .max
        var minimumY = Float.greatestFiniteMagnitude
        var maximumY = -Float.greatestFiniteMagnitude
        var confidenceSum = 0
    }

    var onProgress: (@Sendable (Double, String) -> Void)?

    func process(
        sessionDirectory: URL,
        mode: StableScanMode,
        completion: @escaping @Sendable (Result<StableProcessingResult, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                completion(.success(try self.processSynchronously(sessionDirectory: sessionDirectory, mode: mode)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func processSynchronously(sessionDirectory: URL, mode: StableScanMode) throws -> StableProcessingResult {
        let started = CFAbsoluteTimeGetCurrent()
        let rawURL = sessionDirectory.appendingPathComponent("raw_stream.3eld")
        guard FileManager.default.fileExists(atPath: rawURL.path) else { throw ProcessorError.rawFileMissing }

        let fileSize = (try? rawURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let handle = try FileHandle(forReadingFrom: rawURL)
        defer { try? handle.close() }

        var poses: [UInt64: StablePoseSample] = [:]
        poses.reserveCapacity(12_000)
        var evidence: [CellKey: Evidence] = [:]
        var pathSegments: [StablePathSegment] = []
        var breakPoints: [StableBreakPoint] = []
        var lastPathPose: StablePoseSample?
        var currentSegmentID = 0
        var currentBreakID = 0
        var posePackets = 0
        var scanPackets = 0
        var matchedScans = 0
        var unmatchedScans = 0
        var acceptedPoints = 0
        var bytesRead = 0
        let cellSize: Float = 0.10

        while let headerData = try readExact(handle, count: 40, allowEndOfFile: true) {
            bytesRead += headerData.count
            let header = try parseHeader(headerData)
            guard let payload = try readExact(handle, count: header.payloadSize, allowEndOfFile: false) else {
                throw ProcessorError.truncatedStream
            }
            bytesRead += payload.count

            switch header.type {
            case StreamingMessageType.pose.rawValue:
                let pose = try decodePose(payload, header: header)
                poses[header.frameID] = pose
                posePackets += 1
                appendPathPose(
                    pose,
                    segments: &pathSegments,
                    breaks: &breakPoints,
                    lastPose: &lastPathPose,
                    segmentID: &currentSegmentID,
                    breakID: &currentBreakID
                )

            case StreamingMessageType.scan2D.rawValue:
                scanPackets += 1
                guard let pose = poses[header.frameID] else {
                    unmatchedScans += 1
                    continue
                }
                matchedScans += 1
                acceptedPoints += try accumulateScan(
                    payload,
                    flags: header.flags,
                    frameID: header.frameID,
                    pose: pose,
                    cellSize: cellSize,
                    evidence: &evidence
                )

            default:
                break
            }

            if fileSize > 0, (posePackets + scanPackets).isMultiple(of: 100) {
                onProgress?(min(0.98, Double(bytesRead) / Double(fileSize)), "قراءة الجلسة الخام")
            }
        }

        onProgress?(0.98, "تجهيز نتيجة المعالجة")
        let structuralCells = evidence.compactMap { key, value -> StableProcessedCell? in
            let verticalSpan = value.maximumY - value.minimumY
            guard value.hits >= 6, value.frameCount >= 2, verticalSpan >= 0.35 else { return nil }
            return StableProcessedCell(
                ix: key.ix,
                iz: key.iz,
                hits: value.hits,
                frameCount: value.frameCount,
                minimumY: value.minimumY,
                maximumY: value.maximumY,
                averageConfidence: value.hits > 0 ? Float(value.confidenceSum) / Float(value.hits) : 0
            )
        }

        let durationMS = (CFAbsoluteTimeGetCurrent() - started) * 1_000
        let summary = StableProcessingSummary(
            mode: mode.rawValue,
            posePackets: posePackets,
            scanPackets: scanPackets,
            matchedScans: matchedScans,
            unmatchedScans: unmatchedScans,
            acceptedPoints: acceptedPoints,
            rawEvidenceCells: evidence.count,
            structuralCells: structuralCells.count,
            pathSegments: pathSegments.count,
            trackingBreaks: breakPoints.count,
            processingDurationMilliseconds: durationMS,
            axisConvention: "ARKit world X/Z; viewer maps forward (-Z) upward"
        )

        let runDirectory = try createRunDirectory(in: sessionDirectory)
        try writeResultFiles(
            runDirectory: runDirectory,
            summary: summary,
            cells: structuralCells,
            pathSegments: pathSegments,
            breakPoints: breakPoints,
            cellSize: cellSize
        )
        onProgress?(1.0, "اكتملت المعالجة")
        return StableProcessingResult(
            runDirectory: runDirectory,
            summary: summary,
            cells: structuralCells,
            pathSegments: pathSegments,
            breakPoints: breakPoints
        )
    }

    private func parseHeader(_ data: Data) throws -> PacketHeader {
        guard data.count == 40,
              data.starts(with: [0x33, 0x45, 0x4C, 0x44]),
              data.readUInt16(at: 4) == 1,
              let type = data.readUInt16(at: 6),
              let flags = data.readUInt32(at: 8),
              let frameID = data.readUInt64(at: 20),
              let timestamp = data.readUInt64(at: 28),
              let payloadSize = data.readUInt32(at: 36),
              payloadSize <= 128 * 1024 * 1024 else {
            throw ProcessorError.invalidPacket
        }
        return PacketHeader(
            type: type,
            flags: flags,
            frameID: frameID,
            timestampNanoseconds: timestamp,
            payloadSize: Int(payloadSize)
        )
    }

    private func decodePose(_ payload: Data, header: PacketHeader) throws -> StablePoseSample {
        guard payload.count == 32,
              let px = payload.readFloat(at: 0),
              let py = payload.readFloat(at: 4),
              let pz = payload.readFloat(at: 8),
              let qx = payload.readFloat(at: 12),
              let qy = payload.readFloat(at: 16),
              let qz = payload.readFloat(at: 20),
              let qw = payload.readFloat(at: 24) else {
            throw ProcessorError.invalidPose
        }
        return StablePoseSample(
            frameID: header.frameID,
            timestampSeconds: Double(header.timestampNanoseconds) / 1_000_000_000,
            timestampNanoseconds: header.timestampNanoseconds,
            px: px,
            py: py,
            pz: pz,
            quaternion: StableQuaternion(simd_quatf(ix: qx, iy: qy, iz: qz, r: qw)),
            trackingState: payload[28],
            trackingReason: 0,
            worldMappingStatus: 0,
            thermalState: payload[29]
        )
    }

    private func accumulateScan(
        _ payload: Data,
        flags: UInt32,
        frameID: UInt64,
        pose: StablePoseSample,
        cellSize: Float,
        evidence: inout [CellKey: Evidence]
    ) throws -> Int {
        guard payload.count >= 28,
              let sourceWidthValue = payload.readUInt16(at: 0),
              let sourceHeightValue = payload.readUInt16(at: 2),
              let gridWidthValue = payload.readUInt16(at: 4),
              let gridHeightValue = payload.readUInt16(at: 6),
              let strideXValue = payload.readUInt16(at: 8),
              let strideYValue = payload.readUInt16(at: 10),
              let fx = payload.readFloat(at: 12),
              let fy = payload.readFloat(at: 16),
              let cx = payload.readFloat(at: 20),
              let cy = payload.readFloat(at: 24),
              fx != 0, fy != 0 else {
            throw ProcessorError.invalidScan
        }

        let sourceWidth = Int(sourceWidthValue)
        let sourceHeight = Int(sourceHeightValue)
        let gridWidth = Int(gridWidthValue)
        let gridHeight = Int(gridHeightValue)
        let strideX = Int(strideXValue)
        let strideY = Int(strideYValue)
        let sampleCount = gridWidth * gridHeight
        let confidenceIncluded = (flags & 1) != 0
        let depthOffset = 28
        let confidenceOffset = depthOffset + sampleCount * 2
        let expected = confidenceOffset + (confidenceIncluded ? sampleCount : 0)
        guard sourceWidth > 0, sourceHeight > 0, gridWidth > 0, gridHeight > 0,
              strideX > 0, strideY > 0, sampleCount <= 200_000, payload.count == expected else {
            throw ProcessorError.invalidScan
        }

        let rotation = pose.quaternion.simdValue
        var accepted = 0
        for gridY in 0..<gridHeight {
            let pixelY = min(gridY * strideY, sourceHeight - 1)
            for gridX in 0..<gridWidth {
                let index = gridY * gridWidth + gridX
                guard let millimeters = payload.readUInt16(at: depthOffset + index * 2) else { continue }
                let depth = Float(millimeters) / 1_000
                guard depth >= 0.15, depth <= 5.0 else { continue }
                let confidence = confidenceIncluded ? Int(payload[confidenceOffset + index]) : 1
                guard confidence >= 1 else { continue }

                let pixelX = min(gridX * strideX, sourceWidth - 1)
                let cameraPoint = SIMD3<Float>(
                    (Float(pixelX) - cx) / fx * depth,
                    -(Float(pixelY) - cy) / fy * depth,
                    -depth
                )
                let world = pose.position + rotation.act(cameraPoint)
                let relativeY = world.y - pose.py
                // Keep likely vertical structures and reject most floor/ceiling evidence.
                guard relativeY >= -0.75, relativeY <= 1.45 else { continue }

                let key = CellKey(ix: Int(floor(world.x / cellSize)), iz: Int(floor(world.z / cellSize)))
                var cell = evidence[key] ?? Evidence()
                cell.hits += 1
                if cell.lastFrameID != frameID {
                    cell.frameCount += 1
                    cell.lastFrameID = frameID
                }
                cell.minimumY = min(cell.minimumY, world.y)
                cell.maximumY = max(cell.maximumY, world.y)
                cell.confidenceSum += confidence
                evidence[key] = cell
                accepted += 1
            }
        }
        return accepted
    }

    private func appendPathPose(
        _ pose: StablePoseSample,
        segments: inout [StablePathSegment],
        breaks: inout [StableBreakPoint],
        lastPose: inout StablePoseSample?,
        segmentID: inout Int,
        breakID: inout Int
    ) {
        guard pose.trackingState == 2 else {
            lastPose = pose
            return
        }

        var breakReason: String?
        if let previous = lastPose, previous.trackingState == 2 {
            let dt = pose.timestampSeconds - previous.timestampSeconds
            let distance = simd_distance(pose.position, previous.position)
            let speed = dt > 0 ? distance / Float(dt) : Float.greatestFiniteMagnitude
            if dt <= 0 || dt > 0.20 {
                breakReason = "فجوة زمنية"
            } else if distance > 0.75 || speed > 4.0 {
                breakReason = "قفزة Pose مسجلة"
            }
        } else if lastPose != nil {
            breakReason = "استعادة التتبع"
        }

        let point = StablePathPoint(x: pose.px, z: pose.pz, timestampNanoseconds: pose.timestampNanoseconds)
        if segments.isEmpty || breakReason != nil || lastPose?.trackingState != 2 {
            segmentID += 1
            segments.append(StablePathSegment(id: segmentID, points: [point]))
            if let breakReason {
                breakID += 1
                breaks.append(StableBreakPoint(id: breakID, x: pose.px, z: pose.pz, reason: breakReason))
            }
        } else {
            segments[segments.count - 1].points.append(point)
        }
        lastPose = pose
    }

    private func createRunDirectory(in sessionDirectory: URL) throws -> URL {
        let root = sessionDirectory.appendingPathComponent("results", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        let directory = root.appendingPathComponent("run_\(formatter.string(from: Date()))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeResultFiles(
        runDirectory: URL,
        summary: StableProcessingSummary,
        cells: [StableProcessedCell],
        pathSegments: [StablePathSegment],
        breakPoints: [StableBreakPoint],
        cellSize: Float
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(summary).write(to: runDirectory.appendingPathComponent("summary.json"), options: .atomic)
        try encoder.encode(cells).write(to: runDirectory.appendingPathComponent("structural_cells.json"), options: .atomic)
        try encoder.encode(pathSegments).write(to: runDirectory.appendingPathComponent("trajectory.json"), options: .atomic)
        try encoder.encode(breakPoints).write(to: runDirectory.appendingPathComponent("tracking_breaks.json"), options: .atomic)

        let resultObject: [String: Any] = [
            "format": "3ELiDAR Local 2D Result",
            "format_version": 1,
            "stable_core_version": "0.5.0",
            "cell_size_m": cellSize,
            "axis_convention": summary.axisConvention,
            "summary_file": "summary.json",
            "cells_file": "structural_cells.json",
            "trajectory_file": "trajectory.json",
            "tracking_breaks_file": "tracking_breaks.json"
        ]
        let resultData = try JSONSerialization.data(withJSONObject: resultObject, options: [.prettyPrinted, .sortedKeys])
        try resultData.write(to: runDirectory.appendingPathComponent("result_2d.json"), options: .atomic)
    }

    private func readExact(_ handle: FileHandle, count: Int, allowEndOfFile: Bool) throws -> Data? {
        if count == 0 { return Data() }
        var output = Data()
        output.reserveCapacity(count)
        while output.count < count {
            guard let chunk = try handle.read(upToCount: count - output.count), !chunk.isEmpty else {
                if output.isEmpty, allowEndOfFile { return nil }
                throw ProcessorError.truncatedStream
            }
            output.append(chunk)
        }
        return output
    }
}

private extension Data {
    func readUInt16(at offset: Int) -> UInt16? { readInteger(UInt16.self, at: offset) }
    func readUInt32(at offset: Int) -> UInt32? { readInteger(UInt32.self, at: offset) }
    func readUInt64(at offset: Int) -> UInt64? { readInteger(UInt64.self, at: offset) }

    func readFloat(at offset: Int) -> Float? {
        guard let bits = readUInt32(at: offset) else { return nil }
        return Float(bitPattern: bits)
    }

    func readInteger<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T? {
        guard offset >= 0, offset + MemoryLayout<T>.size <= count else { return nil }
        var value: T = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { destination in
            copyBytes(to: destination, from: offset..<(offset + MemoryLayout<T>.size))
        }
        return T(littleEndian: value)
    }
}

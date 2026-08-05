import Foundation
import simd

struct UnifiedPacketHeader {
    let type: StreamingMessageType
    let flags: UInt32
    let sessionID: UInt64
    let frameID: UInt64
    let timestampNanoseconds: UInt64
    let payloadSize: Int
}

struct UnifiedDecodedPose {
    let position: SIMD3<Float>
    let quaternion: simd_quatf
    let trackingState: UInt8
    let thermalState: UInt8
}

struct UnifiedScanPreviewSample {
    let pixelX: Int
    let pixelY: Int
    let depthMeters: Float
    let confidence: UInt8
}

struct UnifiedDecodedScanPreview {
    let sourceWidth: Int
    let sourceHeight: Int
    let gridWidth: Int
    let gridHeight: Int
    let strideX: Int
    let strideY: Int
    let fx: Float
    let fy: Float
    let cx: Float
    let cy: Float
    let fullSampleCount: Int
    let samples: [UnifiedScanPreviewSample]
}

enum UnifiedProtocolError: LocalizedError {
    case shortPacket
    case invalidMagic
    case unsupportedVersion(UInt16)
    case unknownMessageType(UInt16)
    case payloadMismatch
    case invalidPose
    case invalidScan
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .shortPacket: "حزمة 3ELD أقصر من المطلوب."
        case .invalidMagic: "توقيع حزمة 3ELD غير صحيح."
        case .unsupportedVersion(let version): "إصدار البروتوكول غير مدعوم: \(version)."
        case .unknownMessageType(let type): "نوع حزمة غير معروف: \(type)."
        case .payloadMismatch: "حجم بيانات الحزمة لا يطابق العنوان."
        case .invalidPose: "بيانات Pose غير صالحة."
        case .invalidScan: "بيانات المسح 2D غير صالحة."
        case .invalidJSON: "بيانات JSON غير صالحة."
        }
    }
}

private extension Data {
    func unifiedReadInteger<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T? {
        guard offset >= 0, offset + MemoryLayout<T>.size <= count else { return nil }
        var value: T = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { destination in
            copyBytes(to: destination, from: offset..<(offset + MemoryLayout<T>.size))
        }
        return T(littleEndian: value)
    }

    func unifiedReadFloat(at offset: Int) -> Float? {
        guard let bits = unifiedReadInteger(UInt32.self, at: offset) else { return nil }
        return Float(bitPattern: bits)
    }
}

extension StreamingProtocolV01 {
    static func unifiedHelloPacket(
        sessionID: UInt64,
        role: UnifiedDeviceRole,
        scanMode: UnifiedScanMode,
        deviceName: String,
        deviceModel: String,
        systemVersion: String
    ) throws -> Data {
        let object: [String: Any] = [
            "device_name": deviceName,
            "device_model": deviceModel,
            "system_version": systemVersion,
            "app_feature": "المسح الموحد",
            "role": role.rawValue,
            "scan_mode": scanMode.rawValue,
            "stream_capabilities": "pose,scan2d,receiver,standalone,session_recording"
        ]
        let payload = try JSONSerialization.data(withJSONObject: object, options: [])
        return packet(
            type: .hello,
            sessionID: sessionID,
            frameID: 0,
            timestampNanoseconds: DispatchTime.now().uptimeNanoseconds,
            payload: payload
        )
    }

    static func sessionControlPacket(
        sessionID: UInt64,
        frameID: UInt64,
        action: String,
        role: UnifiedDeviceRole,
        scanMode: UnifiedScanMode,
        reason: String? = nil
    ) throws -> Data {
        var object: [String: Any] = [
            "action": action,
            "role": role.rawValue,
            "scan_mode": scanMode.rawValue
        ]
        if let reason { object["reason"] = reason }
        let payload = try JSONSerialization.data(withJSONObject: object, options: [])
        return packet(
            type: .sessionControl,
            sessionID: sessionID,
            frameID: frameID,
            timestampNanoseconds: DispatchTime.now().uptimeNanoseconds,
            payload: payload
        )
    }

    static func decodePacket(_ data: Data) throws -> (UnifiedPacketHeader, Data) {
        guard data.count >= 40 else { throw UnifiedProtocolError.shortPacket }
        guard data.prefix(4) == Data([0x33, 0x45, 0x4C, 0x44]) else {
            throw UnifiedProtocolError.invalidMagic
        }
        guard let version = data.unifiedReadInteger(UInt16.self, at: 4),
              let typeRaw = data.unifiedReadInteger(UInt16.self, at: 6),
              let flags = data.unifiedReadInteger(UInt32.self, at: 8),
              let sessionID = data.unifiedReadInteger(UInt64.self, at: 12),
              let frameID = data.unifiedReadInteger(UInt64.self, at: 20),
              let timestamp = data.unifiedReadInteger(UInt64.self, at: 28),
              let payloadSizeRaw = data.unifiedReadInteger(UInt32.self, at: 36) else {
            throw UnifiedProtocolError.shortPacket
        }
        guard version == 1 else { throw UnifiedProtocolError.unsupportedVersion(version) }
        guard let type = StreamingMessageType(rawValue: typeRaw) else {
            throw UnifiedProtocolError.unknownMessageType(typeRaw)
        }
        let payloadSize = Int(payloadSizeRaw)
        guard data.count == 40 + payloadSize else { throw UnifiedProtocolError.payloadMismatch }
        let payload = data.subdata(in: 40..<data.count)
        return (
            UnifiedPacketHeader(
                type: type,
                flags: flags,
                sessionID: sessionID,
                frameID: frameID,
                timestampNanoseconds: timestamp,
                payloadSize: payloadSize
            ),
            payload
        )
    }

    static func decodePose(_ payload: Data) throws -> UnifiedDecodedPose {
        guard payload.count == 32 else { throw UnifiedProtocolError.invalidPose }
        var values: [Float] = []
        values.reserveCapacity(7)
        for index in 0..<7 {
            guard let value = payload.unifiedReadFloat(at: index * 4) else {
                throw UnifiedProtocolError.invalidPose
            }
            values.append(value)
        }
        return UnifiedDecodedPose(
            position: SIMD3<Float>(values[0], values[1], values[2]),
            quaternion: simd_quatf(ix: values[3], iy: values[4], iz: values[5], r: values[6]),
            trackingState: payload[28],
            thermalState: payload[29]
        )
    }

    static func decodeJSONObject(_ payload: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw UnifiedProtocolError.invalidJSON
        }
        return value
    }

    static func decodeScanPreview(
        _ payload: Data,
        flags: UInt32,
        horizontalSampleCount: Int
    ) throws -> UnifiedDecodedScanPreview {
        guard payload.count >= 28,
              let sourceWidthRaw = payload.unifiedReadInteger(UInt16.self, at: 0),
              let sourceHeightRaw = payload.unifiedReadInteger(UInt16.self, at: 2),
              let gridWidthRaw = payload.unifiedReadInteger(UInt16.self, at: 4),
              let gridHeightRaw = payload.unifiedReadInteger(UInt16.self, at: 6),
              let strideXRaw = payload.unifiedReadInteger(UInt16.self, at: 8),
              let strideYRaw = payload.unifiedReadInteger(UInt16.self, at: 10),
              let fx = payload.unifiedReadFloat(at: 12),
              let fy = payload.unifiedReadFloat(at: 16),
              let cx = payload.unifiedReadFloat(at: 20),
              let cy = payload.unifiedReadFloat(at: 24) else {
            throw UnifiedProtocolError.invalidScan
        }

        let sourceWidth = Int(sourceWidthRaw)
        let sourceHeight = Int(sourceHeightRaw)
        let gridWidth = Int(gridWidthRaw)
        let gridHeight = Int(gridHeightRaw)
        let strideX = Int(strideXRaw)
        let strideY = Int(strideYRaw)
        guard sourceWidth > 0, sourceHeight > 0, gridWidth > 0, gridHeight > 0,
              strideX > 0, strideY > 0 else {
            throw UnifiedProtocolError.invalidScan
        }
        let sampleCount = gridWidth * gridHeight
        let confidenceIncluded = flags & 1 != 0
        let expected = 28 + sampleCount * 2 + (confidenceIncluded ? sampleCount : 0)
        guard payload.count == expected else { throw UnifiedProtocolError.invalidScan }

        let requested = max(2, min(32, horizontalSampleCount))
        let row = max(0, min(gridHeight - 1, (gridHeight - 1) / 2))
        var columns = Set<Int>()
        for index in 0..<requested {
            columns.insert(Int((Double(index) * Double(gridWidth - 1) / Double(requested - 1)).rounded()))
        }
        let depthOffset = 28
        let confidenceOffset = depthOffset + sampleCount * 2
        var samples: [UnifiedScanPreviewSample] = []
        for column in columns.sorted() {
            let sampleIndex = row * gridWidth + column
            guard let depthMillimeters = payload.unifiedReadInteger(UInt16.self, at: depthOffset + sampleIndex * 2) else {
                continue
            }
            let confidence = confidenceIncluded ? payload[confidenceOffset + sampleIndex] : 1
            samples.append(
                UnifiedScanPreviewSample(
                    pixelX: min(column * strideX, sourceWidth - 1),
                    pixelY: min(row * strideY, sourceHeight - 1),
                    depthMeters: Float(depthMillimeters) / 1_000,
                    confidence: confidence
                )
            )
        }
        return UnifiedDecodedScanPreview(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            gridWidth: gridWidth,
            gridHeight: gridHeight,
            strideX: strideX,
            strideY: strideY,
            fx: fx,
            fy: fy,
            cx: cx,
            cy: cy,
            fullSampleCount: sampleCount,
            samples: samples
        )
    }
}

final class UnifiedPacketStreamDecoder {
    private var buffer = Data()

    func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var output: [Data] = []
        while buffer.count >= 40 {
            guard buffer.prefix(4) == Data([0x33, 0x45, 0x4C, 0x44]) else {
                if let range = buffer.range(of: Data([0x33, 0x45, 0x4C, 0x44]), options: [], in: 1..<buffer.count) {
                    buffer.removeSubrange(0..<range.lowerBound)
                } else {
                    buffer = Data(buffer.suffix(min(3, buffer.count)))
                    break
                }
                continue
            }
            guard let payloadSize = buffer.unifiedReadInteger(UInt32.self, at: 36) else { break }
            let packetSize = 40 + Int(payloadSize)
            guard packetSize <= 128 * 1024 * 1024 else {
                buffer.removeAll(keepingCapacity: true)
                break
            }
            guard buffer.count >= packetSize else { break }
            output.append(buffer.subdata(in: 0..<packetSize))
            buffer.removeSubrange(0..<packetSize)
        }
        return output
    }
}

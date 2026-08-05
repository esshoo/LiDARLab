import CoreGraphics
import CoreVideo
import Foundation
import simd

private let streamingProtocolMagic = Data([0x33, 0x45, 0x4C, 0x44]) // "3ELD"
private let streamingProtocolVersion: UInt16 = 1
private let scan2DConfidenceIncludedFlag: UInt32 = 1 << 0

enum StreamingMessageType: UInt16 {
    case hello = 1
    case pose = 2
    case depth = 3
    case confidence = 4
    case rgb = 5
    case intrinsics = 6
    case tracking = 7
    case scan2D = 8
    case localizationResult = 100
}

extension Data {
    mutating func appendStreamingLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
            append(contentsOf: bytes)
        }
    }

    mutating func appendStreamingFloat32(_ value: Float) {
        appendStreamingLittleEndian(value.bitPattern)
    }
}

enum StreamingProtocolV01 {
    static func packet(
        type: StreamingMessageType,
        sessionID: UInt64,
        frameID: UInt64,
        timestampNanoseconds: UInt64,
        payload: Data,
        flags: UInt32 = 0
    ) -> Data {
        var result = Data(capacity: 40 + payload.count)
        result.append(streamingProtocolMagic)
        result.appendStreamingLittleEndian(streamingProtocolVersion)
        result.appendStreamingLittleEndian(type.rawValue)
        result.appendStreamingLittleEndian(flags)
        result.appendStreamingLittleEndian(sessionID)
        result.appendStreamingLittleEndian(frameID)
        result.appendStreamingLittleEndian(timestampNanoseconds)
        result.appendStreamingLittleEndian(UInt32(payload.count))
        result.append(payload)
        return result
    }

    static func helloPacket(
        sessionID: UInt64,
        deviceName: String,
        deviceModel: String,
        systemVersion: String
    ) throws -> Data {
        let object: [String: String] = [
            "device_name": deviceName,
            "device_model": deviceModel,
            "system_version": systemVersion,
            "app_feature": "البث إلى الكمبيوتر",
            "stream_capabilities": "pose,scan2d,optional_confidence"
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

    static func posePacket(
        sessionID: UInt64,
        frameID: UInt64,
        timestampNanoseconds: UInt64,
        position: SIMD3<Float>,
        quaternion: simd_quatf,
        trackingState: UInt8,
        thermalState: UInt8
    ) -> Data {
        var payload = Data(capacity: 32)
        payload.appendStreamingFloat32(position.x)
        payload.appendStreamingFloat32(position.y)
        payload.appendStreamingFloat32(position.z)
        payload.appendStreamingFloat32(quaternion.vector.x)
        payload.appendStreamingFloat32(quaternion.vector.y)
        payload.appendStreamingFloat32(quaternion.vector.z)
        payload.appendStreamingFloat32(quaternion.vector.w)
        payload.append(trackingState)
        payload.append(thermalState)
        payload.appendStreamingLittleEndian(UInt16(0))

        return packet(
            type: .pose,
            sessionID: sessionID,
            frameID: frameID,
            timestampNanoseconds: timestampNanoseconds,
            payload: payload
        )
    }

    /// Sends a light, downsampled depth grid. Windows reconstructs the rays,
    /// transforms them with the pose carrying the same frame ID, then projects
    /// the resulting points onto the global X/Z plane.
    static func scan2DPacket(
        sessionID: UInt64,
        frameID: UInt64,
        timestampNanoseconds: UInt64,
        depthMap: CVPixelBuffer,
        confidenceMap: CVPixelBuffer?,
        cameraIntrinsics: simd_float3x3,
        cameraImageResolution: CGSize,
        samplingStride: Int,
        includeConfidence: Bool
    ) -> Data? {
        let sourceWidth = CVPixelBufferGetWidth(depthMap)
        let sourceHeight = CVPixelBufferGetHeight(depthMap)
        guard sourceWidth > 0,
              sourceHeight > 0,
              cameraImageResolution.width > 0,
              cameraImageResolution.height > 0 else {
            return nil
        }

        let stride = max(1, samplingStride)
        let gridWidth = (sourceWidth + stride - 1) / stride
        let gridHeight = (sourceHeight + stride - 1) / stride
        let sampleCount = gridWidth * gridHeight

        guard sourceWidth <= Int(UInt16.max),
              sourceHeight <= Int(UInt16.max),
              gridWidth <= Int(UInt16.max),
              gridHeight <= Int(UInt16.max),
              stride <= Int(UInt16.max) else {
            return nil
        }

        let depthLock = CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        guard depthLock == kCVReturnSuccess,
              let depthBase = CVPixelBufferGetBaseAddress(depthMap) else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        var confidenceLocked = false
        var confidenceBase: UnsafeMutableRawPointer?
        var confidenceWidth = 0
        var confidenceHeight = 0
        var confidenceBytesPerRow = 0

        if includeConfidence,
           let confidenceMap,
           CVPixelBufferLockBaseAddress(confidenceMap, .readOnly) == kCVReturnSuccess {
            confidenceLocked = true
            confidenceBase = CVPixelBufferGetBaseAddress(confidenceMap)
            confidenceWidth = CVPixelBufferGetWidth(confidenceMap)
            confidenceHeight = CVPixelBufferGetHeight(confidenceMap)
            confidenceBytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
        }
        defer {
            if confidenceLocked, let confidenceMap {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
        }

        let confidenceIncluded = includeConfidence && confidenceBase != nil
        let scaleX = Float(sourceWidth) / Float(cameraImageResolution.width)
        let scaleY = Float(sourceHeight) / Float(cameraImageResolution.height)
        let fx = cameraIntrinsics.columns.0.x * scaleX
        let fy = cameraIntrinsics.columns.1.y * scaleY
        let cx = cameraIntrinsics.columns.2.x * scaleX
        let cy = cameraIntrinsics.columns.2.y * scaleY

        let depthBytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let bytesPerSample = confidenceIncluded ? 3 : 2
        var payload = Data(capacity: 28 + sampleCount * bytesPerSample)

        payload.appendStreamingLittleEndian(UInt16(sourceWidth))
        payload.appendStreamingLittleEndian(UInt16(sourceHeight))
        payload.appendStreamingLittleEndian(UInt16(gridWidth))
        payload.appendStreamingLittleEndian(UInt16(gridHeight))
        payload.appendStreamingLittleEndian(UInt16(stride))
        payload.appendStreamingLittleEndian(UInt16(stride))
        payload.appendStreamingFloat32(fx)
        payload.appendStreamingFloat32(fy)
        payload.appendStreamingFloat32(cx)
        payload.appendStreamingFloat32(cy)

        var confidenceValues = Data(capacity: confidenceIncluded ? sampleCount : 0)

        for gridY in 0..<gridHeight {
            let sourceY = min(gridY * stride, sourceHeight - 1)
            let depthRow = depthBase
                .advanced(by: sourceY * depthBytesPerRow)
                .assumingMemoryBound(to: Float32.self)

            for gridX in 0..<gridWidth {
                let sourceX = min(gridX * stride, sourceWidth - 1)
                let depthMeters = depthRow[sourceX]

                let millimeters: UInt16
                if depthMeters.isFinite, depthMeters > 0 {
                    let value = Int((depthMeters * 1_000).rounded())
                    millimeters = UInt16(clamping: value)
                } else {
                    millimeters = 0
                }
                payload.appendStreamingLittleEndian(millimeters)

                if confidenceIncluded,
                   let confidenceBase,
                   confidenceWidth > 0,
                   confidenceHeight > 0 {
                    let confidenceX = min(
                        Int(Float(sourceX) * Float(confidenceWidth) / Float(sourceWidth)),
                        confidenceWidth - 1
                    )
                    let confidenceY = min(
                        Int(Float(sourceY) * Float(confidenceHeight) / Float(sourceHeight)),
                        confidenceHeight - 1
                    )
                    let row = confidenceBase
                        .advanced(by: confidenceY * confidenceBytesPerRow)
                        .assumingMemoryBound(to: UInt8.self)
                    confidenceValues.append(row[confidenceX])
                }
            }
        }

        if confidenceIncluded {
            payload.append(confidenceValues)
        }

        return packet(
            type: .scan2D,
            sessionID: sessionID,
            frameID: frameID,
            timestampNanoseconds: timestampNanoseconds,
            payload: payload,
            flags: confidenceIncluded ? scan2DConfidenceIncludedFlag : 0
        )
    }

}

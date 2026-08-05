import Foundation
import simd

private let streamingProtocolMagic = Data([0x33, 0x45, 0x4C, 0x44]) // "3ELD"
private let streamingProtocolVersion: UInt16 = 1

enum StreamingMessageType: UInt16 {
    case hello = 1
    case pose = 2
    case depth = 3
    case confidence = 4
    case rgb = 5
    case intrinsics = 6
    case tracking = 7
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
            "app_feature": "البث إلى الكمبيوتر"
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
}

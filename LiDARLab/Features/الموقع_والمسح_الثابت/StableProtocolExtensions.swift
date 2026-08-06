import Foundation
import UIKit

extension StreamingProtocolV01 {
    static func stableHelloPacket(sessionID: UInt64, mode: StableScanMode) throws -> Data {
        let device = UIDevice.current
        let object: [String: Any] = [
            "device_name": device.name,
            "device_model": device.model,
            "system_version": device.systemVersion,
            "app_feature": "Stable Location Core",
            "stable_core_version": "0.5.2",
            "role": "sender",
            "scan_mode": mode.protocolName,
            "stream_capabilities": "pose_full_rate,scan2d_same_frame,append_only_local_recording,post_session_processing,hello_ack,frame_ack"
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
}

enum StableProtocolPackets {
    private static let magic = Data([0x33, 0x45, 0x4C, 0x44])
    private static let version: UInt16 = 1
    private static let sessionControlType: UInt16 = 9

    static func sessionControlPacket(
        sessionID: UInt64,
        frameID: UInt64,
        action: String,
        mode: StableScanMode
    ) throws -> Data {
        let payload = try JSONSerialization.data(withJSONObject: [
            "action": action,
            "scan_mode": mode.protocolName,
            "stable_core_version": "0.5.2"
        ], options: [])

        var result = Data(capacity: 40 + payload.count)
        result.append(magic)
        result.appendStreamingLittleEndian(version)
        result.appendStreamingLittleEndian(sessionControlType)
        result.appendStreamingLittleEndian(UInt32(0))
        result.appendStreamingLittleEndian(sessionID)
        result.appendStreamingLittleEndian(frameID)
        result.appendStreamingLittleEndian(DispatchTime.now().uptimeNanoseconds)
        result.appendStreamingLittleEndian(UInt32(payload.count))
        result.append(payload)
        return result
    }
}

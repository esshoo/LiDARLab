import ARKit
import Foundation
import SwiftUI
import UIKit
import simd

@MainActor
final class ComputerBridgeViewModel: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    enum StreamMode: String, CaseIterable, Identifiable {
        case poseOnly
        case scan2D

        var id: String { rawValue }

        var title: String {
            switch self {
            case .poseOnly: "الموقع فقط"
            case .scan2D: "مسح 2D"
            }
        }
    }

    enum ThermalPolicy: String, CaseIterable, Identifiable {
        case warnOnly
        case stopDepthAtCritical
        case stopAllAtCritical

        var id: String { rawValue }

        var title: String {
            switch self {
            case .warnOnly: "تنبيه فقط — لا تغيير تلقائي"
            case .stopDepthAtCritical: "إيقاف Depth عند الحرارة الحرجة"
            case .stopAllAtCritical: "إيقاف كل الإرسال عند الحرارة الحرجة"
            }
        }
    }

    @Published var serverIP: String {
        didSet { UserDefaults.standard.set(serverIP, forKey: Self.serverIPKey) }
    }
    @Published var serverPort: String {
        didSet { UserDefaults.standard.set(serverPort, forKey: Self.serverPortKey) }
    }
    @Published var targetFPS: Int {
        didSet { UserDefaults.standard.set(targetFPS, forKey: Self.targetFPSKey) }
    }
    @Published var streamMode: StreamMode {
        didSet { UserDefaults.standard.set(streamMode.rawValue, forKey: Self.streamModeKey) }
    }
    @Published var samplingStride: Int {
        didSet { UserDefaults.standard.set(samplingStride, forKey: Self.samplingStrideKey) }
    }
    @Published var sendConfidence: Bool {
        didSet { UserDefaults.standard.set(sendConfidence, forKey: Self.sendConfidenceKey) }
    }
    @Published var thermalPolicy: ThermalPolicy {
        didSet { UserDefaults.standard.set(thermalPolicy.rawValue, forKey: Self.thermalPolicyKey) }
    }

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var isStreaming = false
    @Published private(set) var framesSent: UInt64 = 0
    @Published private(set) var framesSkipped: UInt64 = 0
    @Published private(set) var scanFramesSent: UInt64 = 0
    @Published private(set) var scanFramesSkipped: UInt64 = 0
    @Published private(set) var bytesSent: UInt64 = 0
    @Published private(set) var trackingText = "غير متاح"
    @Published private(set) var thermalText = "طبيعي"
    @Published private(set) var depthStatusText = "بانتظار LiDAR"
    @Published private(set) var lastPosition = SIMD3<Float>(repeating: 0)
    @Published private(set) var lastServerMessage = "لا توجد رسالة من الكمبيوتر بعد."
    @Published private(set) var lastError: String?

    private static let serverIPKey = "computerBridge.serverIP"
    private static let serverPortKey = "computerBridge.serverPort"
    private static let targetFPSKey = "computerBridge.targetFPS"
    private static let streamModeKey = "computerBridge.streamMode"
    private static let samplingStrideKey = "computerBridge.samplingStride"
    private static let sendConfidenceKey = "computerBridge.sendConfidence"
    private static let thermalPolicyKey = "computerBridge.thermalPolicy"

    private let client = ComputerBridgeWebSocketClient()
    private var sessionID = UInt64.random(in: 1...UInt64.max)
    private var frameID: UInt64 = 0
    private var lastSentFrameTimestamp: TimeInterval = -.greatestFiniteMagnitude
    private var sendInProgress = false
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    init() {
        serverIP = UserDefaults.standard.string(forKey: Self.serverIPKey) ?? "192.168.0.2"
        serverPort = UserDefaults.standard.string(forKey: Self.serverPortKey) ?? "8766"

        let savedFPS = UserDefaults.standard.integer(forKey: Self.targetFPSKey)
        targetFPS = [1, 2, 5, 10, 15, 30].contains(savedFPS) ? savedFPS : 10

        let savedMode = UserDefaults.standard.string(forKey: Self.streamModeKey)
        streamMode = StreamMode(rawValue: savedMode ?? "") ?? .scan2D

        let savedStride = UserDefaults.standard.integer(forKey: Self.samplingStrideKey)
        samplingStride = [2, 4, 6, 8, 12].contains(savedStride) ? savedStride : 6

        if UserDefaults.standard.object(forKey: Self.sendConfidenceKey) == nil {
            sendConfidence = true
        } else {
            sendConfidence = UserDefaults.standard.bool(forKey: Self.sendConfidenceKey)
        }

        let savedThermalPolicy = UserDefaults.standard.string(forKey: Self.thermalPolicyKey)
        thermalPolicy = ThermalPolicy(rawValue: savedThermalPolicy ?? "") ?? .warnOnly
    }

    var connectionTitle: String {
        switch connectionState {
        case .disconnected: "غير متصل"
        case .connecting: "جاري الاتصال"
        case .connected: "متصل"
        case .failed: "فشل الاتصال"
        }
    }

    var isConnected: Bool {
        connectionState == .connected
    }

    var settingsLocked: Bool {
        isStreaming
    }

    var totalSentText: String {
        let bytes = Double(bytesSent)
        if bytes >= 1_000_000 {
            return String(format: "%.2f MB", bytes / 1_000_000)
        }
        if bytes >= 1_000 {
            return String(format: "%.1f KB", bytes / 1_000)
        }
        return "\(bytesSent) B"
    }

    var positionText: String {
        String(format: "X %.3f  Y %.3f  Z %.3f", lastPosition.x, lastPosition.y, lastPosition.z)
    }

    var estimatedTransferText: String {
        guard streamMode == .scan2D else {
            let mbps = Double(72 * targetFPS * 8) / 1_000_000
            return String(format: "تقدير الموقع فقط: %.3f Mbps", mbps)
        }

        let sourceWidth = 256
        let sourceHeight = 192
        let gridWidth = (sourceWidth + samplingStride - 1) / samplingStride
        let gridHeight = (sourceHeight + samplingStride - 1) / samplingStride
        let sampleCount = gridWidth * gridHeight
        let bytesPerSample = sendConfidence ? 3 : 2
        let bytesPerFrame = 72 + 68 + sampleCount * bytesPerSample
        let mbps = Double(bytesPerFrame * targetFPS * 8) / 1_000_000
        return String(
            format: "تقدير تقريبي: %d عينة/Frame — %.3f Mbps",
            sampleCount,
            mbps
        )
    }

    func connect() {
        guard connectionState != .connecting else { return }
        guard let url = websocketURL else {
            connectionState = .failed("عنوان IP أو المنفذ غير صالح.")
            lastError = "اكتب عنوان الكمبيوتر مثل 192.168.0.2 والمنفذ 8766."
            return
        }

        isStreaming = false
        receiveTask?.cancel()
        receiveTask = nil
        pingTask?.cancel()
        pingTask = nil
        sendInProgress = false
        connectionState = .connecting
        lastError = nil
        sessionID = UInt64.random(in: 1...UInt64.max)
        frameID = 0

        Task {
            await client.disconnect()
            await client.connect(to: url)

            do {
                let device = UIDevice.current
                let hello = try StreamingProtocolV01.helloPacket(
                    sessionID: sessionID,
                    deviceName: device.name,
                    deviceModel: device.model,
                    systemVersion: device.systemVersion
                )
                try await client.send(hello)
                bytesSent += UInt64(hello.count)
                connectionState = .connected
                lastServerMessage = "تم تعريف الجهاز. راجع إعدادات النقل ثم ابدأ الإرسال."
                startReceiveLoop()
                startPingLoop()
            } catch {
                connectionState = .failed(error.localizedDescription)
                lastError = error.localizedDescription
                await client.disconnect()
            }
        }
    }

    func disconnect(resetStatistics: Bool = false) {
        isStreaming = false
        receiveTask?.cancel()
        receiveTask = nil
        pingTask?.cancel()
        pingTask = nil
        connectionState = .disconnected
        sendInProgress = false

        Task { await client.disconnect() }

        if resetStatistics {
            framesSent = 0
            framesSkipped = 0
            scanFramesSent = 0
            scanFramesSkipped = 0
            bytesSent = 0
            frameID = 0
            lastServerMessage = "لا توجد رسالة من الكمبيوتر بعد."
        }
    }

    func toggleStreaming() {
        if isStreaming {
            isStreaming = false
            lastServerMessage = "تم إيقاف الإرسال مؤقتًا."
        } else if isConnected {
            lastSentFrameTimestamp = -.greatestFiniteMagnitude
            isStreaming = true
            lastServerMessage = streamMode == .scan2D
                ? "بدأ الإرسال بالإعدادات المختارة: \(targetFPS) FPS، خطوة \(samplingStride)."
                : "بدأ إرسال موقع الجهاز فقط بمعدل \(targetFPS) FPS."
        }
    }

    func handle(frame: ARFrame) {
        updateStatus(from: frame)
        guard isConnected, isStreaming else { return }

        let minimumInterval = 1.0 / Double(max(targetFPS, 1))
        guard frame.timestamp - lastSentFrameTimestamp >= minimumInterval else { return }
        lastSentFrameTimestamp = frame.timestamp

        let currentThermalState = ProcessInfo.processInfo.thermalState
        if currentThermalState == .critical, thermalPolicy == .stopAllAtCritical {
            framesSkipped += 1
            if streamMode == .scan2D { scanFramesSkipped += 1 }
            depthStatusText = "الإرسال متوقف حسب سياسة الحرارة المختارة"
            return
        }

        guard !sendInProgress else {
            framesSkipped += 1
            return
        }

        frameID &+= 1
        let currentFrameID = frameID
        let transform = frame.camera.transform
        let position = SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
        let quaternion = simd_quatf(transform)
        let timestampNanoseconds = UInt64(max(frame.timestamp, 0) * 1_000_000_000)
        let posePacket = StreamingProtocolV01.posePacket(
            sessionID: sessionID,
            frameID: currentFrameID,
            timestampNanoseconds: timestampNanoseconds,
            position: position,
            quaternion: quaternion,
            trackingState: trackingCode(frame.camera.trackingState),
            thermalState: thermalCode(currentThermalState)
        )

        var scanPacket: Data?
        if streamMode == .scan2D {
            if currentThermalState == .critical, thermalPolicy == .stopDepthAtCritical {
                depthStatusText = "Depth متوقف حسب سياسة الحرارة المختارة"
                scanFramesSkipped += 1
            } else if let depthData = frame.sceneDepth {
                scanPacket = StreamingProtocolV01.scan2DPacket(
                    sessionID: sessionID,
                    frameID: currentFrameID,
                    timestampNanoseconds: timestampNanoseconds,
                    depthMap: depthData.depthMap,
                    confidenceMap: depthData.confidenceMap,
                    cameraIntrinsics: frame.camera.intrinsics,
                    cameraImageResolution: frame.camera.imageResolution,
                    samplingStride: samplingStride,
                    includeConfidence: sendConfidence
                )
                let confidenceText = sendConfidence ? "مع Confidence" : "بدون Confidence"
                depthStatusText = scanPacket == nil
                    ? "تعذر قراءة العمق"
                    : "خطوة \(samplingStride) — \(confidenceText)"
                if scanPacket == nil {
                    scanFramesSkipped += 1
                }
            } else {
                depthStatusText = "لا توجد sceneDepth"
                scanFramesSkipped += 1
            }
        } else {
            depthStatusText = "غير مستخدم"
        }

        lastPosition = position
        sendInProgress = true

        Task {
            defer { sendInProgress = false }
            do {
                try await client.send(posePacket)
                framesSent += 1
                bytesSent += UInt64(posePacket.count)

                if let scanPacket {
                    try await client.send(scanPacket)
                    scanFramesSent += 1
                    bytesSent += UInt64(scanPacket.count)
                }
            } catch {
                isStreaming = false
                connectionState = .failed(error.localizedDescription)
                lastError = error.localizedDescription
            }
        }
    }

    func stop() {
        disconnect(resetStatistics: false)
    }

    private var websocketURL: URL? {
        let trimmedIP = serverIP.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = serverPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIP.isEmpty,
              let port = Int(trimmedPort),
              (1...65_535).contains(port) else {
            return nil
        }
        return URL(string: "ws://\(trimmedIP):\(port)/ws/device")
    }

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task {
            while !Task.isCancelled {
                do {
                    let message = try await client.receive()
                    switch message {
                    case .string(let text):
                        lastServerMessage = summarizedServerMessage(text)
                    case .data(let data):
                        lastServerMessage = "استلم الجهاز \(data.count) بايت من المستقبل."
                    @unknown default:
                        lastServerMessage = "استلم الجهاز رسالة غير معروفة."
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    isStreaming = false
                    connectionState = .failed(error.localizedDescription)
                    lastError = error.localizedDescription
                    return
                }
            }
        }
    }

    private func startPingLoop() {
        pingTask?.cancel()
        pingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { return }
                do {
                    try await client.sendPing()
                } catch {
                    isStreaming = false
                    connectionState = .failed(error.localizedDescription)
                    lastError = error.localizedDescription
                    return
                }
            }
        }
    }

    private func summarizedServerMessage(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return text
        }

        if let type = json["type"] as? String,
           type == "localization_result" {
            let frame = (json["frame_id"] as? NSNumber)?.uint64Value ?? 0
            let status = json["status"] as? String ?? "—"
            return "رد المستقبل للإطار \(frame): \(status)"
        }

        if let message = json["message"] as? String {
            return message
        }
        return text
    }

    private func updateStatus(from frame: ARFrame) {
        switch frame.camera.trackingState {
        case .normal:
            trackingText = "طبيعي"
        case .notAvailable:
            trackingText = "غير متاح"
        case .limited(let reason):
            trackingText = "محدود: \(limitedReasonText(reason))"
        }

        thermalText = thermalStateText(ProcessInfo.processInfo.thermalState)
        if streamMode == .scan2D, frame.sceneDepth != nil, !isStreaming {
            depthStatusText = "LiDAR جاهز — الإعدادات يدوية"
        }
    }

    private func trackingCode(_ state: ARCamera.TrackingState) -> UInt8 {
        switch state {
        case .notAvailable: 0
        case .limited: 1
        case .normal: 2
        }
    }

    private func limitedReasonText(_ reason: ARCamera.TrackingState.Reason) -> String {
        switch reason {
        case .initializing: "تهيئة"
        case .excessiveMotion: "حركة سريعة"
        case .insufficientFeatures: "تفاصيل قليلة"
        case .relocalizing: "إعادة تحديد الموقع"
        @unknown default: "سبب غير معروف"
        }
    }

    private func thermalCode(_ state: ProcessInfo.ThermalState) -> UInt8 {
        switch state {
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        case .critical: 3
        @unknown default: 3
        }
    }

    private func thermalStateText(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "طبيعي"
        case .fair: "دافئ"
        case .serious: "مرتفع"
        case .critical: "حرج"
        @unknown default: "غير معروف"
        }
    }
}

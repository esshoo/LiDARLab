import ARKit
import CoreVideo
import Foundation
import Network
import SwiftUI
import UIKit
import simd

@MainActor
final class UnifiedScanViewModel: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case listening
        case failed(String)

        var title: String {
            switch self {
            case .disconnected: "غير متصل"
            case .connecting: "جاري الاتصال"
            case .connected: "متصل"
            case .listening: "يستقبل"
            case .failed: "فشل"
            }
        }
    }

    // MARK: - Persisted user choices

    @Published var role: UnifiedDeviceRole {
        didSet { defaults.set(role.rawValue, forKey: Keys.role) }
    }
    @Published var scanMode: UnifiedScanMode {
        didSet { defaults.set(scanMode.rawValue, forKey: Keys.scanMode) }
    }
    @Published var connectionKind: UnifiedConnectionKind {
        didSet { defaults.set(connectionKind.rawValue, forKey: Keys.connectionKind) }
    }
    @Published var serverIP: String {
        didSet { defaults.set(serverIP, forKey: Keys.serverIP) }
    }
    @Published var serverPort: String {
        didSet { defaults.set(serverPort, forKey: Keys.serverPort) }
    }
    @Published var directPort: Int {
        didSet { defaults.set(directPort, forKey: Keys.directPort) }
    }
    @Published var selectedReceiverID: String? {
        didSet { defaults.set(selectedReceiverID, forKey: Keys.selectedReceiverID) }
    }
    @Published var poseFPS: Int {
        didSet { defaults.set(poseFPS, forKey: Keys.poseFPS) }
    }
    @Published var scanFPS: Int {
        didSet { defaults.set(scanFPS, forKey: Keys.scanFPS) }
    }
    @Published var samplingStride: Int {
        didSet { defaults.set(samplingStride, forKey: Keys.samplingStride) }
    }
    @Published var sendConfidence: Bool {
        didSet { defaults.set(sendConfidence, forKey: Keys.sendConfidence) }
    }
    @Published var thermalPolicy: UnifiedThermalPolicy {
        didSet { defaults.set(thermalPolicy.rawValue, forKey: Keys.thermalPolicy) }
    }
    @Published var saveLocalCopyWhenSending: Bool {
        didSet { defaults.set(saveLocalCopyWhenSending, forKey: Keys.saveLocalCopyWhenSending) }
    }
    @Published var previewFPS: Int {
        didSet { defaults.set(previewFPS, forKey: Keys.previewFPS) }
    }
    @Published var coveragePreviewStyle: UnifiedCoveragePreviewStyle {
        didSet { defaults.set(coveragePreviewStyle.rawValue, forKey: Keys.coveragePreviewStyle) }
    }
    @Published var pathPreviewStyle: UnifiedPathPreviewStyle {
        didSet { defaults.set(pathPreviewStyle.rawValue, forKey: Keys.pathPreviewStyle) }
    }
    @Published var devicePreviewStyle: UnifiedDevicePreviewStyle {
        didSet { defaults.set(devicePreviewStyle.rawValue, forKey: Keys.devicePreviewStyle) }
    }
    @Published var previewCellSize: Float {
        didSet { defaults.set(Double(previewCellSize), forKey: Keys.previewCellSize) }
    }
    @Published var previewHorizontalRays: Int {
        didSet { defaults.set(previewHorizontalRays, forKey: Keys.previewHorizontalRays) }
    }
    @Published var previewMinimumDepth: Float {
        didSet { defaults.set(Double(previewMinimumDepth), forKey: Keys.previewMinimumDepth) }
    }
    @Published var previewMaximumDepth: Float {
        didSet { defaults.set(Double(previewMaximumDepth), forKey: Keys.previewMaximumDepth) }
    }
    @Published var previewMinimumConfidence: Int {
        didSet { defaults.set(previewMinimumConfidence, forKey: Keys.previewMinimumConfidence) }
    }
    @Published var recorderFlushPackets: Int {
        didSet { defaults.set(recorderFlushPackets, forKey: Keys.recorderFlushPackets) }
    }
    @Published var recorderSynchronizeOnFlush: Bool {
        didSet { defaults.set(recorderSynchronizeOnFlush, forKey: Keys.recorderSynchronizeOnFlush) }
    }

    // MARK: - Live state

    @Published private(set) var sessionState: UnifiedSessionState = .idle
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var currentPosition = SIMD3<Float>(repeating: 0)
    @Published private(set) var currentQuaternion = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    @Published private(set) var path: [UnifiedPreviewPoint] = []
    @Published private(set) var coverageCells: [UnifiedPreviewCell] = []
    @Published private(set) var currentSweep: UnifiedPreviewSweep?
    @Published private(set) var trackingText = "غير متاح"
    @Published private(set) var thermalText = "طبيعي"
    @Published private(set) var depthText = "بانتظار الجلسة"
    @Published private(set) var statusMessage = "اختر الدور ووضع المسح ثم ابدأ."
    @Published private(set) var remoteDeviceName = "—"
    @Published private(set) var framesCaptured: UInt64 = 0
    @Published private(set) var posePackets: UInt64 = 0
    @Published private(set) var scanPackets: UInt64 = 0
    @Published private(set) var skippedFrames: UInt64 = 0
    @Published private(set) var packetsReceived: UInt64 = 0
    @Published private(set) var bytesTransferred: UInt64 = 0
    @Published private(set) var recordedPackets: UInt64 = 0
    @Published private(set) var recordedBytes: UInt64 = 0
    @Published private(set) var currentSessionDirectory: URL?
    @Published private(set) var lastError: String?
    @Published var capabilityWarning: UnifiedCapabilityWarning?

    let browser = UnifiedAppleReceiverBrowser()

    private let defaults = UserDefaults.standard
    private let websocketClient = ComputerBridgeWebSocketClient()
    private let directClient = UnifiedAppleDirectTCPClient()
    private let receiverServer = UnifiedAppleDirectReceiverServer()
    private let recorder = UnifiedLocalSessionRecorder()

    private var sessionID = UInt64.random(in: 1...UInt64.max)
    private var frameID: UInt64 = 0
    private var lastPoseTimestamp: TimeInterval = -.greatestFiniteMagnitude
    private var lastScanTimestamp: TimeInterval = -.greatestFiniteMagnitude
    private var lastPreviewTimestamp: TimeInterval = -.greatestFiniteMagnitude
    private var senderBusy = false
    private var websocketReceiveTask: Task<Void, Never>?
    private var websocketPingTask: Task<Void, Never>?
    private var receiverPoses: [UInt64: UnifiedDecodedPose] = [:]
    private var localRecordingActive = false
    private var pendingStartAfterWarning = false
    private var incomingPacketQueue: [Data] = []
    private var processingIncomingQueue = false
    private var coverageCellStore: Set<UnifiedPreviewCell> = []

    private enum Keys {
        static let role = "unified.role"
        static let scanMode = "unified.scanMode"
        static let connectionKind = "unified.connectionKind"
        static let serverIP = "unified.serverIP"
        static let serverPort = "unified.serverPort"
        static let directPort = "unified.directPort"
        static let selectedReceiverID = "unified.selectedReceiverID"
        static let poseFPS = "unified.poseFPS"
        static let scanFPS = "unified.scanFPS"
        static let samplingStride = "unified.samplingStride"
        static let sendConfidence = "unified.sendConfidence"
        static let thermalPolicy = "unified.thermalPolicy"
        static let saveLocalCopyWhenSending = "unified.saveLocalCopyWhenSending"
        static let previewFPS = "unified.previewFPS"
        static let coveragePreviewStyle = "unified.coveragePreviewStyle"
        static let pathPreviewStyle = "unified.pathPreviewStyle"
        static let devicePreviewStyle = "unified.devicePreviewStyle"
        static let previewCellSize = "unified.previewCellSize"
        static let previewHorizontalRays = "unified.previewHorizontalRays"
        static let previewMinimumDepth = "unified.previewMinimumDepth"
        static let previewMaximumDepth = "unified.previewMaximumDepth"
        static let previewMinimumConfidence = "unified.previewMinimumConfidence"
        static let recorderFlushPackets = "unified.recorderFlushPackets"
        static let recorderSynchronizeOnFlush = "unified.recorderSynchronizeOnFlush"
    }

    init() {
        role = UnifiedDeviceRole(rawValue: defaults.string(forKey: Keys.role) ?? "") ?? .sender
        scanMode = UnifiedScanMode(rawValue: defaults.string(forKey: Keys.scanMode) ?? "") ?? .scan2D
        connectionKind = UnifiedConnectionKind(rawValue: defaults.string(forKey: Keys.connectionKind) ?? "") ?? .windowsWebSocket
        serverIP = defaults.string(forKey: Keys.serverIP) ?? "192.168.0.2"
        serverPort = defaults.string(forKey: Keys.serverPort) ?? "8766"

        let savedDirectPort = defaults.integer(forKey: Keys.directPort)
        directPort = (1...65_535).contains(savedDirectPort) ? savedDirectPort : 8767
        selectedReceiverID = defaults.string(forKey: Keys.selectedReceiverID)

        poseFPS = Self.validChoice(defaults.integer(forKey: Keys.poseFPS), choices: Self.fpsChoices, fallback: 30)
        scanFPS = Self.validChoice(defaults.integer(forKey: Keys.scanFPS), choices: Self.fpsChoices, fallback: 10)
        samplingStride = Self.validChoice(defaults.integer(forKey: Keys.samplingStride), choices: Self.strideChoices, fallback: 6)
        sendConfidence = defaults.object(forKey: Keys.sendConfidence) == nil ? true : defaults.bool(forKey: Keys.sendConfidence)
        thermalPolicy = UnifiedThermalPolicy(rawValue: defaults.string(forKey: Keys.thermalPolicy) ?? "") ?? .warnOnly
        saveLocalCopyWhenSending = defaults.bool(forKey: Keys.saveLocalCopyWhenSending)

        previewFPS = Self.validChoice(defaults.integer(forKey: Keys.previewFPS), choices: Self.previewFPSChoices, fallback: 10)
        coveragePreviewStyle = UnifiedCoveragePreviewStyle(
            rawValue: defaults.string(forKey: Keys.coveragePreviewStyle) ?? ""
        ) ?? .filledCells
        pathPreviewStyle = UnifiedPathPreviewStyle(
            rawValue: defaults.string(forKey: Keys.pathPreviewStyle) ?? ""
        ) ?? .line
        devicePreviewStyle = UnifiedDevicePreviewStyle(
            rawValue: defaults.string(forKey: Keys.devicePreviewStyle) ?? ""
        ) ?? .phoneAndFrustum
        let savedCellSize = defaults.double(forKey: Keys.previewCellSize)
        previewCellSize = savedCellSize > 0 ? Float(savedCellSize) : 0.18
        let savedRays = defaults.integer(forKey: Keys.previewHorizontalRays)
        previewHorizontalRays = savedRays > 0 ? savedRays : 9
        let savedMinDepth = defaults.double(forKey: Keys.previewMinimumDepth)
        previewMinimumDepth = savedMinDepth > 0 ? Float(savedMinDepth) : 0.15
        let savedMaxDepth = defaults.double(forKey: Keys.previewMaximumDepth)
        previewMaximumDepth = savedMaxDepth > 0 ? Float(savedMaxDepth) : 5.0
        previewMinimumConfidence = defaults.object(forKey: Keys.previewMinimumConfidence) == nil ? 1 : defaults.integer(forKey: Keys.previewMinimumConfidence)

        let savedFlush = defaults.integer(forKey: Keys.recorderFlushPackets)
        recorderFlushPackets = savedFlush > 0 ? savedFlush : 30
        recorderSynchronizeOnFlush = defaults.bool(forKey: Keys.recorderSynchronizeOnFlush)
    }

    static let fpsChoices = [1, 2, 5, 10, 15, 30]
    static let previewFPSChoices = [1, 2, 5, 10, 15, 30]
    static let strideChoices = [2, 4, 6, 8, 12]

    var isRecording: Bool { sessionState == .recording }
    var isPaused: Bool { sessionState == .paused }
    var isConnected: Bool { connectionState == .connected }
    var settingsLocked: Bool { sessionState == .recording || sessionState == .paused }
    var needsARSession: Bool { role != .receiver }

    var transferredText: String { Self.byteText(bytesTransferred) }
    var recordedText: String { Self.byteText(recordedBytes) }
    var positionText: String {
        String(format: "X %.2f  Y %.2f  Z %.2f", currentPosition.x, currentPosition.y, currentPosition.z)
    }

    var capabilitySummary: [String] {
        let capabilities = DeviceCapabilities.current
        return [
            capabilities.worldTrackingSupported ? "✓ World Tracking" : "△ World Tracking غير مكتشف",
            capabilities.sceneDepthSupported ? "✓ Scene Depth" : "△ Scene Depth غير مكتشفة",
            "✓ استقبال وحفظ الجلسات",
            "المعالجة بعد الإنهاء: على الجهاز أو الكمبيوتر حسب المرحلة"
        ]
    }

    var estimatedTransferText: String {
        let poseBytes = 72 * poseFPS
        guard scanMode == .scan2D else {
            return String(format: "Pose فقط: نحو %.3f Mbps", Double(poseBytes * 8) / 1_000_000)
        }
        let width = 256
        let height = 192
        let samples = ((width + samplingStride - 1) / samplingStride) * ((height + samplingStride - 1) / samplingStride)
        let bytesPerSample = sendConfidence ? 3 : 2
        let scanBytes = (68 + samples * bytesPerSample) * scanFPS
        return String(format: "Pose %d + Scan %d FPS — نحو %.3f Mbps", poseFPS, scanFPS, Double((poseBytes + scanBytes) * 8) / 1_000_000)
    }

    // MARK: - Role and connection lifecycle

    func applyRoleChange() {
        stopNetworking()
        resetLivePreview()
        lastError = nil
        switch role {
        case .sender:
            sessionState = .idle
            statusMessage = "اتصل بالمستقبل ثم ابدأ جلسة الإرسال."
            if connectionKind == .appleDirectTCP { browser.start() }
        case .receiver:
            browser.stop()
            startReceiver()
        case .standalone:
            browser.stop()
            connectionState = .disconnected
            sessionState = .ready
            statusMessage = "جاهز للتسجيل والمعالجة لاحقًا على هذا الجهاز."
        }
    }

    func connectSender() {
        guard role == .sender, connectionState != .connecting else { return }
        lastError = nil
        connectionState = .connecting
        Task {
            do {
                switch connectionKind {
                case .windowsWebSocket:
                    guard let url = websocketURL else {
                        throw NSError(domain: "3ELiDAR", code: 1, userInfo: [NSLocalizedDescriptionKey: "عنوان IP أو منفذ Windows غير صالح."])
                    }
                    await websocketClient.disconnect()
                    await websocketClient.connect(to: url)
                    startWebSocketReceiveLoop()
                    startWebSocketPingLoop()
                case .appleDirectTCP:
                    if let selectedReceiverID,
                       let endpoint = browser.endpoint(for: selectedReceiverID) {
                        try await directClient.connect(endpoint: endpoint)
                    } else {
                        try await directClient.connect(host: serverIP, port: UInt16(clamping: directPort))
                    }
                }
                connectionState = .connected
                sessionState = .ready
                statusMessage = "تم الاتصال. راجع الإعدادات ثم ابدأ الجلسة."
            } catch {
                connectionState = .failed(error.localizedDescription)
                lastError = error.localizedDescription
                statusMessage = "فشل الاتصال."
            }
        }
    }

    func disconnectSender() {
        websocketReceiveTask?.cancel()
        websocketReceiveTask = nil
        websocketPingTask?.cancel()
        websocketPingTask = nil
        Task {
            await websocketClient.disconnect()
            await directClient.disconnect()
        }
        connectionState = .disconnected
        if role == .sender { sessionState = .idle }
        statusMessage = "تم قطع الاتصال."
    }

    func startReceiver() {
        guard role == .receiver else { return }
        do {
            try receiverServer.start(
                port: UInt16(clamping: directPort),
                serviceName: "3ELiDAR — \(UIDevice.current.name)",
                onPacket: { [weak self] packet in
                    Task { @MainActor in self?.enqueueIncomingPacket(packet) }
                },
                onStatus: { [weak self] message in
                    Task { @MainActor in
                        self?.statusMessage = message
                        if message.contains("جاهز") {
                            self?.connectionState = .listening
                            self?.sessionState = .listening
                        }
                    }
                }
            )
            connectionState = .listening
            sessionState = .listening
            statusMessage = "بانتظار جهاز مرسل على المنفذ \(directPort)."
        } catch {
            connectionState = .failed(error.localizedDescription)
            sessionState = .failed
            lastError = error.localizedDescription
        }
    }

    func stopNetworking() {
        receiverServer.stop()
        disconnectSender()
    }

    // MARK: - Session controls

    func requestStartSession() {
        guard sessionState != .recording else { return }
        if let warning = startWarning() {
            pendingStartAfterWarning = true
            capabilityWarning = warning
            return
        }
        startSessionForced()
    }

    func continueAfterCapabilityWarning() {
        capabilityWarning = nil
        guard pendingStartAfterWarning else { return }
        pendingStartAfterWarning = false
        startSessionForced()
    }

    func cancelCapabilityWarning() {
        pendingStartAfterWarning = false
        capabilityWarning = nil
    }

    func requestProcessing() {
        pendingStartAfterWarning = false
        capabilityWarning = UnifiedCapabilityWarning(
            title: "الجلسة جاهزة للمعالجة",
            message: role == .sender && connectionKind == .windowsWebSocket
                ? "تم حفظ الجلسة على Windows. افتح نافذة المعالجة هناك واختر الإعدادات ثم اضغط بدء المعالجة؛ لن تبدأ تلقائيًا."
                : "تم حفظ الجلسة الخام. محرك معالجة 2D داخل iPhone/iPad هو المرحلة التالية، لذلك لا يحذف التطبيق البيانات ولا ينتج نتيجة وهمية في v0.4.",
            continueTitle: "تم"
        )
    }

    private func startSessionForced() {
        guard role != .receiver else {
            startReceiver()
            return
        }
        if role == .sender, !isConnected {
            lastError = "اتصل بجهاز المستقبل أولًا."
            return
        }

        resetSessionCounters()
        sessionID = UInt64.random(in: 1...UInt64.max)
        frameID = 0
        lastPoseTimestamp = -.greatestFiniteMagnitude
        lastScanTimestamp = -.greatestFiniteMagnitude
        lastPreviewTimestamp = -.greatestFiniteMagnitude
        sessionState = .recording
        statusMessage = scanMode.implementedInCurrentCaptureCore
            ? "يتم الآن جمع البيانات وحفظها. المعالجة مؤجلة حتى نهاية الجلسة."
            : "بدأت الجلسة مع تسجيل Pose فقط؛ حمولة هذا الوضع ما زالت تحت التطوير."

        Task {
            do {
                let shouldRecord = role == .standalone || saveLocalCopyWhenSending
                if shouldRecord {
                    let directory = try await recorder.start(
                        sessionID: sessionID,
                        role: role,
                        scanMode: scanMode,
                        flushEveryPackets: recorderFlushPackets,
                        synchronizeOnFlush: recorderSynchronizeOnFlush,
                        captureSettings: recordingSettingsSnapshot()
                    )
                    localRecordingActive = true
                    currentSessionDirectory = directory
                }

                let hello = try makeHelloPacket()
                let start = try StreamingProtocolV01.sessionControlPacket(
                    sessionID: sessionID,
                    frameID: 0,
                    action: "start",
                    role: role,
                    scanMode: scanMode
                )
                try await dispatchPacket(hello)
                try await dispatchPacket(start)
            } catch {
                sessionState = .failed
                lastError = error.localizedDescription
                statusMessage = "تعذر بدء الجلسة."
            }
        }
    }

    func pauseOrResume() {
        guard role != .receiver else { return }
        switch sessionState {
        case .recording:
            sessionState = .paused
            statusMessage = "الجلسة متوقفة مؤقتًا دون معالجة."
            sendControl(action: "pause")
            Task { try? await recorder.markState("paused") }
        case .paused:
            sessionState = .recording
            lastPoseTimestamp = -.greatestFiniteMagnitude
            lastScanTimestamp = -.greatestFiniteMagnitude
            statusMessage = "استؤنف جمع البيانات."
            sendControl(action: "resume")
            Task { try? await recorder.markState("recording") }
        default:
            break
        }
    }

    func finishSession() {
        guard sessionState == .recording || sessionState == .paused else { return }
        sessionState = .finished
        statusMessage = "يتم إنهاء الكتابة وحفظ الجلسة دون معالجة تلقائية."
        Task {
            do {
                let packet = try StreamingProtocolV01.sessionControlPacket(
                    sessionID: sessionID,
                    frameID: frameID,
                    action: "finish",
                    role: role,
                    scanMode: scanMode
                )
                try await dispatchPacket(packet)
                if localRecordingActive {
                    currentSessionDirectory = try await recorder.finish(reason: "user_finished")
                    localRecordingActive = false
                    await refreshRecorderCounters()
                }
                statusMessage = "انتهت الجلسة وحُفظت البيانات. لا توجد معالجة تلقائية."
            } catch {
                lastError = error.localizedDescription
                statusMessage = "انتهت الجلسة مع خطأ أثناء الحفظ النهائي."
            }
        }
    }

    func resetLivePreview() {
        path.removeAll(keepingCapacity: false)
        coverageCellStore.removeAll(keepingCapacity: false)
        coverageCells.removeAll(keepingCapacity: false)
        currentSweep = nil
        receiverPoses.removeAll(keepingCapacity: false)
        currentPosition = .zero
        currentQuaternion = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    }

    // MARK: - AR capture

    func handle(frame: ARFrame) {
        updateARStatus(frame)
        guard role != .receiver, sessionState == .recording else { return }

        framesCaptured &+= 1
        let poseInterval = 1.0 / Double(max(1, poseFPS))
        let scanInterval = 1.0 / Double(max(1, scanFPS))
        let previewInterval = 1.0 / Double(max(1, previewFPS))
        let poseDue = frame.timestamp - lastPoseTimestamp >= poseInterval
        let scanDue = scanMode == .scan2D && frame.timestamp - lastScanTimestamp >= scanInterval
        let previewDue = frame.timestamp - lastPreviewTimestamp >= previewInterval
        guard poseDue || scanDue || previewDue else { return }

        let thermal = ProcessInfo.processInfo.thermalState
        if thermal == .critical, thermalPolicy == .stopAllAtCritical {
            skippedFrames &+= 1
            depthText = "التقاط متوقف حسب سياسة الحرارة المختارة."
            return
        }

        let transform = frame.camera.transform
        let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let quaternion = simd_quatf(transform)
        currentPosition = position
        currentQuaternion = quaternion

        if previewDue {
            lastPreviewTimestamp = frame.timestamp
            appendPath(position)
        }

        if senderBusy && (poseDue || scanDue) {
            skippedFrames &+= 1
            return
        }

        if poseDue || scanDue {
            if poseDue { lastPoseTimestamp = frame.timestamp }
            if scanDue { lastScanTimestamp = frame.timestamp }
            frameID &+= 1
            let currentFrameID = frameID
            let timestamp = UInt64(max(0, frame.timestamp) * 1_000_000_000)
            let posePacket = StreamingProtocolV01.posePacket(
                sessionID: sessionID,
                frameID: currentFrameID,
                timestampNanoseconds: timestamp,
                position: position,
                quaternion: quaternion,
                trackingState: trackingCode(frame.camera.trackingState),
                thermalState: thermalCode(thermal)
            )

            var scanPacket: Data?
            if scanDue {
                if thermal == .critical, thermalPolicy == .stopDepthAtCritical {
                    depthText = "Depth متوقفة حسب سياسة الحرارة المختارة."
                } else if let depth = frame.sceneDepth {
                    scanPacket = StreamingProtocolV01.scan2DPacket(
                        sessionID: sessionID,
                        frameID: currentFrameID,
                        timestampNanoseconds: timestamp,
                        depthMap: depth.depthMap,
                        confidenceMap: depth.confidenceMap,
                        cameraIntrinsics: frame.camera.intrinsics,
                        cameraImageResolution: frame.camera.imageResolution,
                        samplingStride: samplingStride,
                        includeConfidence: sendConfidence
                    )
                    if previewDue {
                        appendCoverageFromDepth(
                            depth.depthMap,
                            confidenceMap: depth.confidenceMap,
                            intrinsics: frame.camera.intrinsics,
                            imageResolution: frame.camera.imageResolution,
                            transform: transform
                        )
                    }
                    depthText = scanPacket == nil ? "تعذر إنشاء حزمة Depth." : "Depth تُجمع بلا معالجة مباشرة."
                } else {
                    depthText = "لم يوفر ARKit Scene Depth لهذه اللحظة."
                }
            }

            senderBusy = true
            Task {
                defer { senderBusy = false }
                do {
                    try await dispatchPacket(posePacket)
                    posePackets &+= 1
                    if let scanPacket {
                        try await dispatchPacket(scanPacket)
                        scanPackets &+= 1
                    }
                } catch {
                    skippedFrames &+= 1
                    lastError = error.localizedDescription
                    statusMessage = "تعذر حفظ أو إرسال إحدى الحزم."
                }
            }
        }
    }

    // MARK: - Receiver

    private func enqueueIncomingPacket(_ packet: Data) {
        incomingPacketQueue.append(packet)
        guard !processingIncomingQueue else { return }
        processingIncomingQueue = true
        Task { @MainActor in
            while !incomingPacketQueue.isEmpty {
                let next = incomingPacketQueue.removeFirst()
                await processIncomingPacket(next)
            }
            processingIncomingQueue = false
        }
    }

    private func processIncomingPacket(_ packet: Data) async {
        do {
            let (header, payload) = try StreamingProtocolV01.decodePacket(packet)
            packetsReceived &+= 1
            bytesTransferred &+= UInt64(packet.count)

            var helloJSON: [String: Any]?
            if header.type == .hello {
                helloJSON = try StreamingProtocolV01.decodeJSONObject(payload)
                remoteDeviceName = helloJSON?["device_name"] as? String ?? "جهاز Apple"
            }

            if !localRecordingActive || header.sessionID != sessionID {
                if localRecordingActive {
                    _ = try? await recorder.finish(reason: "new_remote_session")
                    localRecordingActive = false
                }
                try await beginReceiverRecording(sessionID: header.sessionID, json: helloJSON)
            }

            try await recorder.append(packet)
            await refreshRecorderCounters()

            switch header.type {
            case .pose:
                let pose = try StreamingProtocolV01.decodePose(payload)
                receiverPoses[header.frameID] = pose
                trimReceiverPoses()
                currentPosition = pose.position
                currentQuaternion = pose.quaternion
                appendPath(pose.position)
                posePackets &+= 1
                trackingText = pose.trackingState == 2 ? "طبيعي" : pose.trackingState == 1 ? "محدود" : "غير متاح"
                thermalText = thermalTextForCode(pose.thermalState)
            case .scan2D:
                let preview = try StreamingProtocolV01.decodeScanPreview(
                    payload,
                    flags: header.flags,
                    horizontalSampleCount: previewHorizontalRays
                )
                if let pose = receiverPoses[header.frameID] {
                    appendCoverage(scan: preview, pose: pose)
                }
                scanPackets &+= 1
                depthText = "يتم حفظ Depth المستلمة بلا معالجة."
            case .sessionControl:
                let json = try StreamingProtocolV01.decodeJSONObject(payload)
                let action = json["action"] as? String ?? ""
                await handleReceiverControl(action)
            case .hello:
                statusMessage = "تم تعريف المرسل: \(remoteDeviceName)."
            default:
                break
            }
        } catch {
            lastError = error.localizedDescription
            statusMessage = "وصلت حزمة غير صالحة: \(error.localizedDescription)"
        }
    }

    private func beginReceiverRecording(sessionID: UInt64, json: [String: Any]?) async throws {
        self.sessionID = sessionID
        frameID = 0
        resetSessionCounters(keepConnection: true)
        sessionState = .recording
        connectionState = .connected
        if let name = json?["device_name"] as? String { remoteDeviceName = name }
        let remoteMode = UnifiedScanMode(rawValue: json?["scan_mode"] as? String ?? "") ?? scanMode
        statusMessage = "بدأ استقبال جلسة من \(remoteDeviceName)."
        currentSessionDirectory = try await recorder.start(
            sessionID: sessionID,
            role: .receiver,
            scanMode: remoteMode,
            flushEveryPackets: recorderFlushPackets,
            synchronizeOnFlush: recorderSynchronizeOnFlush,
            captureSettings: recordingSettingsSnapshot()
        )
        localRecordingActive = true
    }

    private func handleReceiverControl(_ action: String) async {
        switch action {
        case "start", "resume":
            sessionState = .recording
            statusMessage = "يتم استقبال الجلسة وحفظها."
        case "pause":
            sessionState = .paused
            statusMessage = "أوقف المرسل الجلسة مؤقتًا."
        case "finish":
            sessionState = .finished
            statusMessage = "يتم إغلاق الجلسة المستلمة."
            if localRecordingActive {
                currentSessionDirectory = try? await recorder.finish(reason: "remote_finished")
                localRecordingActive = false
                await refreshRecorderCounters()
            }
            statusMessage = "انتهت الجلسة المستلمة وحُفظت. لا توجد معالجة تلقائية."
        default:
            break
        }
    }

    // MARK: - Packet dispatch and local recording

    private func dispatchPacket(_ packet: Data) async throws {
        if role == .sender {
            switch connectionKind {
            case .windowsWebSocket:
                try await websocketClient.send(packet)
            case .appleDirectTCP:
                try await directClient.send(packet)
            }
            bytesTransferred &+= UInt64(packet.count)
        }
        if localRecordingActive {
            try await recorder.append(packet)
            await refreshRecorderCounters()
        }
    }

    private func sendControl(action: String) {
        Task {
            do {
                let packet = try StreamingProtocolV01.sessionControlPacket(
                    sessionID: sessionID,
                    frameID: frameID,
                    action: action,
                    role: role,
                    scanMode: scanMode
                )
                try await dispatchPacket(packet)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func makeHelloPacket() throws -> Data {
        let device = UIDevice.current
        return try StreamingProtocolV01.unifiedHelloPacket(
            sessionID: sessionID,
            role: role,
            scanMode: scanMode,
            deviceName: device.name,
            deviceModel: device.model,
            systemVersion: device.systemVersion
        )
    }

    private func refreshRecorderCounters() async {
        let counters = await recorder.counters()
        recordedPackets = counters.packets
        recordedBytes = counters.bytes
    }

    // MARK: - Lightweight preview only

    private func appendPath(_ position: SIMD3<Float>) {
        let point = UnifiedPreviewPoint(x: position.x, z: position.z)
        if let last = path.last {
            let distance = simd_length(SIMD2<Float>(point.x - last.x, point.z - last.z))
            if distance < 0.01 { return }
        }
        path.append(point)
    }

    private func appendCoverage(scan: UnifiedDecodedScanPreview, pose: UnifiedDecodedPose) {
        var endpoints: [UnifiedPreviewPoint] = []
        for sample in scan.samples {
            guard sample.confidence >= UInt8(clamping: previewMinimumConfidence),
                  sample.depthMeters.isFinite,
                  sample.depthMeters >= previewMinimumDepth,
                  sample.depthMeters <= previewMaximumDepth,
                  scan.fx != 0,
                  scan.fy != 0 else { continue }
            let cameraX = (Float(sample.pixelX) - scan.cx) / scan.fx * sample.depthMeters
            let cameraY = -(Float(sample.pixelY) - scan.cy) / scan.fy * sample.depthMeters
            let cameraZ = -sample.depthMeters
            let rotated = pose.quaternion.act(SIMD3<Float>(cameraX, cameraY, cameraZ))
            endpoints.append(
                UnifiedPreviewPoint(
                    x: pose.position.x + rotated.x,
                    z: pose.position.z + rotated.z
                )
            )
        }
        let origin = UnifiedPreviewPoint(x: pose.position.x, z: pose.position.z)
        updateCoverage(origin: origin, endpoints: endpoints)
    }

    private func appendCoverageFromDepth(
        _ depthMap: CVPixelBuffer,
        confidenceMap: CVPixelBuffer?,
        intrinsics: simd_float3x3,
        imageResolution: CGSize,
        transform: simd_float4x4
    ) {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard width > 0, height > 0,
              imageResolution.width > 0, imageResolution.height > 0,
              CVPixelBufferLockBaseAddress(depthMap, .readOnly) == kCVReturnSuccess,
              let base = CVPixelBufferGetBaseAddress(depthMap) else { return }
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        var confidenceLocked = false
        var confidenceBase: UnsafeMutableRawPointer?
        var confidenceWidth = 0
        var confidenceHeight = 0
        var confidenceBytesPerRow = 0
        if let confidenceMap,
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

        let depthBytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let rowY = max(0, min(height - 1, height / 2))
        let scaleX = Float(width) / Float(imageResolution.width)
        let scaleY = Float(height) / Float(imageResolution.height)
        let fx = intrinsics.columns.0.x * scaleX
        let fy = intrinsics.columns.1.y * scaleY
        let cx = intrinsics.columns.2.x * scaleX
        let cy = intrinsics.columns.2.y * scaleY
        guard fx != 0, fy != 0 else { return }

        let origin = UnifiedPreviewPoint(x: transform.columns.3.x, z: transform.columns.3.z)
        var points: [UnifiedPreviewPoint] = [origin]
        let count = max(2, min(32, previewHorizontalRays))
        let depthRow = base.advanced(by: rowY * depthBytesPerRow).assumingMemoryBound(to: Float32.self)
        for index in 0..<count {
            let x = Int((Double(index) * Double(width - 1) / Double(count - 1)).rounded())
            let depth = depthRow[x]
            guard depth.isFinite, depth >= previewMinimumDepth, depth <= previewMaximumDepth else { continue }
            if let confidenceBase, confidenceWidth > 0, confidenceHeight > 0 {
                let confidenceX = min(Int(Float(x) * Float(confidenceWidth) / Float(width)), confidenceWidth - 1)
                let confidenceY = min(Int(Float(rowY) * Float(confidenceHeight) / Float(height)), confidenceHeight - 1)
                let value = confidenceBase
                    .advanced(by: confidenceY * confidenceBytesPerRow)
                    .assumingMemoryBound(to: UInt8.self)[confidenceX]
                if Int(value) < previewMinimumConfidence { continue }
            }
            let camera = SIMD4<Float>(
                (Float(x) - cx) / fx * depth,
                -(Float(rowY) - cy) / fy * depth,
                -depth,
                1
            )
            let world = transform * camera
            points.append(UnifiedPreviewPoint(x: world.x, z: world.z))
        }
        guard points.count >= 3 else { return }
        updateCoverage(origin: origin, endpoints: Array(points.dropFirst()))
    }

    private func updateCoverage(origin: UnifiedPreviewPoint, endpoints: [UnifiedPreviewPoint]) {
        guard endpoints.count >= 2 else { return }
        currentSweep = UnifiedPreviewSweep(points: [origin] + endpoints)

        let cellSize = max(0.05, previewCellSize)
        for endpoint in endpoints {
            let dx = endpoint.x - origin.x
            let dz = endpoint.z - origin.z
            let distance = max(abs(dx), abs(dz))
            let steps = max(1, Int(ceil(distance / cellSize)))
            for step in 0...steps {
                let amount = Float(step) / Float(steps)
                let x = origin.x + dx * amount
                let z = origin.z + dz * amount
                let cell = UnifiedPreviewCell(
                    xIndex: Int(floor(x / cellSize)),
                    zIndex: Int(floor(z / cellSize))
                )
                if coverageCellStore.insert(cell).inserted {
                    coverageCells.append(cell)
                }
            }
        }
    }

    private func trimReceiverPoses() {
        guard receiverPoses.count > 128 else { return }
        let keep = receiverPoses.keys.sorted().suffix(128)
        let keepSet = Set(keep)
        receiverPoses = receiverPoses.filter { keepSet.contains($0.key) }
    }

    // MARK: - Advisory capability system

    private func startWarning() -> UnifiedCapabilityWarning? {
        let capabilities = DeviceCapabilities.current
        if role == .receiver { return nil }
        if !capabilities.worldTrackingSupported {
            return UnifiedCapabilityWarning(
                title: "World Tracking غير مكتشف",
                message: "لم يكتشف التطبيق دعم World Tracking. يمكنك التجربة، وعند الفشل ستظل خيارات الاستقبال وإدارة الجلسات متاحة.",
                continueTitle: "التجربة على أي حال"
            )
        }
        if scanMode.requiresDepth, !capabilities.sceneDepthSupported {
            return UnifiedCapabilityWarning(
                title: "حساس العمق غير مكتشف",
                message: "هذا الوضع يحتاج Depth، ولم يكتشف النظام Scene Depth على الجهاز. لن تُقفل الميزة؛ يمكن تجربتها وسيستمر حفظ Pose حتى إذا فشلت Depth.",
                continueTitle: "التجربة على أي حال"
            )
        }
        if !scanMode.implementedInCurrentCaptureCore {
            return UnifiedCapabilityWarning(
                title: "الوضع مجهز ولم يكتمل بعد",
                message: "يمكن بدء الجلسة، لكن الإصدار الحالي يسجل Pose فقط لهذا الوضع. لن يدعي التطبيق أنه سجّل 3D قبل إضافة حمولتها الفعلية.",
                continueTitle: "بدء تجربة Pose"
            )
        }
        return nil
    }

    func shutdown() {
        if sessionState == .recording || sessionState == .paused {
            finishSession()
        }
        receiverServer.stop()
        websocketReceiveTask?.cancel()
        websocketPingTask?.cancel()
        browser.stop()
        Task {
            await websocketClient.disconnect()
            await directClient.disconnect()
        }
    }

    // MARK: - Helpers

    private var websocketURL: URL? {
        let ip = serverIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(serverPort), (1...65_535).contains(port), !ip.isEmpty else { return nil }
        return URL(string: "ws://\(ip):\(port)/ws/device")
    }

    private func startWebSocketReceiveLoop() {
        websocketReceiveTask?.cancel()
        websocketReceiveTask = Task {
            while !Task.isCancelled {
                do {
                    let message = try await websocketClient.receive()
                    switch message {
                    case .string(let text):
                        statusMessage = summarizeServerMessage(text)
                    case .data(let data):
                        statusMessage = "استلم التطبيق \(data.count) بايت من Windows."
                    @unknown default:
                        break
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    connectionState = .failed(error.localizedDescription)
                    lastError = error.localizedDescription
                    return
                }
            }
        }
    }

    private func startWebSocketPingLoop() {
        websocketPingTask?.cancel()
        websocketPingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { return }
                do {
                    try await websocketClient.sendPing()
                } catch {
                    connectionState = .failed(error.localizedDescription)
                    lastError = error.localizedDescription
                    return
                }
            }
        }
    }

    private func summarizeServerMessage(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return text }
        return json["message"] as? String ?? text
    }

    private func updateARStatus(_ frame: ARFrame) {
        switch frame.camera.trackingState {
        case .normal: trackingText = "طبيعي"
        case .notAvailable: trackingText = "غير متاح"
        case .limited(let reason):
            switch reason {
            case .initializing: trackingText = "محدود: تهيئة"
            case .excessiveMotion: trackingText = "محدود: حركة سريعة"
            case .insufficientFeatures: trackingText = "محدود: تفاصيل قليلة"
            case .relocalizing: trackingText = "محدود: إعادة تحديد"
            @unknown default: trackingText = "محدود"
            }
        }
        thermalText = thermalTextForState(ProcessInfo.processInfo.thermalState)
        if scanMode == .poseOnly { depthText = "غير مطلوبة في وضع المسار" }
    }

    private func trackingCode(_ state: ARCamera.TrackingState) -> UInt8 {
        switch state {
        case .notAvailable: 0
        case .limited: 1
        case .normal: 2
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

    private func thermalTextForState(_ state: ProcessInfo.ThermalState) -> String {
        thermalTextForCode(thermalCode(state))
    }

    private func thermalTextForCode(_ code: UInt8) -> String {
        switch code {
        case 0: "طبيعي"
        case 1: "دافئ"
        case 2: "مرتفع"
        default: "حرج"
        }
    }

    private func resetSessionCounters(keepConnection: Bool = false) {
        framesCaptured = 0
        posePackets = 0
        scanPackets = 0
        skippedFrames = 0
        packetsReceived = 0
        bytesTransferred = 0
        recordedPackets = 0
        recordedBytes = 0
        currentSessionDirectory = nil
        frameID = 0
        resetLivePreview()
        if !keepConnection { remoteDeviceName = "—" }
    }

    private func recordingSettingsSnapshot() -> [String: Any] {
        [
            "role": role.rawValue,
            "scan_mode": scanMode.rawValue,
            "connection_kind": connectionKind.rawValue,
            "pose_fps": poseFPS,
            "scan_fps": scanFPS,
            "sampling_stride": samplingStride,
            "confidence_enabled": sendConfidence,
            "thermal_policy": thermalPolicy.rawValue,
            "preview_fps": previewFPS,
            "coverage_preview_style": coveragePreviewStyle.rawValue,
            "path_preview_style": pathPreviewStyle.rawValue,
            "device_preview_style": devicePreviewStyle.rawValue,
            "preview_cell_size_m": previewCellSize,
            "preview_storage_policy": "append_only_no_temporal_deletion",
            "preview_horizontal_rays": previewHorizontalRays,
            "preview_minimum_depth_m": previewMinimumDepth,
            "preview_maximum_depth_m": previewMaximumDepth,
            "preview_minimum_confidence": previewMinimumConfidence,
            "recorder_flush_packets": recorderFlushPackets,
            "recorder_synchronize_on_flush": recorderSynchronizeOnFlush
        ]
    }

    private static func validChoice(_ value: Int, choices: [Int], fallback: Int) -> Int {
        choices.contains(value) ? value : fallback
    }

    private static func byteText(_ bytes: UInt64) -> String {
        if bytes >= 1_000_000_000 { return String(format: "%.2f GB", Double(bytes) / 1_000_000_000) }
        if bytes >= 1_000_000 { return String(format: "%.2f MB", Double(bytes) / 1_000_000) }
        if bytes >= 1_000 { return String(format: "%.1f KB", Double(bytes) / 1_000) }
        return "\(bytes) B"
    }
}

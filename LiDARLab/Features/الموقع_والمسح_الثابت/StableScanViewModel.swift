@preconcurrency import ARKit
import Foundation
import SwiftUI
import UIKit
import simd

private final class StablePreviewCoalescer: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: StablePreviewSnapshot?
    private var scheduled = false

    func submit(_ snapshot: StablePreviewSnapshot, deliver: @escaping @Sendable (StablePreviewSnapshot) -> Void) {
        lock.lock()
        latest = snapshot
        let shouldSchedule = !scheduled
        if shouldSchedule { scheduled = true }
        lock.unlock()
        guard shouldSchedule else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let value = self.latest
            self.latest = nil
            self.scheduled = false
            self.lock.unlock()
            if let value { deliver(value) }
        }
    }
}

@MainActor
final class StableScanViewModel: ObservableObject {
    @Published private(set) var sessionState: StableSessionState = .preparing
    @Published private(set) var preview: StablePreviewSnapshot = StableScanViewModel.emptyPreview
    @Published private(set) var statusMessage = "يتم تهيئة Stable Location Core."
    @Published private(set) var lastError: String?
    @Published private(set) var currentSessionDirectory: URL?
    @Published private(set) var processingResult: StableProcessingResult?
    @Published private(set) var processingProgress: Double = 0
    @Published private(set) var processingProgressText = ""
    @Published private(set) var networkConnected = false
    @Published private(set) var networkStatus = "غير متصل"
    @Published private(set) var arSessionEnabled = true
    @Published private(set) var arSessionGeneration = 1
    @Published var depthAdvisoryVisible = false

    @Published var mode: StableScanMode = .locationOnly {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "stableCore.mode")
            if !settingsLocked {
                arSessionGeneration += 1
                pipeline.resetPreview()
                statusMessage = "تم تجهيز وضع \(mode.title). انتظر حتى يصبح التتبع طبيعيًا."
                sessionState = .preparing
            }
        }
    }
    @Published var sendToWindows = false {
        didSet { UserDefaults.standard.set(sendToWindows, forKey: "stableCore.sendToWindows") }
    }
    @Published var serverIP = "192.168.0.2" {
        didSet { UserDefaults.standard.set(serverIP, forKey: "stableCore.serverIP") }
    }
    @Published var serverPort = "8766" {
        didSet { UserDefaults.standard.set(serverPort, forKey: "stableCore.serverPort") }
    }
    @Published var depthFPS = 10 {
        didSet { UserDefaults.standard.set(depthFPS, forKey: "stableCore.depthFPS") }
    }
    @Published var samplingStride = 6 {
        didSet { UserDefaults.standard.set(samplingStride, forKey: "stableCore.samplingStride") }
    }
    @Published var includeConfidence = true {
        didSet { UserDefaults.standard.set(includeConfidence, forKey: "stableCore.includeConfidence") }
    }
    @Published var previewFPS = 5 {
        didSet { UserDefaults.standard.set(previewFPS, forKey: "stableCore.previewFPS") }
    }
    @Published var previewCellSize: Float = 0.18 {
        didSet { UserDefaults.standard.set(Double(previewCellSize), forKey: "stableCore.previewCellSize") }
    }
    @Published var keepScreenAwake = true {
        didSet {
            UserDefaults.standard.set(keepScreenAwake, forKey: "stableCore.keepScreenAwake")
            updateIdleTimer()
        }
    }

    let pipeline: StableCapturePipeline
    private let recorder: StableSessionRecorder
    private let network: StableNetworkSender
    private let processor: StableLocalProcessor
    private let previewCoalescer = StablePreviewCoalescer()
    private var sessionID: UInt64 = 0
    private var viewVisible = false
    private var applicationActive = true

    init() {
        let recorder = StableSessionRecorder()
        let network = StableNetworkSender()
        let processor = StableLocalProcessor()
        let pipeline = StableCapturePipeline(recorder: recorder, network: network)
        self.recorder = recorder
        self.network = network
        self.processor = processor
        self.pipeline = pipeline

        if let savedMode = UserDefaults.standard.string(forKey: "stableCore.mode"),
           let value = StableScanMode(rawValue: savedMode) {
            mode = value
        }
        if UserDefaults.standard.object(forKey: "stableCore.sendToWindows") != nil {
            sendToWindows = UserDefaults.standard.bool(forKey: "stableCore.sendToWindows")
        }
        serverIP = UserDefaults.standard.string(forKey: "stableCore.serverIP") ?? "192.168.0.2"
        serverPort = UserDefaults.standard.string(forKey: "stableCore.serverPort") ?? "8766"
        let savedDepthFPS = UserDefaults.standard.integer(forKey: "stableCore.depthFPS")
        depthFPS = [1, 2, 5, 10, 15].contains(savedDepthFPS) ? savedDepthFPS : 10
        let savedStride = UserDefaults.standard.integer(forKey: "stableCore.samplingStride")
        samplingStride = [2, 4, 6, 8, 12].contains(savedStride) ? savedStride : 6
        if UserDefaults.standard.object(forKey: "stableCore.includeConfidence") != nil {
            includeConfidence = UserDefaults.standard.bool(forKey: "stableCore.includeConfidence")
        }
        let savedPreviewFPS = UserDefaults.standard.integer(forKey: "stableCore.previewFPS")
        previewFPS = [2, 5, 10].contains(savedPreviewFPS) ? savedPreviewFPS : 5
        let savedCell = UserDefaults.standard.double(forKey: "stableCore.previewCellSize")
        previewCellSize = savedCell >= 0.05 ? Float(savedCell) : 0.18
        if UserDefaults.standard.object(forKey: "stableCore.keepScreenAwake") != nil {
            keepScreenAwake = UserDefaults.standard.bool(forKey: "stableCore.keepScreenAwake")
        }

        configureCallbacks()
    }

    var settingsLocked: Bool {
        sessionState == .recording || sessionState == .paused || sessionState == .finalizing || sessionState == .processing
    }

    var sceneDepthSupported: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    var canStart: Bool {
        !settingsLocked && sessionState != .processing
    }

    var canProcess: Bool {
        currentSessionDirectory != nil && (sessionState == .finished || sessionState == .resultReady)
    }

    var positionText: String {
        guard let pose = preview.currentPose else { return "X —  Y —  Z —" }
        return String(format: "X %.3f  Y %.3f  Z %.3f", pose.px, pose.py, pose.pz)
    }

    var orientationText: String {
        guard let pose = preview.currentPose else { return "الاتجاه غير متاح" }
        let forward = pose.quaternion.simdValue.act(SIMD3<Float>(0, 0, -1))
        let pitch = asin(max(-1, min(1, forward.y))) * 180 / .pi
        if pitch > 25 { return String(format: "نحو السقف %.0f°", pitch) }
        if pitch < -25 { return String(format: "نحو الأرض %.0f°", pitch) }
        return String(format: "إلى الأمام %.0f°", pitch)
    }

    var recordedSizeText: String { Self.byteText(preview.recordedBytes) }
    var networkQueueText: String { "\(preview.networkQueuedPackets) / \(Self.byteText(preview.networkQueuedBytes))" }

    func viewDidAppear() {
        viewVisible = true
        arSessionEnabled = true
        updateIdleTimer()
    }

    func viewDidDisappear() {
        viewVisible = false
        if sessionState == .recording || sessionState == .paused {
            endSession(reason: "view_closed")
        } else {
            arSessionEnabled = false
        }
        updateIdleTimer()
    }

    func setApplicationActive(_ active: Bool) {
        applicationActive = active
        updateIdleTimer()
    }

    func requestStart() {
        guard canStart else { return }
        if mode == .scan2D, !sceneDepthSupported {
            depthAdvisoryVisible = true
            return
        }
        startSessionForced()
    }

    func startDespiteDepthAdvisory() {
        depthAdvisoryVisible = false
        startSessionForced()
    }

    func cancelDepthAdvisory() {
        depthAdvisoryVisible = false
    }

    func pauseOrResume() {
        switch sessionState {
        case .recording:
            pipeline.pause()
            sessionState = .paused
            statusMessage = "توقف التسجيل مؤقتًا، بينما ARKit يواصل التتبع دون Reset."
        case .paused:
            pipeline.resume()
            sessionState = .recording
            statusMessage = "استؤنف التسجيل في Segment جديد دون وصل كاذب."
        default:
            break
        }
        updateIdleTimer()
    }

    func endSession(reason: String = "user_finished") {
        guard sessionState == .recording || sessionState == .paused else { return }
        sessionState = .finalizing
        statusMessage = "يتم انتظار آخر Depth ثم إغلاق الملف الخام."
        updateIdleTimer()
        pipeline.finish(reason: reason, mode: mode) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let directory):
                    self.currentSessionDirectory = directory
                    self.sessionState = .finished
                    self.arSessionEnabled = false
                    self.statusMessage = "تم فصل الالتقاط وحفظ الجلسة. المعالجة لن تبدأ إلا بأمرك."
                case .failure(let error):
                    self.sessionState = .failed
                    self.lastError = error.localizedDescription
                    self.statusMessage = "تعذر إنهاء الجلسة بصورة سليمة."
                }
                self.updateIdleTimer()
            }
        }
    }

    func processSavedSession() {
        guard let directory = currentSessionDirectory, canProcess else { return }
        sessionState = .processing
        processingProgress = 0
        processingProgressText = "بدء قراءة الملف الخام"
        arSessionEnabled = false
        updateIdleTimer()
        processor.process(sessionDirectory: directory, mode: mode) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let value):
                    self.processingResult = value
                    self.sessionState = .resultReady
                    self.processingProgress = 1
                    self.processingProgressText = "اكتملت المعالجة"
                    self.statusMessage = "النتيجة مبنية من الملف المحفوظ، وليس من Preview الحية."
                case .failure(let error):
                    self.sessionState = .failed
                    self.lastError = error.localizedDescription
                    self.statusMessage = "فشلت المعالجة، والجلسة الخام ما زالت محفوظة."
                }
            }
        }
    }

    func prepareNewSession() {
        guard !settingsLocked else { return }
        processingResult = nil
        currentSessionDirectory = nil
        lastError = nil
        preview = Self.emptyPreview
        pipeline.resetPreview()
        arSessionGeneration += 1
        arSessionEnabled = true
        sessionState = .preparing
        statusMessage = "بدأ مرجع ARKit جديد. انتظر التتبع الطبيعي ثم ابدأ."
    }

    func connectWindows() {
        guard let url = websocketURL else {
            lastError = "عنوان Windows أو المنفذ غير صالح."
            return
        }
        network.connect(to: url)
    }

    func disconnectWindows() {
        network.disconnect(keepPendingPackets: true)
    }

    private func startSessionForced() {
        lastError = nil
        processingResult = nil
        arSessionEnabled = true
        sessionID = UInt64.random(in: 1...UInt64.max)

        do {
            let directory = try recorder.start(
                sessionID: sessionID,
                mode: mode,
                captureSettings: captureSettingsMetadata()
            )
            currentSessionDirectory = directory
            if sendToWindows {
                connectWindows()
            }
            let hello = try StreamingProtocolV01.stableHelloPacket(sessionID: sessionID, mode: mode)
            let start = try StableProtocolPackets.sessionControlPacket(
                sessionID: sessionID,
                frameID: 0,
                action: "start",
                mode: mode
            )
            pipeline.start(
                sessionID: sessionID,
                settings: captureSettings,
                networkEnabled: sendToWindows,
                helloPacket: hello,
                startPacket: start
            )
            sessionState = .recording
            statusMessage = mode == .locationOnly
                ? "تسجيل كل Pose محليًا. لا Depth ولا معالجة أثناء الجلسة."
                : "تسجيل Pose أولًا ثم Depth بنفس Frame ID. لا معالجة أثناء الجلسة."
            updateIdleTimer()
        } catch {
            sessionState = .failed
            lastError = error.localizedDescription
            statusMessage = "تعذر فتح ملف الجلسة؛ لم يبدأ الالتقاط."
        }
    }

    private var captureSettings: StableCaptureSettings {
        StableCaptureSettings(
            mode: mode,
            depthFPS: depthFPS,
            samplingStride: samplingStride,
            includeConfidence: includeConfidence,
            previewFPS: previewFPS,
            previewCellSize: previewCellSize,
            previewHorizontalRays: 9,
            previewMinimumConfidence: 1,
            previewMinimumDepth: 0.15,
            previewMaximumDepth: 5.0
        )
    }

    private func captureSettingsMetadata() -> [String: Any] {
        [
            "mode": mode.rawValue,
            "pose_recording": "every_arframe",
            "depth_fps": depthFPS,
            "sampling_stride": samplingStride,
            "include_confidence": includeConfidence,
            "preview_fps": previewFPS,
            "preview_cell_size_m": previewCellSize,
            "send_to_windows": sendToWindows,
            "keep_screen_awake": keepScreenAwake,
            "processing_policy": "manual_after_finish_only"
        ]
    }

    private var websocketURL: URL? {
        let ip = serverIP.trimmingCharacters(in: .whitespacesAndNewlines)
        let portText = serverPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ip.isEmpty, let port = Int(portText), (1...65_535).contains(port) else { return nil }
        return URL(string: "ws://\(ip):\(port)/ws/device")
    }

    private func configureCallbacks() {
        let coalescer = previewCoalescer
        pipeline.onPreview = { [weak self] snapshot in
            coalescer.submit(snapshot) { [weak self] value in
                Task { @MainActor in self?.applyPreview(value) }
            }
        }
        pipeline.onStatus = { [weak self] message in
            Task { @MainActor in self?.statusMessage = message }
        }
        pipeline.onError = { [weak self] message in
            Task { @MainActor in
                self?.lastError = message
                self?.statusMessage = "حدث خطأ في Capture Core."
            }
        }
        recorder.onError = { [weak self] message in
            Task { @MainActor in
                self?.lastError = "التخزين: \(message)"
                self?.sessionState = .failed
            }
        }
        network.onState = { [weak self] connected, message in
            Task { @MainActor in
                self?.networkConnected = connected
                self?.networkStatus = message
            }
        }
        processor.onProgress = { [weak self] value, text in
            Task { @MainActor in
                self?.processingProgress = value
                self?.processingProgressText = text
            }
        }
    }

    private func applyPreview(_ value: StablePreviewSnapshot) {
        preview = value
        if sessionState == .preparing, value.trackingText == "طبيعي" {
            sessionState = .ready
            statusMessage = "التتبع طبيعي. يمكنك بدء \(mode.title)."
        }
    }

    private func updateIdleTimer() {
        let activeSession = sessionState == .recording || sessionState == .paused || sessionState == .finalizing
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake && viewVisible && applicationActive && activeSession
    }

    private static func byteText(_ bytes: UInt64) -> String {
        if bytes >= 1_000_000_000 { return String(format: "%.2f GB", Double(bytes) / 1_000_000_000) }
        if bytes >= 1_000_000 { return String(format: "%.2f MB", Double(bytes) / 1_000_000) }
        if bytes >= 1_000 { return String(format: "%.1f KB", Double(bytes) / 1_000) }
        return "\(bytes) B"
    }

    private static let emptyPreview = StablePreviewSnapshot(
        pathSegments: [],
        breakPoints: [],
        coverageCells: [],
        currentPose: nil,
        trackingText: "غير متاح",
        poseCount: 0,
        depthCount: 0,
        recordedPackets: 0,
        recordedBytes: 0,
        networkQueuedPackets: 0,
        networkQueuedBytes: 0
    )
}

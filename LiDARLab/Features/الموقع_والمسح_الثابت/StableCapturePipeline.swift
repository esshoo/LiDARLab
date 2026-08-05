@preconcurrency import ARKit
import CoreVideo
import Foundation
import simd

private final class StableDepthInput: @unchecked Sendable {
    let frameID: UInt64
    let timestampNanoseconds: UInt64
    let depthMap: CVPixelBuffer
    let confidenceMap: CVPixelBuffer?
    let intrinsics: simd_float3x3
    let imageResolution: CGSize
    let pose: StablePoseSample
    let settings: StableCaptureSettings

    init(
        frameID: UInt64,
        timestampNanoseconds: UInt64,
        depthMap: CVPixelBuffer,
        confidenceMap: CVPixelBuffer?,
        intrinsics: simd_float3x3,
        imageResolution: CGSize,
        pose: StablePoseSample,
        settings: StableCaptureSettings
    ) {
        self.frameID = frameID
        self.timestampNanoseconds = timestampNanoseconds
        self.depthMap = depthMap
        self.confidenceMap = confidenceMap
        self.intrinsics = intrinsics
        self.imageResolution = imageResolution
        self.pose = pose
        self.settings = settings
    }
}

final class StableCapturePipeline: @unchecked Sendable {
    private let lock = NSLock()
    private let depthQueue = DispatchQueue(label: "com.essam.3elidar.stable-depth", qos: .userInitiated)
    private let previewQueue = DispatchQueue(label: "com.essam.3elidar.stable-preview", qos: .utility)
    private let recorder: StableSessionRecorder
    private let network: StableNetworkSender

    private var isRecording = false
    private var isPaused = false
    private var networkEnabled = false
    private var sessionID: UInt64 = 0
    private var frameID: UInt64 = 0
    private var settings = StableCaptureSettings(
        mode: .locationOnly,
        depthFPS: 10,
        samplingStride: 6,
        includeConfidence: true,
        previewFPS: 10,
        previewCellSize: 0.18,
        previewHorizontalRays: 9,
        previewMinimumConfidence: 1,
        previewMinimumDepth: 0.15,
        previewMaximumDepth: 5.0
    )
    private var lastDepthTimestamp = -Double.greatestFiniteMagnitude
    private var lastStatusTimestamp = -Double.greatestFiniteMagnitude
    private var poseCount: UInt64 = 0
    private var depthCount: UInt64 = 0
    private var limitedTrackingFrames: UInt64 = 0
    private var depthUnavailableFrames: UInt64 = 0
    private var detectedPreviewBreaks: UInt64 = 0
    private var maximumPreviewStep: Float = 0

    // Preview-only state. It never replaces or truncates the raw packet stream.
    private var pathSegments: [StablePathSegment] = []
    private var breakPoints: [StableBreakPoint] = []
    private var coverageCellStore: Set<StableCoverageCell> = []
    private var lastPreviewPose: StablePoseSample?
    private var nextSegmentID = 0
    private var nextBreakID = 0
    private var forceNewSegment = true
    private var latestTrackingText = "غير متاح"

    var onPreview: (@Sendable (StablePreviewSnapshot) -> Void)?
    var onStatus: (@Sendable (String) -> Void)?
    var onError: (@Sendable (String) -> Void)?

    init(recorder: StableSessionRecorder, network: StableNetworkSender) {
        self.recorder = recorder
        self.network = network
    }

    func start(
        sessionID: UInt64,
        settings: StableCaptureSettings,
        networkEnabled: Bool,
        helloPacket: Data,
        startPacket: Data
    ) {
        lock.lock()
        self.sessionID = sessionID
        self.settings = settings
        self.networkEnabled = networkEnabled
        self.frameID = 0
        self.lastDepthTimestamp = -Double.greatestFiniteMagnitude
        self.poseCount = 0
        self.depthCount = 0
        self.limitedTrackingFrames = 0
        self.depthUnavailableFrames = 0
        self.detectedPreviewBreaks = 0
        self.maximumPreviewStep = 0
        self.isPaused = false
        self.isRecording = true
        lock.unlock()

        previewQueue.async { [weak self] in
            guard let self else { return }
            self.pathSegments.removeAll(keepingCapacity: true)
            self.breakPoints.removeAll(keepingCapacity: true)
            self.coverageCellStore.removeAll(keepingCapacity: true)
            self.lastPreviewPose = nil
            self.nextSegmentID = 0
            self.nextBreakID = 0
            self.forceNewSegment = true
        }

        recorder.append(helloPacket)
        recorder.append(startPacket)
        if networkEnabled {
            network.enqueue(helloPacket)
            network.enqueue(startPacket)
        }
        onStatus?("بدأ التسجيل من Stable Location Core. Pose لها الأولوية الكاملة.")
    }

    func pause() {
        lock.lock()
        isPaused = true
        lock.unlock()
        previewQueue.async { [weak self] in self?.forceNewSegment = true }
        recorder.markState("paused")
    }

    func resume() {
        lock.lock()
        isPaused = false
        lock.unlock()
        previewQueue.async { [weak self] in self?.forceNewSegment = true }
        recorder.markState("recording")
    }

    func ingest(frame: ARFrame) {
        let transform = frame.camera.transform
        let quaternion = simd_quatf(transform)
        let timestampNanoseconds = UInt64(max(0, frame.timestamp) * 1_000_000_000)
        let thermalState = ProcessInfo.processInfo.thermalState
        let trackingState = Self.trackingCode(frame.camera.trackingState)
        let trackingReason = Self.trackingReasonCode(frame.camera.trackingState)
        let mappingStatus = Self.worldMappingCode(frame.worldMappingStatus)

        var currentFrameID: UInt64 = 0
        var shouldRecord = false
        var shouldCaptureDepth = false
        var settingsSnapshot = settings
        var currentSessionID: UInt64 = 0
        var shouldSendNetwork = false

        lock.lock()
        settingsSnapshot = settings
        currentSessionID = sessionID
        shouldSendNetwork = networkEnabled
        if isRecording, !isPaused {
            frameID &+= 1
            currentFrameID = frameID
            shouldRecord = true
            poseCount &+= 1
            if trackingState != 2 { limitedTrackingFrames &+= 1 }

            if settingsSnapshot.mode == .scan2D {
                let interval = 1.0 / Double(max(1, settingsSnapshot.depthFPS))
                if frame.timestamp - lastDepthTimestamp >= interval {
                    lastDepthTimestamp = frame.timestamp
                    shouldCaptureDepth = true
                }
            }
        }
        let shouldPublishIdleStatus = frame.timestamp - lastStatusTimestamp >= 0.20
        if shouldPublishIdleStatus { lastStatusTimestamp = frame.timestamp }
        lock.unlock()

        let pose = StablePoseSample(
            frameID: currentFrameID,
            timestampSeconds: frame.timestamp,
            timestampNanoseconds: timestampNanoseconds,
            px: transform.columns.3.x,
            py: transform.columns.3.y,
            pz: transform.columns.3.z,
            quaternion: StableQuaternion(quaternion),
            trackingState: trackingState,
            trackingReason: trackingReason,
            worldMappingStatus: mappingStatus,
            thermalState: Self.thermalCode(thermalState)
        )

        if shouldRecord {
            let packet = StreamingProtocolV01.posePacket(
                sessionID: currentSessionID,
                frameID: currentFrameID,
                timestampNanoseconds: timestampNanoseconds,
                position: pose.position,
                quaternion: quaternion,
                trackingState: trackingState,
                thermalState: pose.thermalState
            )
            // Local append is enqueued before any heavy depth work or UI update.
            recorder.append(packet)
            if shouldSendNetwork { network.enqueue(packet) }
            enqueuePreviewPose(pose, settings: settingsSnapshot)
        } else if shouldPublishIdleStatus {
            publishStatusOnly(pose)
        }

        guard shouldRecord, shouldCaptureDepth else { return }
        guard let depth = frame.sceneDepth else {
            lock.lock()
            depthUnavailableFrames &+= 1
            lock.unlock()
            onStatus?("هذه الـFrame لا تحتوي sceneDepth؛ Pose تم حفظها دون تغيير.")
            return
        }

        let input = StableDepthInput(
            frameID: currentFrameID,
            timestampNanoseconds: timestampNanoseconds,
            depthMap: depth.depthMap,
            confidenceMap: depth.confidenceMap,
            intrinsics: frame.camera.intrinsics,
            imageResolution: frame.camera.imageResolution,
            pose: pose,
            settings: settingsSnapshot
        )
        depthQueue.async { [weak self] in self?.processDepth(input, sessionID: currentSessionID, sendNetwork: shouldSendNetwork) }
    }

    func finish(
        reason: String,
        mode: StableScanMode,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        lock.lock()
        isRecording = false
        isPaused = false
        let finalFrameID = frameID
        let finalSessionID = sessionID
        lock.unlock()

        // This block runs only after every already-enqueued depth job has completed.
        depthQueue.async { [weak self] in
            guard let self else { return }
            do {
                let finishPacket = try StableProtocolPackets.sessionControlPacket(
                    sessionID: finalSessionID,
                    frameID: finalFrameID,
                    action: "finish",
                    mode: mode
                )
                self.recorder.append(finishPacket)
                if self.networkEnabled { self.network.enqueue(finishPacket) }

                self.lock.lock()
                let diagnostics: [String: Any] = [
                    "pose_frames": self.poseCount,
                    "depth_frames": self.depthCount,
                    "limited_tracking_frames": self.limitedTrackingFrames,
                    "depth_unavailable_frames": self.depthUnavailableFrames,
                    "preview_breaks": self.detectedPreviewBreaks,
                    "maximum_preview_step_m": self.maximumPreviewStep,
                    "location_core_policy": "record_every_arframe_before_depth_network_and_ui"
                ]
                self.lock.unlock()

                self.recorder.finish(reason: reason, diagnostics: diagnostics, completion: completion)
            } catch {
                completion(.failure(error))
            }
        }
    }

    func resetPreview() {
        previewQueue.async { [weak self] in
            guard let self else { return }
            self.pathSegments.removeAll()
            self.breakPoints.removeAll()
            self.coverageCellStore.removeAll()
            self.lastPreviewPose = nil
            self.forceNewSegment = true
            self.publishPreview(currentPose: nil)
        }
    }

    private func processDepth(_ input: StableDepthInput, sessionID: UInt64, sendNetwork: Bool) {
        guard let packet = StreamingProtocolV01.scan2DPacket(
            sessionID: sessionID,
            frameID: input.frameID,
            timestampNanoseconds: input.timestampNanoseconds,
            depthMap: input.depthMap,
            confidenceMap: input.confidenceMap,
            cameraIntrinsics: input.intrinsics,
            cameraImageResolution: input.imageResolution,
            samplingStride: input.settings.samplingStride,
            includeConfidence: input.settings.includeConfidence
        ) else {
            onStatus?("تعذر تكوين حزمة Depth للإطار \(input.frameID). Pose محفوظة.")
            return
        }

        recorder.append(packet)
        if sendNetwork { network.enqueue(packet) }
        lock.lock()
        depthCount &+= 1
        lock.unlock()

        let endpoints = previewEndpoints(from: input)
        guard !endpoints.isEmpty else { return }
        previewQueue.async { [weak self] in
            guard let self else { return }
            self.rasterizeCoverage(from: input.pose, endpoints: endpoints, cellSize: input.settings.previewCellSize)
        }
    }

    private func enqueuePreviewPose(_ pose: StablePoseSample, settings: StableCaptureSettings) {
        previewQueue.async { [weak self] in
            guard let self else { return }
            let interval = 1.0 / Double(max(1, settings.previewFPS))
            if let last = self.lastPreviewPose,
               pose.timestampSeconds - last.timestampSeconds < interval {
                return
            }
            self.appendPreviewPose(pose)
            self.publishPreview(currentPose: pose)
        }
    }

    private func publishStatusOnly(_ pose: StablePoseSample) {
        previewQueue.async { [weak self] in
            guard let self else { return }
            self.latestTrackingText = Self.trackingText(state: pose.trackingState, reason: pose.trackingReason)
            self.publishPreview(currentPose: pose)
        }
    }

    private func appendPreviewPose(_ pose: StablePoseSample) {
        latestTrackingText = Self.trackingText(state: pose.trackingState, reason: pose.trackingReason)
        guard pose.trackingState == 2 else {
            forceNewSegment = true
            lastPreviewPose = pose
            return
        }

        let point = StablePathPoint(x: pose.px, z: pose.pz, timestampNanoseconds: pose.timestampNanoseconds)
        var breakReason: String?
        if let previous = lastPreviewPose, previous.trackingState == 2 {
            let dt = pose.timestampSeconds - previous.timestampSeconds
            let dx = pose.px - previous.px
            let dy = pose.py - previous.py
            let dz = pose.pz - previous.pz
            let distance = sqrt(dx * dx + dy * dy + dz * dz)
            maximumPreviewStep = max(maximumPreviewStep, distance)
            let speed = dt > 0 ? distance / Float(dt) : Float.greatestFiniteMagnitude
            if dt <= 0 || dt > 0.35 {
                breakReason = "فجوة زمنية \(String(format: "%.2f", dt)) ث"
            } else if distance > 0.75 || speed > 4.0 {
                breakReason = "انتقال غير متصل \(String(format: "%.2f", distance)) م"
            }
        } else if lastPreviewPose != nil {
            breakReason = "استعادة التتبع"
        }

        if forceNewSegment || breakReason != nil || pathSegments.isEmpty {
            nextSegmentID += 1
            pathSegments.append(StablePathSegment(id: nextSegmentID, points: [point]))
            forceNewSegment = false
            if let breakReason {
                nextBreakID += 1
                breakPoints.append(StableBreakPoint(id: nextBreakID, x: pose.px, z: pose.pz, reason: breakReason))
                detectedPreviewBreaks &+= 1
            }
        } else {
            pathSegments[pathSegments.count - 1].points.append(point)
        }
        lastPreviewPose = pose
    }

    private func publishPreview(currentPose: StablePoseSample?) {
        let recorderStats = recorder.currentSnapshot()
        let networkStats = network.snapshot()
        let snapshot = StablePreviewSnapshot(
            pathSegments: pathSegments,
            breakPoints: breakPoints,
            coverageCells: Array(coverageCellStore),
            currentPose: currentPose,
            trackingText: latestTrackingText,
            poseCount: poseCount,
            depthCount: depthCount,
            recordedPackets: recorderStats.packets,
            recordedBytes: recorderStats.bytes,
            networkQueuedPackets: networkStats.queuedPackets,
            networkQueuedBytes: networkStats.queuedBytes
        )
        onPreview?(snapshot)
    }

    private func previewEndpoints(from input: StableDepthInput) -> [SIMD3<Float>] {
        let depthMap = input.depthMap
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard width > 0, height > 0, input.imageResolution.width > 0, input.imageResolution.height > 0 else { return [] }
        guard CVPixelBufferLockBaseAddress(depthMap, .readOnly) == kCVReturnSuccess,
              let base = CVPixelBufferGetBaseAddress(depthMap) else { return [] }
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        var confidenceBase: UnsafeMutableRawPointer?
        var confidenceWidth = 0
        var confidenceHeight = 0
        var confidenceBytesPerRow = 0
        var confidenceLocked = false
        if let confidenceMap = input.confidenceMap,
           CVPixelBufferLockBaseAddress(confidenceMap, .readOnly) == kCVReturnSuccess {
            confidenceLocked = true
            confidenceBase = CVPixelBufferGetBaseAddress(confidenceMap)
            confidenceWidth = CVPixelBufferGetWidth(confidenceMap)
            confidenceHeight = CVPixelBufferGetHeight(confidenceMap)
            confidenceBytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
        }
        defer {
            if confidenceLocked, let confidenceMap = input.confidenceMap {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
        }

        let depthBytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let scaleX = Float(width) / Float(input.imageResolution.width)
        let scaleY = Float(height) / Float(input.imageResolution.height)
        let fx = input.intrinsics.columns.0.x * scaleX
        let fy = input.intrinsics.columns.1.y * scaleY
        let cx = input.intrinsics.columns.2.x * scaleX
        let cy = input.intrinsics.columns.2.y * scaleY
        guard fx != 0, fy != 0 else { return [] }

        let rayCount = max(3, input.settings.previewHorizontalRays)
        let sourceY = min(max(Int(cy.rounded()), 0), height - 1)
        let depthRow = base.advanced(by: sourceY * depthBytesPerRow).assumingMemoryBound(to: Float32.self)
        let rotation = input.pose.quaternion.simdValue
        var endpoints: [SIMD3<Float>] = []
        endpoints.reserveCapacity(rayCount)

        for index in 0..<rayCount {
            let fraction = rayCount == 1 ? 0.5 : Float(index) / Float(rayCount - 1)
            let sourceX = min(max(Int((fraction * Float(width - 1)).rounded()), 0), width - 1)
            let depthMeters = depthRow[sourceX]
            guard depthMeters.isFinite,
                  depthMeters >= input.settings.previewMinimumDepth,
                  depthMeters <= input.settings.previewMaximumDepth else { continue }

            if let confidenceBase, confidenceWidth > 0, confidenceHeight > 0 {
                let confidenceX = min(Int(Float(sourceX) * Float(confidenceWidth) / Float(width)), confidenceWidth - 1)
                let confidenceY = min(Int(Float(sourceY) * Float(confidenceHeight) / Float(height)), confidenceHeight - 1)
                let confidenceRow = confidenceBase
                    .advanced(by: confidenceY * confidenceBytesPerRow)
                    .assumingMemoryBound(to: UInt8.self)
                guard Int(confidenceRow[confidenceX]) >= input.settings.previewMinimumConfidence else { continue }
            }

            let cameraPoint = SIMD3<Float>(
                (Float(sourceX) - cx) / fx * depthMeters,
                -(Float(sourceY) - cy) / fy * depthMeters,
                -depthMeters
            )
            endpoints.append(input.pose.position + rotation.act(cameraPoint))
        }
        return endpoints
    }

    private func rasterizeCoverage(from pose: StablePoseSample, endpoints: [SIMD3<Float>], cellSize: Float) {
        let size = max(0.05, cellSize)
        for endpoint in endpoints {
            let dx = endpoint.x - pose.px
            let dz = endpoint.z - pose.pz
            let steps = max(1, Int(ceil(max(abs(dx), abs(dz)) / size)))
            for step in 0...steps {
                let amount = Float(step) / Float(steps)
                let x = pose.px + dx * amount
                let z = pose.pz + dz * amount
                coverageCellStore.insert(StableCoverageCell(
                    ix: Int(floor(x / size)),
                    iz: Int(floor(z / size))
                ))
            }
        }
    }

    private static func trackingCode(_ state: ARCamera.TrackingState) -> UInt8 {
        switch state {
        case .notAvailable: 0
        case .limited: 1
        case .normal: 2
        }
    }

    private static func trackingReasonCode(_ state: ARCamera.TrackingState) -> UInt8 {
        guard case .limited(let reason) = state else { return 0 }
        switch reason {
        case .initializing: return 1
        case .excessiveMotion: return 2
        case .insufficientFeatures: return 3
        case .relocalizing: return 4
        @unknown default: return 255
        }
    }

    private static func worldMappingCode(_ status: ARFrame.WorldMappingStatus) -> UInt8 {
        switch status {
        case .notAvailable: 0
        case .limited: 1
        case .extending: 2
        case .mapped: 3
        @unknown default: 255
        }
    }

    private static func thermalCode(_ state: ProcessInfo.ThermalState) -> UInt8 {
        switch state {
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        case .critical: 3
        @unknown default: 3
        }
    }

    private static func trackingText(state: UInt8, reason: UInt8) -> String {
        switch state {
        case 2: return "طبيعي"
        case 1:
            switch reason {
            case 1: return "محدود: تهيئة"
            case 2: return "محدود: حركة سريعة"
            case 3: return "محدود: تفاصيل بصرية قليلة"
            case 4: return "محدود: إعادة تحديد الموقع"
            default: return "محدود"
            }
        default: return "غير متاح"
        }
    }
}

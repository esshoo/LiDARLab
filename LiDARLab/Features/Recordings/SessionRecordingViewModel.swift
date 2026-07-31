import ARKit
import Combine
import CoreImage
import RealityKit
import UIKit

final class SessionRecordingViewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var frameCount = 0
    @Published private(set) var droppedFrames = 0
    @Published private(set) var centerDistance: Float?
    @Published private(set) var statusMessage = "ابدأ التسجيل لحفظ الصورة والعمق وحركة الكاميرا."
    @Published private(set) var latestSession: RecordedSessionSummary?
    @Published private(set) var savedSessions: [RecordedSessionSummary] = []
    @Published private(set) var errorMessage: String?

    var framesPerSecond: Double = 2
    var durationLimit: TimeInterval = 60
    var preferSmoothedDepth = true

    private weak var arView: ARView?
    private let processingQueue = DispatchQueue(label: "com.esshoo.LiDARLab.recording", qos: .userInitiated)
    private let ciContext = CIContext(options: [.cacheIntermediates: true])
    private let stateLock = NSLock()
    private let writeGroup = DispatchGroup()
    private var currentOrientation: UIInterfaceOrientation = .portrait
    private var updateTimer: Timer?
    private var lastCenterUpdate: TimeInterval = 0

    private var recordingActive = false
    private var recordingStartDate: Date?
    private var recordingStartFrameTimestamp: TimeInterval?
    private var recordingFolderURL: URL?
    private var framesFolderURL: URL?
    private var recordingName = "Session"
    private var recordedFrames: [RecordedFrameMetadata] = []
    private var pendingWrites = 0
    private var nextFrameIndex = 0
    private var lastScheduledTimestamp: TimeInterval = -.greatestFiniteMagnitude
    private var internalDroppedFrames = 0
    private var recordingSmoothedDepth = true
    private var requestedFPS: Double = 2

    override init() {
        super.init()
        refreshSessions()
    }

    func attach(to arView: ARView) {
        self.arView = arView
        arView.session.delegate = self
        startSession(resetTracking: true)
    }

    func updateOrientation(_ orientation: UIInterfaceOrientation) {
        currentOrientation = orientation
    }

    func startSession(resetTracking: Bool) {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            errorMessage = "تسجيل العمق يحتاج إلى جهاز يدعم Scene Depth."
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.frameSemantics.insert(.sceneDepth)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }

        let options: ARSession.RunOptions = resetTracking ? [.resetTracking, .removeExistingAnchors] : []
        arView?.session.run(configuration, options: options)
    }

    func startRecording(name: String) {
        guard !isRecording, !isFinalizing else { return }
        do {
            let storage = LiDARLabStorage.shared
            try storage.ensureDirectories()
            let cleanName = storage.sanitizedName(name, fallback: "Session")
            let date = Date()
            let folderName = storage.timestampedName(prefix: cleanName, date: date)
            let folder = storage.recordingsURL.appendingPathComponent(folderName, isDirectory: true)
            let framesFolder = folder.appendingPathComponent("Frames", isDirectory: true)
            try FileManager.default.createDirectory(at: framesFolder, withIntermediateDirectories: true)

            stateLock.lock()
            recordingActive = true
            recordingStartDate = date
            recordingStartFrameTimestamp = nil
            recordingFolderURL = folder
            framesFolderURL = framesFolder
            recordingName = cleanName
            recordedFrames = []
            pendingWrites = 0
            nextFrameIndex = 0
            lastScheduledTimestamp = -.greatestFiniteMagnitude
            internalDroppedFrames = 0
            recordingSmoothedDepth = preferSmoothedDepth
            requestedFPS = max(1, min(4, framesPerSecond))
            stateLock.unlock()

            elapsedTime = 0
            frameCount = 0
            droppedFrames = 0
            latestSession = nil
            isRecording = true
            statusMessage = "جارٍ التسجيل… حرّك الجهاز ببطء لتقليل الإطارات المفقودة."
            startUpdateTimer()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() {
        stateLock.lock()
        let wasActive = recordingActive
        recordingActive = false
        stateLock.unlock()
        guard wasActive else { return }

        updateTimer?.invalidate()
        updateTimer = nil
        isRecording = false
        isFinalizing = true
        statusMessage = "جارٍ إنهاء الملفات وكتابة فهرس الجلسة…"

        writeGroup.notify(queue: processingQueue) { [weak self] in
            self?.finalizeRecording()
        }
    }

    func leaveView() {
        if isRecording { stopRecording() }
        arView?.session.pause()
    }

    func refreshSessions() {
        savedSessions = RecordedSessionSummary.loadAll()
    }

    func delete(_ session: RecordedSessionSummary) {
        do {
            try FileManager.default.removeItem(at: session.folderURL)
            if latestSession?.id == session.id { latestSession = nil }
            refreshSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let depthData = selectedDepth(from: frame)
        if frame.timestamp - lastCenterUpdate >= 0.15 {
            lastCenterUpdate = frame.timestamp
            let center = depthData.flatMap { centerDepth(from: $0.depthMap) }
            DispatchQueue.main.async { [weak self] in self?.centerDistance = center }
        }

        stateLock.lock()
        guard recordingActive else {
            stateLock.unlock()
            return
        }

        if recordingStartFrameTimestamp == nil {
            recordingStartFrameTimestamp = frame.timestamp
        }
        let startTimestamp = recordingStartFrameTimestamp ?? frame.timestamp
        let elapsed = max(0, frame.timestamp - startTimestamp)
        let shouldStop = elapsed >= durationLimit
        let interval = 1.0 / max(requestedFPS, 1)
        let canScheduleByTime = frame.timestamp - lastScheduledTimestamp >= interval

        guard !shouldStop else {
            stateLock.unlock()
            DispatchQueue.main.async { [weak self] in self?.stopRecording() }
            return
        }

        guard canScheduleByTime else {
            stateLock.unlock()
            return
        }
        lastScheduledTimestamp = frame.timestamp

        guard pendingWrites < 2, let depthData else {
            internalDroppedFrames += 1
            let dropped = internalDroppedFrames
            stateLock.unlock()
            DispatchQueue.main.async { [weak self] in self?.droppedFrames = dropped }
            return
        }

        let index = nextFrameIndex
        nextFrameIndex += 1
        pendingWrites += 1
        writeGroup.enter()
        let framesFolder = framesFolderURL
        let orientation = currentOrientation
        stateLock.unlock()

        guard let framesFolder else {
            completePendingWrite(frameMetadata: nil, failed: true)
            return
        }

        processingQueue.async { [self, frame, depthData] in
            do {
                let metadata = try self.writeFrame(
                    frame,
                    depthData: depthData,
                    index: index,
                    relativeTimestamp: elapsed,
                    folder: framesFolder,
                    orientation: orientation
                )
                self.completePendingWrite(frameMetadata: metadata, failed: false)
            } catch {
                self.completePendingWrite(frameMetadata: nil, failed: true)
                DispatchQueue.main.async { [weak self] in
                    self?.errorMessage = "تعذر حفظ أحد إطارات التسجيل: \(error.localizedDescription)"
                }
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = error.localizedDescription
            if self?.isRecording == true { self?.stopRecording() }
        }
    }

    private func startUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.stateLock.lock()
            let start = self.recordingStartDate
            let count = self.recordedFrames.count
            let dropped = self.internalDroppedFrames
            self.stateLock.unlock()
            self.elapsedTime = start.map { Date().timeIntervalSince($0) } ?? 0
            self.frameCount = count
            self.droppedFrames = dropped
        }
    }

    private func selectedDepth(from frame: ARFrame) -> ARDepthData? {
        stateLock.lock()
        let useSmoothed = recordingActive ? recordingSmoothedDepth : preferSmoothedDepth
        stateLock.unlock()
        if useSmoothed { return frame.smoothedSceneDepth ?? frame.sceneDepth }
        return frame.sceneDepth
    }

    private func completePendingWrite(frameMetadata: RecordedFrameMetadata?, failed: Bool) {
        stateLock.lock()
        pendingWrites = max(0, pendingWrites - 1)
        if let frameMetadata { recordedFrames.append(frameMetadata) }
        if failed { internalDroppedFrames += 1 }
        let count = recordedFrames.count
        let dropped = internalDroppedFrames
        stateLock.unlock()

        writeGroup.leave()
        DispatchQueue.main.async { [weak self] in
            self?.frameCount = count
            self?.droppedFrames = dropped
        }
    }

    private func finalizeRecording() {
        stateLock.lock()
        let folder = recordingFolderURL
        let name = recordingName
        let createdAt = recordingStartDate ?? Date()
        let frames = recordedFrames.sorted { $0.index < $1.index }
        let dropped = internalDroppedFrames
        let fps = requestedFPS
        let smoothed = recordingSmoothedDepth
        stateLock.unlock()

        guard let folder else {
            DispatchQueue.main.async { [weak self] in
                self?.isFinalizing = false
                self?.errorMessage = "تعذر تحديد مجلد التسجيل."
            }
            return
        }

        do {
            let manifest = RecordedSessionManifest(
                formatVersion: 1,
                name: name,
                createdAt: createdAt,
                endedAt: Date(),
                requestedFramesPerSecond: fps,
                smoothedDepth: smoothed,
                droppedFrames: dropped,
                frames: frames
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(manifest).write(
                to: folder.appendingPathComponent("session.json"),
                options: .atomic
            )
            let summary = try RecordedSessionSummary.load(from: folder)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.latestSession = summary
                self.isFinalizing = false
                self.elapsedTime = summary.duration
                self.frameCount = summary.frameCount
                self.droppedFrames = summary.manifest.droppedFrames
                self.statusMessage = summary.frameCount > 0
                    ? "تم حفظ الجلسة. يمكنك تشغيلها أو مشاركتها."
                    : "تم إنشاء الجلسة، لكن لم تُحفظ إطارات عمق صالحة."
                self.refreshSessions()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.isFinalizing = false
                self?.errorMessage = error.localizedDescription
                self?.statusMessage = "تعذر إنهاء التسجيل."
            }
        }
    }

    private func writeFrame(
        _ frame: ARFrame,
        depthData: ARDepthData,
        index: Int,
        relativeTimestamp: TimeInterval,
        folder: URL,
        orientation: UIInterfaceOrientation
    ) throws -> RecordedFrameMetadata {
        let stem = String(format: "frame-%06d", index)
        let colorName = "\(stem)-color.jpg"
        let heatName = "\(stem)-depth.png"
        let depthName = "\(stem)-depth.bin"

        guard let colorImage = makeCameraImage(frame.capturedImage, orientation: orientation),
              let colorData = colorImage.jpegData(compressionQuality: 0.82) else {
            throw NSError(domain: "SessionRecording", code: 1, userInfo: [NSLocalizedDescriptionKey: "تعذر تحويل صورة الكاميرا."])
        }
        let processed = processDepth(depthData.depthMap, orientation: orientation.recordingImageOrientation)
        guard let heatImage = processed.image, let heatData = heatImage.pngData() else {
            throw NSError(domain: "SessionRecording", code: 2, userInfo: [NSLocalizedDescriptionKey: "تعذر إنشاء خريطة العمق."])
        }

        try colorData.write(to: folder.appendingPathComponent(colorName), options: .atomic)
        try heatData.write(to: folder.appendingPathComponent(heatName), options: .atomic)
        try rawDepthData(from: depthData.depthMap).write(
            to: folder.appendingPathComponent(depthName),
            options: .atomic
        )

        return RecordedFrameMetadata(
            index: index,
            relativeTimestamp: relativeTimestamp,
            colorFile: "Frames/\(colorName)",
            heatMapFile: "Frames/\(heatName)",
            depthFile: "Frames/\(depthName)",
            depthWidth: CVPixelBufferGetWidth(depthData.depthMap),
            depthHeight: CVPixelBufferGetHeight(depthData.depthMap),
            centerDistanceMeters: processed.center,
            minimumDistanceMeters: processed.minimum,
            maximumDistanceMeters: processed.maximum,
            cameraTransformColumnMajor: flatten(frame.camera.transform),
            cameraIntrinsicsColumnMajor: flatten(frame.camera.intrinsics),
            trackingState: String(describing: frame.camera.trackingState)
        )
    }

    private func makeCameraImage(_ pixelBuffer: CVPixelBuffer, orientation: UIInterfaceOrientation) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation.recordingImageOrientation)
    }

    private func centerDepth(from pixelBuffer: CVPixelBuffer) -> Float? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer) / MemoryLayout<Float32>.stride
        let values = base.assumingMemoryBound(to: Float32.self)
        var samples: [Float] = []
        for y in max(0, height / 2 - 2)...min(height - 1, height / 2 + 2) {
            for x in max(0, width / 2 - 2)...min(width - 1, width / 2 + 2) {
                let value = values[y * stride + x]
                if value.isFinite, value > 0.05, value < 10 { samples.append(value) }
            }
        }
        samples.sort()
        return samples.isEmpty ? nil : samples[samples.count / 2]
    }

    private func processDepth(
        _ pixelBuffer: CVPixelBuffer,
        orientation: UIImage.Orientation
    ) -> (image: UIImage?, center: Float?, minimum: Float?, maximum: Float?) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return (nil, nil, nil, nil) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer) / MemoryLayout<Float32>.stride
        let values = base.assumingMemoryBound(to: Float32.self)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var minimum = Float.greatestFiniteMagnitude
        var maximum: Float = 0
        var centerSamples: [Float] = []

        for y in 0..<height {
            for x in 0..<width {
                let depth = values[y * stride + x]
                let index = (y * width + x) * 4
                guard depth.isFinite, depth > 0.05, depth <= 8 else {
                    pixels[index + 3] = 0
                    continue
                }
                minimum = min(minimum, depth)
                maximum = max(maximum, depth)
                if abs(x - width / 2) <= 2, abs(y - height / 2) <= 2 { centerSamples.append(depth) }
                let color = Self.heatColor(max(0, min(1, (depth - 0.2) / 4.8)))
                pixels[index] = color.0
                pixels[index + 1] = color.1
                pixels[index + 2] = color.2
                pixels[index + 3] = 255
            }
        }
        centerSamples.sort()
        return (
            Self.makeRGBAImage(pixels, width: width, height: height, orientation: orientation),
            centerSamples.isEmpty ? nil : centerSamples[centerSamples.count / 2],
            minimum == Float.greatestFiniteMagnitude ? nil : minimum,
            maximum == 0 ? nil : maximum
        )
    }

    private func rawDepthData(from pixelBuffer: CVPixelBuffer) -> Data {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return Data() }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let packedBytes = width * MemoryLayout<Float32>.stride
        var data = Data(capacity: packedBytes * height)
        for row in 0..<height {
            let pointer = base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            data.append(contentsOf: UnsafeBufferPointer(start: pointer, count: packedBytes))
        }
        return data
    }

    private static func heatColor(_ value: Float) -> (UInt8, UInt8, UInt8) {
        let t = max(0, min(1, value))
        let red = UInt8(max(0, min(255, 255 * min(1, max(0, 1.5 - abs(4 * t - 3))))))
        let green = UInt8(max(0, min(255, 255 * min(1, max(0, 1.5 - abs(4 * t - 2))))))
        let blue = UInt8(max(0, min(255, 255 * min(1, max(0, 1.5 - abs(4 * t - 1))))))
        return (red, green, blue)
    }

    private static func makeRGBAImage(
        _ pixels: [UInt8],
        width: Int,
        height: Int,
        orientation: UIImage.Orientation
    ) -> UIImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }

    private func flatten(_ matrix: simd_float4x4) -> [Float] {
        [matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w,
         matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w,
         matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w,
         matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w]
    }

    private func flatten(_ matrix: simd_float3x3) -> [Float] {
        [matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z,
         matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z,
         matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z]
    }
}

private extension UIInterfaceOrientation {
    var recordingImageOrientation: UIImage.Orientation {
        switch self {
        case .portrait: .right
        case .portraitUpsideDown: .left
        case .landscapeLeft: .up
        case .landscapeRight: .down
        default: .right
        }
    }
}

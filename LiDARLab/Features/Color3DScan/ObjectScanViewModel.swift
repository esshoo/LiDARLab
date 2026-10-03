import ARKit
import Combine
import CoreImage
import Foundation
import RealityKit
import UIKit
import simd

final class ObjectScanViewModel: NSObject, ObservableObject, ARSessionDelegate {
    enum Phase: Equatable {
        case idle
        case selecting
        case capturing
        case reconstructing
        case completed
        case failed

        var title: String {
            switch self {
            case .idle: "جاهز للبدء"
            case .selecting: "اختيار المجسم"
            case .capturing: "مسح المجسم"
            case .reconstructing: "بناء النموذج"
            case .completed: "اكتمل النموذج"
            case .failed: "حدث خطأ"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var targetSelected = false
    @Published private(set) var capturedImageCount = 0
    @Published private(set) var targetImageCount = 48
    @Published private(set) var coverageProgress: Double = 0
    @Published private(set) var imageProgress: Double = 0
    @Published private(set) var estimatedCompletion: Double = 0
    @Published private(set) var reconstructionProgress: Double = 0
    @Published private(set) var currentDistanceMeters: Float = 0
    @Published private(set) var trackingState = "متوقف"
    @Published private(set) var statusMessage = "ابدأ جلسة جديدة ثم المس المجسم المطلوب على الشاشة."
    @Published private(set) var modelURL: URL?
    @Published private(set) var sessionFolderURL: URL?
    @Published var errorMessage: String?

    private weak var arView: ARView?
    private let fileManager = FileManager.default
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let captureQueue = DispatchQueue(label: "com.essam.3E.LiDARLab.objectscan.images", qos: .utility)
    private let stateLock = NSLock()

    private var runtimeOptions = Color3DScanSettings.objectOptions
    private var sessionGeneration = UUID()
    private var captureEnabled = false
    private var targetWorldPoint: SIMD3<Float>?
    private var selectionAnchor: AnchorEntity?
    private var imagesFolderURL: URL?
    private var modelFolderURL: URL?
    private var capturedImageURLs: [URL] = []
    private var visitedCoverageBins: Set<Int> = []
    private let coverageBinCount = 36
    private var lastCaptureTimestamp: TimeInterval = -100
    private var lastCaptureYaw: Float?
    private var photogrammetrySession: PhotogrammetrySession?
    private var reconstructionTask: Task<Void, Never>?

    var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported && PhotogrammetrySession.isSupported
    }

    var canBeginCapture: Bool {
        phase == .selecting && targetSelected
    }

    var canFinishCapture: Bool {
        phase == .capturing && capturedImageCount >= runtimeOptions.minimumImagesBeforeFinish
    }

    var minimumImagesBeforeFinish: Int {
        runtimeOptions.minimumImagesBeforeFinish
    }

    var objectSizeTitle: String {
        runtimeOptions.objectSizePreset.title
    }

    func attach(to arView: ARView) {
        self.arView = arView
        arView.automaticallyConfigureSession = false
        arView.session.delegate = self
    }

    func startNewScan() {
        guard isSupported else {
            errorMessage = "هذا الجهاز لا يدعم ARWorldTracking وإعادة بناء Photogrammetry على الجهاز."
            return
        }
        guard let arView else {
            errorMessage = "عارض الكاميرا غير جاهز بعد."
            return
        }

        cancelInternal(removeFiles: true)
        runtimeOptions = Color3DScanSettings.objectOptions
        targetImageCount = runtimeOptions.targetImageCount

        do {
            let storage = LiDARLabStorage.shared
            try storage.ensureDirectories()
            let root = storage.capturesURL
                .appendingPathComponent("Color3D", isDirectory: true)
                .appendingPathComponent("Objects", isDirectory: true)
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

            let folder = root.appendingPathComponent(
                storage.timestampedName(prefix: "ObjectScan") + "-" + String(UUID().uuidString.prefix(8)),
                isDirectory: true
            )
            let images = folder.appendingPathComponent("Images", isDirectory: true)
            let model = folder.appendingPathComponent("Model", isDirectory: true)
            try fileManager.createDirectory(at: images, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: model, withIntermediateDirectories: true)

            stateLock.lock()
            sessionGeneration = UUID()
            captureEnabled = false
            targetWorldPoint = nil
            imagesFolderURL = images
            modelFolderURL = model
            capturedImageURLs.removeAll(keepingCapacity: true)
            visitedCoverageBins.removeAll(keepingCapacity: true)
            lastCaptureTimestamp = -100
            lastCaptureYaw = nil
            stateLock.unlock()

            sessionFolderURL = folder
            modelURL = nil
            targetSelected = false
            capturedImageCount = 0
            coverageProgress = 0
            imageProgress = 0
            estimatedCompletion = 0
            reconstructionProgress = 0
            currentDistanceMeters = 0
            phase = .selecting
            statusMessage = "المس المجسم المطلوب مباشرة على الشاشة. سنثبت نقطة الهدف ثم تلف حولها."

            clearSelectionMarker()
            let configuration = ARWorldTrackingConfiguration()
            configuration.worldAlignment = .gravity
            configuration.planeDetection = [.horizontal, .vertical]
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }
            if runtimeOptions.useSmoothedDepthForSelection,
               ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                configuration.frameSemantics.insert(.smoothedSceneDepth)
            }
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
            statusMessage = "تعذر بدء جلسة مسح المجسم."
        }
    }

    func selectTarget(at screenPoint: CGPoint) {
        guard phase == .selecting,
              let arView,
              let frame = arView.session.currentFrame else { return }

        let selected = depthWorldPoint(at: screenPoint, frame: frame, arView: arView)
            ?? raycastWorldPoint(at: screenPoint, arView: arView)

        guard let selected else {
            DispatchQueue.main.async { [weak self] in
                self?.statusMessage = "لم أستطع تثبيت نقطة على المجسم هنا. اقترب قليلًا، وجّه الكاميرا للجسم، ثم المسه مرة أخرى."
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
            return
        }

        stateLock.lock()
        targetWorldPoint = selected
        stateLock.unlock()

        showSelectionMarker(at: selected)
        let camera = SIMD3<Float>(
            frame.camera.transform.columns.3.x,
            frame.camera.transform.columns.3.y,
            frame.camera.transform.columns.3.z
        )
        let distance = simd_distance(camera, selected)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.targetSelected = true
            self.currentDistanceMeters = distance
            self.statusMessage = "تم تحديد الهدف عند \(String(format: "%.2f", distance)) م. تأكد أن العلامة على المجسم الصحيح ثم ابدأ المسح."
            if self.runtimeOptions.haptics {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }

    func clearTargetSelection() {
        guard phase == .selecting else { return }
        stateLock.lock()
        targetWorldPoint = nil
        stateLock.unlock()
        clearSelectionMarker()
        targetSelected = false
        currentDistanceMeters = 0
        statusMessage = "المس المجسم المطلوب على الشاشة لتحديده من جديد."
    }

    func beginCapture() {
        guard phase == .selecting else { return }
        stateLock.lock()
        let hasTarget = targetWorldPoint != nil
        captureEnabled = hasTarget
        visitedCoverageBins.removeAll(keepingCapacity: true)
        lastCaptureTimestamp = -100
        lastCaptureYaw = nil
        stateLock.unlock()
        guard hasTarget else {
            errorMessage = "حدد المجسم باللمس أولًا."
            return
        }

        capturedImageCount = 0
        coverageProgress = 0
        imageProgress = 0
        estimatedCompletion = 0
        phase = .capturing
        statusMessage = "لف حول المجسم ببطء مع إبقاء العلامة في منتصف المشهد. الإنهاء يدوي عندما ترى أن التغطية كافية."
    }

    func captureManualImage() {
        guard phase == .capturing,
              let frame = arView?.session.currentFrame else { return }
        scheduleImageCapture(frame: frame, force: true)
    }

    func finishCapture() {
        guard phase == .capturing else { return }
        guard capturedImageCount >= runtimeOptions.minimumImagesBeforeFinish else {
            errorMessage = "التقط \(runtimeOptions.minimumImagesBeforeFinish) صور على الأقل قبل بناء النموذج. لديك الآن \(capturedImageCount)."
            return
        }

        stateLock.lock()
        captureEnabled = false
        stateLock.unlock()
        arView?.session.pause()
        captureQueue.sync {}

        phase = .reconstructing
        reconstructionProgress = 0
        statusMessage = "جاري تحليل \(capturedImageCount) صورة وبناء النموذج الملوّن…"
        startReconstruction()
    }

    func pauseCapture() {
        arView?.session.pause()
    }

    func cancelAndReset() {
        cancelInternal(removeFiles: phase != .completed)
        phase = .idle
        targetSelected = false
        capturedImageCount = 0
        coverageProgress = 0
        imageProgress = 0
        estimatedCompletion = 0
        reconstructionProgress = 0
        currentDistanceMeters = 0
        trackingState = "متوقف"
        modelURL = nil
        sessionFolderURL = nil
        statusMessage = "ابدأ جلسة جديدة ثم المس المجسم المطلوب على الشاشة."
        errorMessage = nil
    }

    func clearError() {
        errorMessage = nil
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        stateLock.lock()
        let capturing = captureEnabled
        let target = targetWorldPoint
        let options = runtimeOptions
        stateLock.unlock()
        guard capturing, let target else { return }

        let cameraTransform = frame.camera.transform
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )
        let toTarget = target - cameraPosition
        let distance = simd_length(toTarget)
        guard distance > 0.001 else { return }

        let directionToTarget = toTarget / distance
        let cameraForward = -simd_normalize(SIMD3<Float>(
            cameraTransform.columns.2.x,
            cameraTransform.columns.2.y,
            cameraTransform.columns.2.z
        ))
        let facing = simd_dot(cameraForward, directionToTarget)

        let horizontal = SIMD2<Float>(cameraPosition.x - target.x, cameraPosition.z - target.z)
        let yaw = atan2(horizontal.x, horizontal.y)
        let bin = coverageBin(for: yaw)
        let distanceRange = options.objectSizePreset.recommendedDistanceRange
        let distanceOK = distanceRange.contains(distance)
        let facingOK = facing > 0.62

        if facingOK && distanceOK {
            stateLock.lock()
            visitedCoverageBins.insert(bin)
            let coverageCount = visitedCoverageBins.count
            stateLock.unlock()
            updateLiveProgress(distance: distance, coverageCount: coverageCount)

            if options.autoCapture {
                scheduleImageCapture(frame: frame, force: false, yaw: yaw)
            }
        } else {
            let guidance: String
            if facing <= 0.62 {
                guidance = "وجّه الكاميرا نحو علامة الهدف."
            } else if distance < distanceRange.lowerBound {
                guidance = "أنت قريب جدًا. ابتعد قليلًا عن المجسم."
            } else {
                guidance = "أنت بعيد. اقترب قليلًا من المجسم."
            }
            DispatchQueue.main.async { [weak self] in
                self?.currentDistanceMeters = distance
                self?.statusMessage = guidance
            }
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let text: String
        switch camera.trackingState {
        case .normal: text = "طبيعي"
        case .notAvailable: text = "غير متاح"
        case .limited(let reason):
            switch reason {
            case .initializing: text = "تهيئة"
            case .excessiveMotion: text = "حركة سريعة"
            case .insufficientFeatures: text = "تفاصيل قليلة"
            case .relocalizing: text = "إعادة تحديد الموقع"
            @unknown default: text = "محدود"
            }
        }
        DispatchQueue.main.async { [weak self] in self?.trackingState = text }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.phase = .failed
            self?.errorMessage = error.localizedDescription
            self?.statusMessage = "فشلت جلسة AR أثناء مسح المجسم."
        }
    }

    private func updateLiveProgress(distance: Float, coverageCount: Int) {
        let coverage = min(max(Double(coverageCount) / Double(coverageBinCount), 0), 1)
        let image = min(max(Double(capturedImageCount) / Double(max(targetImageCount, 1)), 0), 1)
        let completion = min(1, coverage * 0.68 + image * 0.32)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentDistanceMeters = distance
            self.coverageProgress = coverage
            self.imageProgress = image
            self.estimatedCompletion = completion
            if completion >= 0.98 {
                self.statusMessage = "التغطية ممتازة. يمكنك إنهاء المسح الآن أو التقاط صور إضافية يدويًا."
            } else {
                self.statusMessage = "استمر في الالتفاف حول الهدف. التغطية التقديرية \(Int(coverage * 100))%."
            }
        }
    }

    private func scheduleImageCapture(frame: ARFrame, force: Bool, yaw suppliedYaw: Float? = nil) {
        stateLock.lock()
        guard captureEnabled,
              let imagesFolderURL else {
            stateLock.unlock()
            return
        }

        let maxAllowedImages = min(140, max(runtimeOptions.targetImageCount + 20, runtimeOptions.targetImageCount))
        guard capturedImageURLs.count < maxAllowedImages else {
            stateLock.unlock()
            return
        }

        let yaw: Float
        if let suppliedYaw {
            yaw = suppliedYaw
        } else if let target = targetWorldPoint {
            let position = frame.camera.transform.columns.3
            yaw = atan2(position.x - target.x, position.z - target.z)
        } else {
            stateLock.unlock()
            return
        }

        if !force {
            let elapsed = frame.timestamp - lastCaptureTimestamp
            guard elapsed >= runtimeOptions.minimumCaptureInterval else {
                stateLock.unlock()
                return
            }
            if let lastCaptureYaw {
                guard angularDistance(yaw, lastCaptureYaw) >= runtimeOptions.minimumAngularStepRadians else {
                    stateLock.unlock()
                    return
                }
            }
            guard capturedImageURLs.count < runtimeOptions.targetImageCount else {
                stateLock.unlock()
                return
            }
        }

        lastCaptureTimestamp = frame.timestamp
        lastCaptureYaw = yaw
        let generation = sessionGeneration
        stateLock.unlock()

        captureQueue.async { [weak self, frame] in
            self?.saveImage(frame: frame, folder: imagesFolderURL, generation: generation)
        }
    }

    private func saveImage(frame: ARFrame, folder: URL, generation: UUID) {
        let pixelBuffer = frame.capturedImage
        let originalWidth = CVPixelBufferGetWidth(pixelBuffer)
        let originalHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard originalWidth > 0, originalHeight > 0 else { return }

        let scale = min(1, CGFloat(runtimeOptions.imageMaxDimension) / CGFloat(max(originalWidth, originalHeight)))
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent.integral),
              let jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: runtimeOptions.jpegQuality) else { return }

        stateLock.lock()
        guard generation == sessionGeneration, captureEnabled else {
            stateLock.unlock()
            return
        }
        let index = capturedImageURLs.count + 1
        stateLock.unlock()

        let fileURL = folder.appendingPathComponent(String(format: "object-%03d.jpg", index))
        do {
            try jpeg.write(to: fileURL, options: .atomic)
        } catch {
            return
        }

        stateLock.lock()
        guard generation == sessionGeneration, captureEnabled else {
            stateLock.unlock()
            try? fileManager.removeItem(at: fileURL)
            return
        }
        capturedImageURLs.append(fileURL)
        let count = capturedImageURLs.count
        let target = max(runtimeOptions.targetImageCount, 1)
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.capturedImageCount = count
            self.imageProgress = min(1, Double(count) / Double(target))
            self.estimatedCompletion = min(1, self.coverageProgress * 0.68 + self.imageProgress * 0.32)
            if self.runtimeOptions.haptics {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func startReconstruction() {
        reconstructionTask?.cancel()
        guard let imagesFolderURL, let modelFolderURL else {
            phase = .failed
            errorMessage = "مجلد صور المجسم غير متاح."
            return
        }

        let finalURL = modelFolderURL.appendingPathComponent("model.usdz")
        try? fileManager.removeItem(at: finalURL)
        let options = runtimeOptions

        reconstructionTask = Task { [weak self] in
            guard let self else { return }
            do {
                var configuration = PhotogrammetrySession.Configuration()
                configuration.sampleOrdering = .sequential
                configuration.featureSensitivity = options.highFeatureSensitivity ? .high : .normal
                configuration.isObjectMaskingEnabled = options.objectMasking

                let session = try PhotogrammetrySession(input: imagesFolderURL, configuration: configuration)
                self.photogrammetrySession = session
                let request = PhotogrammetrySession.Request.modelFile(
                    url: finalURL,
                    detail: .reduced,
                    geometry: nil
                )
                try session.process(requests: [request])

                for try await output in session.outputs {
                    guard !Task.isCancelled else {
                        session.cancel()
                        return
                    }
                    switch output {
                    case .requestProgress(_, fractionComplete: let fraction):
                        DispatchQueue.main.async { [weak self] in
                            self?.reconstructionProgress = fraction
                            self?.statusMessage = "بناء النموذج… \(Int(fraction * 100))%"
                        }
                    case .requestError(_, let error):
                        DispatchQueue.main.async { [weak self] in
                            self?.phase = .failed
                            self?.errorMessage = error.localizedDescription
                            self?.statusMessage = "تعذر إنشاء النموذج من الصور الحالية."
                        }
                    case .processingComplete:
                        if self.fileManager.fileExists(atPath: finalURL.path) {
                            self.writeManifest(modelURL: finalURL)
                            if !options.keepSourceImages {
                                try? self.fileManager.removeItem(at: imagesFolderURL)
                            }
                            DispatchQueue.main.async { [weak self] in
                                self?.modelURL = finalURL
                                self?.reconstructionProgress = 1
                                self?.phase = .completed
                                self?.statusMessage = "اكتمل نموذج USDZ الملوّن."
                            }
                        } else {
                            DispatchQueue.main.async { [weak self] in
                                self?.phase = .failed
                                self?.errorMessage = "انتهت المعالجة لكن ملف USDZ غير موجود."
                            }
                        }
                    default:
                        break
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.phase = .failed
                    self?.errorMessage = error.localizedDescription
                    self?.statusMessage = "فشلت إعادة بناء المجسم."
                }
            }
            self.photogrammetrySession = nil
        }
    }

    private func writeManifest(modelURL: URL) {
        guard let sessionFolderURL else { return }
        stateLock.lock()
        let point = targetWorldPoint
        let imageCount = capturedImageURLs.count
        let coverage = Double(visitedCoverageBins.count) / Double(coverageBinCount)
        stateLock.unlock()

        let record = ObjectScanManifest(
            schemaVersion: 3,
            createdAt: Date(),
            selectedTargetWorldPoint: point.map { [$0.x, $0.y, $0.z] },
            objectSizePreset: runtimeOptions.objectSizePreset.rawValue,
            imageCount: imageCount,
            targetImageCount: runtimeOptions.targetImageCount,
            estimatedCoverage: coverage,
            imageMaxDimension: runtimeOptions.imageMaxDimension,
            jpegQuality: runtimeOptions.jpegQuality,
            highFeatureSensitivity: runtimeOptions.highFeatureSensitivity,
            objectMasking: runtimeOptions.objectMasking,
            modelFile: "Model/\(modelURL.lastPathComponent)",
            keptSourceImages: runtimeOptions.keepSourceImages,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(to: sessionFolderURL.appendingPathComponent("scan.json"), options: .atomic)
        } catch {
            // The model is already complete; metadata failure should not discard it.
        }
    }

    private func depthWorldPoint(at screenPoint: CGPoint, frame: ARFrame, arView: ARView) -> SIMD3<Float>? {
        let depthData: ARDepthData?
        if runtimeOptions.useSmoothedDepthForSelection {
            depthData = frame.smoothedSceneDepth ?? frame.sceneDepth
        } else {
            depthData = frame.sceneDepth ?? frame.smoothedSceneDepth
        }
        guard let depthData else { return nil }

        let viewport = arView.bounds.size
        guard viewport.width > 0, viewport.height > 0 else { return nil }
        let orientation = arView.window?.windowScene?.interfaceOrientation ?? .portrait
        let normalizedView = CGPoint(x: screenPoint.x / viewport.width, y: screenPoint.y / viewport.height)
        let imageToView = frame.displayTransform(for: orientation, viewportSize: viewport)
        let normalizedImage = normalizedView.applying(imageToView.inverted())
        guard normalizedImage.x >= 0, normalizedImage.x <= 1,
              normalizedImage.y >= 0, normalizedImage.y <= 1 else { return nil }

        let depthMap = depthData.depthMap
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let dx = min(max(Int(normalizedImage.x * CGFloat(depthWidth)), 0), depthWidth - 1)
        let dy = min(max(Int(normalizedImage.y * CGFloat(depthHeight)), 0), depthHeight - 1)
        guard let depth = medianDepth(depthMap, x: dx, y: dy), depth > 0.08, depth < 8 else { return nil }

        let imageResolution = frame.camera.imageResolution
        let u = Float(normalizedImage.x) * Float(imageResolution.width)
        let v = Float(normalizedImage.y) * Float(imageResolution.height)
        let intrinsics = frame.camera.intrinsics
        let fx = intrinsics.columns.0.x
        let fy = intrinsics.columns.1.y
        let cx = intrinsics.columns.2.x
        let cy = intrinsics.columns.2.y
        guard fx > 0, fy > 0 else { return nil }

        let cameraPoint = SIMD4<Float>(
            (u - cx) / fx * depth,
            -(v - cy) / fy * depth,
            -depth,
            1
        )
        let world = frame.camera.transform * cameraPoint
        return SIMD3<Float>(world.x, world.y, world.z)
    }

    private func medianDepth(_ buffer: CVPixelBuffer, x: Int, y: Int) -> Float? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<Float32>.size
        let values = base.assumingMemoryBound(to: Float32.self)

        var samples: [Float] = []
        samples.reserveCapacity(9)
        for yy in max(0, y - 1)...min(height - 1, y + 1) {
            for xx in max(0, x - 1)...min(width - 1, x + 1) {
                let value = values[yy * stride + xx]
                if value.isFinite, value > 0.05, value < 10 {
                    samples.append(value)
                }
            }
        }
        guard !samples.isEmpty else { return nil }
        samples.sort()
        return samples[samples.count / 2]
    }

    private func raycastWorldPoint(at screenPoint: CGPoint, arView: ARView) -> SIMD3<Float>? {
        let result = arView.raycast(from: screenPoint, allowing: .existingPlaneGeometry, alignment: .any).first
            ?? arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .any).first
        guard let result else { return nil }
        let t = result.worldTransform.columns.3
        return SIMD3<Float>(t.x, t.y, t.z)
    }

    private func showSelectionMarker(at point: SIMD3<Float>) {
        clearSelectionMarker()
        guard let arView else { return }
        let radius = max(0.018, runtimeOptions.objectSizePreset.approximateDiameterMeters * 0.025)
        let anchor = AnchorEntity(world: point)
        let material = SimpleMaterial(color: UIColor.systemCyan, isMetallic: false)
        let marker = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material])
        anchor.addChild(marker)
        arView.scene.addAnchor(anchor)
        selectionAnchor = anchor
    }

    private func clearSelectionMarker() {
        if let selectionAnchor {
            arView?.scene.removeAnchor(selectionAnchor)
        }
        selectionAnchor = nil
    }

    private func coverageBin(for yaw: Float) -> Int {
        let twoPi = Float.pi * 2
        var normalized = yaw + Float.pi
        normalized.formTruncatingRemainder(dividingBy: twoPi)
        if normalized < 0 { normalized += twoPi }
        return min(max(Int((normalized / twoPi) * Float(coverageBinCount)), 0), coverageBinCount - 1)
    }

    private func angularDistance(_ a: Float, _ b: Float) -> Float {
        abs(atan2(sin(a - b), cos(a - b)))
    }

    private func cancelInternal(removeFiles: Bool) {
        stateLock.lock()
        captureEnabled = false
        sessionGeneration = UUID()
        stateLock.unlock()
        reconstructionTask?.cancel()
        reconstructionTask = nil
        photogrammetrySession?.cancel()
        photogrammetrySession = nil
        arView?.session.pause()
        clearSelectionMarker()

        if removeFiles, let sessionFolderURL {
            try? fileManager.removeItem(at: sessionFolderURL)
        }
    }

    deinit {
        reconstructionTask?.cancel()
        photogrammetrySession?.cancel()
    }
}

private struct ObjectScanManifest: Codable {
    let schemaVersion: Int
    let createdAt: Date
    let selectedTargetWorldPoint: [Float]?
    let objectSizePreset: String
    let imageCount: Int
    let targetImageCount: Int
    let estimatedCoverage: Double
    let imageMaxDimension: Int
    let jpegQuality: Double
    let highFeatureSensitivity: Bool
    let objectMasking: Bool
    let modelFile: String
    let keptSourceImages: Bool
    let appVersion: String
}

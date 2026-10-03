import ARKit
import Combine
import Foundation
import RealityKit
import SwiftUI
import UIKit
import simd

@MainActor
final class ObjectScanViewModel: NSObject, ObservableObject, ARSessionDelegate {
    enum Phase: Equatable {
        case idle
        case aiming
        case preparing
        case readyForDetection
        case detecting
        case capturing
        case finishing
        case reconstructing
        case completed
        case failed

        var title: String {
            switch self {
            case .idle: "جاهز"
            case .aiming: "اختيار المجسم"
            case .preparing: "تهيئة Object Capture"
            case .readyForDetection: "التعرف على المجسم"
            case .detecting: "ضبط حدود المجسم"
            case .capturing: "مسح المجسم"
            case .finishing: "إنهاء الالتقاط"
            case .reconstructing: "بناء النموذج"
            case .completed: "اكتمل النموذج"
            case .failed: "حدث خطأ"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var cameraReady = false
    @Published private(set) var targetSelected = false
    @Published private(set) var targetCentered = false
    @Published private(set) var captureSession: ObjectCaptureSession?
    @Published private(set) var shotCount = 0
    @Published private(set) var maximumShotCount = 0
    @Published private(set) var passNumber = 1
    @Published private(set) var scanPassComplete = false
    @Published private(set) var completedPasses = 0
    @Published private(set) var captureTrackingState = "—"
    @Published private(set) var reconstructionProgress: Double = 0
    @Published private(set) var invalidSampleCount = 0
    @Published private(set) var skippedSampleCount = 0
    @Published private(set) var currentDistanceMeters: Float = 0
    @Published private(set) var trackingState = "متوقف"
    @Published private(set) var feedbackMessage: String?
    @Published private(set) var statusMessage = "افتح الكاميرا، المس المجسم، ثم وجّه الهدف إلى منتصف الإطار قبل اكتشاف Apple."
    @Published private(set) var modelURL: URL?
    @Published private(set) var sessionFolderURL: URL?
    @Published var errorMessage: String?

    private weak var arView: ARView?
    private let fileManager = FileManager.default
    private var targetWorldPoint: SIMD3<Float>?
    private var selectionAnchor: AnchorEntity?
    private var preselectionRunning = false

    private var options = Color3DScanSettings.appleObjectOptions
    private var workFolderURL: URL?
    private var imagesURL: URL?
    private var checkpointsURL: URL?
    private var localModelURL: URL?
    private var finalFolderURL: URL?
    private var listenerTasks: [Task<Void, Never>] = []
    private var reconstructionTask: Task<Void, Never>?
    private var photogrammetrySession: PhotogrammetrySession?

    var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported && ObjectCaptureSession.isSupported && PhotogrammetrySession.isSupported
    }

    var canFinishCapture: Bool {
        phase == .capturing && shotCount >= options.minimumImagesBeforeFinish
    }

    var minimumImagesBeforeFinish: Int {
        options.minimumImagesBeforeFinish
    }

    var recommendedPasses: Int {
        options.recommendedPasses
    }

    var shouldShowPreselectionMesh: Bool {
        phase == .aiming && targetSelected && options.showPreselectionMesh
    }

    var shouldWarnBeforeFinish: Bool {
        guard phase == .capturing, canFinishCapture, options.preferCompletedPassBeforeFinish else { return false }
        return completedPasses < max(options.recommendedPasses, 1)
    }

    var finishWarningMessage: String {
        if completedPasses == 0 {
            return "لم تكتمل أي جولة في Capture Dial بعد. يمكنك الإنهاء يدويًا، لكن إعادة البناء قد تحتوي على تشوهات أو أجزاء ناقصة."
        }
        if completedPasses < recommendedPasses {
            return "اكتملت \(completedPasses) من \(recommendedPasses) جولات موصى بها. يمكنك الإنهاء الآن، أو إضافة جولة أخرى من ارتفاع مختلف لتحسين الشكل."
        }
        return ""
    }

    func attach(to arView: ARView) {
        self.arView = arView
        arView.automaticallyConfigureSession = false
        arView.session.delegate = self
        if phase == .aiming, !preselectionRunning {
            startPreselectionSession()
        }
    }

    func startNewScan() {
        guard isSupported else {
            errorMessage = "هذا الجهاز لا يدعم Object Capture وإعادة البناء على الجهاز."
            return
        }

        cleanup(removeWorkingFiles: true)
        options = Color3DScanSettings.appleObjectOptions
        modelURL = nil
        sessionFolderURL = nil
        shotCount = 0
        maximumShotCount = 0
        passNumber = 1
        scanPassComplete = false
        completedPasses = 0
        captureTrackingState = "—"
        reconstructionProgress = 0
        invalidSampleCount = 0
        skippedSampleCount = 0
        feedbackMessage = nil
        targetWorldPoint = nil
        targetSelected = false
        targetCentered = false
        cameraReady = false
        currentDistanceMeters = 0
        phase = .aiming
        statusMessage = "جاري تجهيز الكاميرا لاختيار المجسم باللمس…"
        clearSelectionMarker()

        if arView != nil {
            startPreselectionSession()
        }
    }

    func selectTarget(at screenPoint: CGPoint) {
        guard phase == .aiming else { return }
        guard cameraReady, let arView, let frame = arView.session.currentFrame else {
            statusMessage = "انتظر حتى تصبح الكاميرا جاهزة ثم المس المجسم."
            return
        }

        let target = depthWorldPoint(at: screenPoint, frame: frame, arView: arView)
            ?? raycastWorldPoint(at: screenPoint, arView: arView)
        guard let target else {
            statusMessage = "لم أجد سطحًا موثوقًا عند نقطة اللمس. وجّه الهاتف للمجسم وحاول مرة أخرى."
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }

        targetWorldPoint = target
        targetSelected = true
        showSelectionMarker(at: target)
        updateTargetGuidance(frame: frame, arView: arView)
        if options.haptics {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    func clearTargetSelection() {
        guard phase == .aiming else { return }
        targetWorldPoint = nil
        targetSelected = false
        targetCentered = false
        currentDistanceMeters = 0
        clearSelectionMarker()
        statusMessage = "المس المجسم الذي تريد مسحه."
    }

    /// Touch selection is a targeting aid. Apple's detector itself only detects the object at camera center.
    func acceptTargetAndPrepareObjectCapture() {
        guard phase == .aiming, targetSelected else { return }
        guard targetCentered else {
            statusMessage = "حرّك الهاتف حتى تصبح علامة الهدف قرب منتصف الإطار ثم حاول مرة أخرى."
            return
        }

        arView?.session.pause()
        preselectionRunning = false
        clearSelectionMarker()
        prepareOfficialSession()
    }

    func startOfficialDetection() {
        guard let session = captureSession, phase == .readyForDetection else { return }
        guard session.startDetecting() else {
            statusMessage = "تعذر بدء اكتشاف المجسم. اجعله في منتصف الإطار وبإضاءة جيدة ثم أعد المحاولة."
            return
        }
        handleState(session.state)
    }

    func resetDetection() {
        guard let session = captureSession else { return }
        if session.resetDetection() {
            handleState(session.state)
            statusMessage = "أعيد ضبط الاكتشاف. أبقِ المجسم في المنتصف ثم ابدأ التعرف من جديد."
        }
    }

    func startCapturing() {
        guard let session = captureSession, phase == .detecting else { return }
        session.startCapturing()
        handleState(session.state)
        statusMessage = "لف حول المجسم ببطء. واجهة Apple تعرض الـPoint Cloud وCapture Dial للمناطق الناقصة."
    }

    func requestManualShot() {
        guard let session = captureSession,
              phase == .capturing,
              session.canRequestImageCapture else { return }
        session.requestImageCapture()
    }

    func beginAdditionalPass() {
        guard let session = captureSession, phase == .capturing else { return }
        session.beginNewScanPass()
        passNumber += 1
        scanPassComplete = false
        statusMessage = "بدأت الجولة \(passNumber). غيّر ارتفاع الهاتف لتغطية تفاصيل جديدة."
    }

    func beginPassAfterFlip() {
        guard let session = captureSession, phase == .capturing else { return }
        session.beginNewScanPassAfterFlip()
        passNumber += 1
        scanPassComplete = false
        statusMessage = "اقلب المجسم إن كان مناسبًا ثم واصل الجولة \(passNumber)."
    }

    func finishCapture() {
        guard let session = captureSession, phase == .capturing else { return }
        session.finish()
        handleState(session.state)
        statusMessage = "جاري إنهاء جلسة Object Capture وحفظ البيانات…"
    }

    func pauseCapture() {
        captureSession?.pause()
    }

    func resumeCapture() {
        captureSession?.resume()
    }

    func cancelAndReset() {
        cleanup(removeWorkingFiles: phase != .completed)
        phase = .idle
        cameraReady = false
        targetSelected = false
        targetCentered = false
        shotCount = 0
        maximumShotCount = 0
        passNumber = 1
        scanPassComplete = false
        completedPasses = 0
        captureTrackingState = "—"
        reconstructionProgress = 0
        invalidSampleCount = 0
        skippedSampleCount = 0
        currentDistanceMeters = 0
        trackingState = "متوقف"
        feedbackMessage = nil
        modelURL = nil
        sessionFolderURL = nil
        statusMessage = "افتح الكاميرا، المس المجسم، ثم وجّه الهدف إلى منتصف الإطار قبل اكتشاف Apple."
        errorMessage = nil
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Preselection AR session

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard phase == .aiming else { return }
        if !cameraReady {
            cameraReady = true
            statusMessage = "الكاميرا جاهزة. المس المجسم المطلوب."
        }
        if let arView, targetWorldPoint != nil {
            updateTargetGuidance(frame: frame, arView: arView)
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal: trackingState = "طبيعي"
        case .notAvailable: trackingState = "غير متاح"
        case .limited(let reason):
            switch reason {
            case .initializing: trackingState = "تهيئة"
            case .excessiveMotion: trackingState = "حركة سريعة"
            case .insufficientFeatures: trackingState = "تفاصيل قليلة"
            case .relocalizing: trackingState = "إعادة تحديد الموقع"
            @unknown default: trackingState = "محدود"
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        guard phase == .aiming else { return }
        phase = .failed
        errorMessage = error.localizedDescription
        statusMessage = "فشلت جلسة AR أثناء اختيار الهدف."
    }

    private func startPreselectionSession() {
        guard phase == .aiming, let arView else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }
        if options.showPreselectionMesh,
           ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        preselectionRunning = true
        cameraReady = false
    }

    private func updateTargetGuidance(frame: ARFrame, arView: ARView) {
        guard let target = targetWorldPoint, arView.bounds.width > 0, arView.bounds.height > 0 else { return }
        let orientation = arView.window?.windowScene?.interfaceOrientation ?? .portrait
        let projected = frame.camera.projectPoint(target, orientation: orientation, viewportSize: arView.bounds.size)
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        let dx = projected.x - center.x
        let dy = projected.y - center.y
        let offset = hypot(dx, dy)
        let threshold = min(arView.bounds.width, arView.bounds.height) * 0.12

        let cameraPosition = SIMD3<Float>(
            frame.camera.transform.columns.3.x,
            frame.camera.transform.columns.3.y,
            frame.camera.transform.columns.3.z
        )
        currentDistanceMeters = simd_distance(cameraPosition, target)
        targetCentered = offset <= threshold
        if targetCentered {
            statusMessage = "الهدف في المنتصف. اضغط اعتماد الهدف لبدء اكتشاف Apple وحدود المجسم."
        } else {
            statusMessage = "تم تحديد الهدف. حرّك الهاتف حتى تصبح العلامة السماوية قرب منتصف الإطار."
        }
    }

    // MARK: - Official Object Capture

    private func prepareOfficialSession() {
        options = Color3DScanSettings.appleObjectOptions
        do {
            let storage = LiDARLabStorage.shared
            try storage.ensureDirectories()

            let finalRoot = storage.capturesURL
                .appendingPathComponent("Color3D", isDirectory: true)
                .appendingPathComponent("Objects", isDirectory: true)
            try fileManager.createDirectory(at: finalRoot, withIntermediateDirectories: true)
            let uniqueName = storage.timestampedName(prefix: "ObjectScan") + "-" + String(UUID().uuidString.prefix(8))
            let finalFolder = finalRoot.appendingPathComponent(uniqueName, isDirectory: true)

            let cacheRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("3ELiDAR-ObjectCaptureWork", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let images = cacheRoot.appendingPathComponent("Images", isDirectory: true)
            let checkpoints = cacheRoot.appendingPathComponent("Checkpoints", isDirectory: true)
            let modelFolder = cacheRoot.appendingPathComponent("Model", isDirectory: true)
            try fileManager.createDirectory(at: images, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: checkpoints, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: modelFolder, withIntermediateDirectories: true)

            let session = ObjectCaptureSession()
            var configuration = ObjectCaptureSession.Configuration()
            configuration.checkpointDirectory = checkpoints
            configuration.isOverCaptureEnabled = options.overCapture
            if #available(iOS 18.0, *) {
                session.isAutoCaptureEnabled = options.autoCapture
                session.shouldPlayHaptics = options.haptics
            }

            workFolderURL = cacheRoot
            imagesURL = images
            checkpointsURL = checkpoints
            localModelURL = modelFolder.appendingPathComponent("model.usdz")
            finalFolderURL = finalFolder
            sessionFolderURL = finalFolder
            captureSession = session
            shotCount = 0
            maximumShotCount = 0
            passNumber = 1
            scanPassComplete = false
            completedPasses = 0
            captureTrackingState = Self.describe(tracking: session.cameraTracking)
            feedbackMessage = nil
            reconstructionProgress = 0
            invalidSampleCount = 0
            skippedSampleCount = 0
            phase = .preparing
            statusMessage = "جاري تشغيل Object Capture الرسمي…"

            attachListeners(to: session)
            session.start(imagesDirectory: images, configuration: configuration)
            handleState(session.state)
            shotCount = session.numberOfShotsTaken
            maximumShotCount = session.maximumNumberOfInputImages
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
            statusMessage = "تعذر بدء Object Capture."
        }
    }

    private func attachListeners(to session: ObjectCaptureSession) {
        detachListeners()

        listenerTasks.append(Task { [weak self, weak session] in
            guard let self, let session else { return }
            for await state in session.stateUpdates {
                guard !Task.isCancelled else { return }
                self.handleState(state)
            }
        })

        listenerTasks.append(Task { [weak self, weak session] in
            guard let self, let session else { return }
            for await count in session.numberOfShotsTakenUpdates {
                guard !Task.isCancelled else { return }
                self.shotCount = count
            }
        })

        listenerTasks.append(Task { [weak self, weak session] in
            guard let self, let session else { return }
            for await completed in session.userCompletedScanPassUpdates {
                guard !Task.isCancelled else { return }
                if completed && !self.scanPassComplete {
                    self.completedPasses += 1
                }
                self.scanPassComplete = completed
                if completed {
                    self.statusMessage = "اكتملت الجولة \(self.passNumber). راجع Point Cloud الفعلي ثم ابدأ جولة جديدة أو أنهِ المسح."
                }
            }
        })

        listenerTasks.append(Task { [weak self, weak session] in
            guard let self, let session else { return }
            for await tracking in session.cameraTrackingUpdates {
                guard !Task.isCancelled else { return }
                self.captureTrackingState = Self.describe(tracking: tracking)
            }
        })

        listenerTasks.append(Task { [weak self, weak session] in
            guard let self, let session else { return }
            for await feedback in session.feedbackUpdates {
                guard !Task.isCancelled else { return }
                self.feedbackMessage = Self.describe(feedback: feedback)
            }
        })
    }

    private func detachListeners() {
        listenerTasks.forEach { $0.cancel() }
        listenerTasks.removeAll()
    }

    private func handleState(_ state: ObjectCaptureSession.CaptureState) {
        switch state {
        case .initializing:
            phase = .preparing
            statusMessage = "جاري تهيئة كاميرا Object Capture…"
        case .ready:
            phase = .readyForDetection
            statusMessage = "المجسم يجب أن يكون في منتصف الإطار. اضغط بدء التعرف الرسمي."
        case .detecting:
            phase = .detecting
            statusMessage = "راجع Bounding Box الذي رسمته Apple وعدّله حتى يحيط بالمجسم فقط."
        case .capturing:
            phase = .capturing
            captureTrackingState = captureSession.map { Self.describe(tracking: $0.cameraTracking) } ?? captureTrackingState
            statusMessage = "لف حول المجسم ببطء واتبع Capture Dial والـPoint Cloud. لا تعتمد على عدد الصور وحده."
        case .finishing:
            phase = .finishing
            statusMessage = "جاري إنهاء الالتقاط وحفظ الصور…"
        case .completed:
            phase = .reconstructing
            statusMessage = "اكتمل الالتقاط. جاري بناء USDZ…"
            detachListeners()
            captureSession = nil
            startReconstruction()
        case .failed(let error):
            phase = .failed
            errorMessage = error.localizedDescription
            statusMessage = "فشل Object Capture: \(error.localizedDescription)"
        @unknown default:
            statusMessage = "تغيّرت حالة Object Capture."
        }
    }

    private func startReconstruction() {
        reconstructionTask?.cancel()
        guard let imagesURL, let localModelURL else {
            phase = .failed
            errorMessage = "صور Object Capture غير متاحة لإعادة البناء."
            return
        }
        try? fileManager.removeItem(at: localModelURL)
        let finalFolder = finalFolderURL
        let workingFolder = workFolderURL
        let options = options

        reconstructionTask = Task { [weak self] in
            guard let self else { return }
            do {
                var configuration = PhotogrammetrySession.Configuration()
                configuration.checkpointDirectory = self.checkpointsURL
                configuration.sampleOrdering = .sequential
                configuration.featureSensitivity = options.highFeatureSensitivity ? .high : .normal
                configuration.isObjectMaskingEnabled = options.objectMasking

                let session = try PhotogrammetrySession(input: imagesURL, configuration: configuration)
                self.photogrammetrySession = session
                let request = PhotogrammetrySession.Request.modelFile(url: localModelURL, detail: .reduced)
                try session.process(requests: [request])

                for try await output in session.outputs {
                    guard !Task.isCancelled else {
                        session.cancel()
                        return
                    }
                    switch output {
                    case .requestProgress(_, fractionComplete: let fraction):
                        self.reconstructionProgress = fraction
                        self.statusMessage = "بناء النموذج… \(Int(fraction * 100))%"
                    case .requestError(_, let error):
                        self.phase = .failed
                        self.errorMessage = error.localizedDescription
                        self.statusMessage = "تعذر بناء النموذج من صور Object Capture."
                    case .invalidSample(_, _):
                        self.invalidSampleCount += 1
                    case .skippedSample(_):
                        self.skippedSampleCount += 1
                    case .automaticDownsampling:
                        self.statusMessage = "RealityKit خفّض دقة بعض صور الإدخال تلقائيًا بسبب حدود ذاكرة الجهاز."
                    case .processingComplete:
                        guard self.fileManager.fileExists(atPath: localModelURL.path), let finalFolder else {
                            if self.phase != .failed {
                                self.phase = .failed
                                self.errorMessage = "انتهت المعالجة بدون ملف USDZ."
                            }
                            continue
                        }
                        try self.fileManager.createDirectory(at: finalFolder, withIntermediateDirectories: true)
                        let modelFolder = finalFolder.appendingPathComponent("Model", isDirectory: true)
                        try self.fileManager.createDirectory(at: modelFolder, withIntermediateDirectories: true)
                        let published = modelFolder.appendingPathComponent("model.usdz")
                        try? self.fileManager.removeItem(at: published)
                        try self.fileManager.copyItem(at: localModelURL, to: published)

                        if options.keepSourceImages {
                            let sourceFolder = finalFolder.appendingPathComponent("Images", isDirectory: true)
                            try? self.fileManager.removeItem(at: sourceFolder)
                            try self.fileManager.copyItem(at: imagesURL, to: sourceFolder)
                        }

                        self.modelURL = published
                        self.reconstructionProgress = 1
                        self.phase = .completed
                        self.statusMessage = "اكتمل نموذج USDZ الملوّن."
                        if let workingFolder {
                            try? self.fileManager.removeItem(at: workingFolder)
                            self.workFolderURL = nil
                        }
                    default:
                        break
                    }
                }
            } catch {
                self.phase = .failed
                self.errorMessage = error.localizedDescription
                self.statusMessage = "فشلت إعادة بناء المجسم."
            }
            self.photogrammetrySession = nil
        }
    }

    private func cleanup(removeWorkingFiles: Bool) {
        detachListeners()
        reconstructionTask?.cancel()
        reconstructionTask = nil
        photogrammetrySession?.cancel()
        photogrammetrySession = nil
        captureSession?.cancel()
        captureSession = nil
        arView?.session.pause()
        preselectionRunning = false
        clearSelectionMarker()

        if removeWorkingFiles, let workFolderURL {
            try? fileManager.removeItem(at: workFolderURL)
        }
        workFolderURL = nil
        imagesURL = nil
        checkpointsURL = nil
        localModelURL = nil
        finalFolderURL = nil
        targetWorldPoint = nil
    }

    private static func describe(tracking: ObjectCaptureSession.Tracking) -> String {
        switch tracking {
        case .normal:
            return "تتبع ممتاز"
        case .notAvailable:
            return "التتبع غير جاهز"
        case .limited(reason: let reason):
            switch reason {
            case .initializing:
                return "تهيئة التتبع"
            case .excessiveMotion:
                return "الحركة سريعة"
            case .insufficientFeatures:
                return "تفاصيل مرئية قليلة"
            case .relocalizing:
                return "إعادة تحديد الموقع"
            @unknown default:
                return "تتبع محدود"
            }
        @unknown default:
            return "حالة تتبع غير معروفة"
        }
    }

    private static func describe(feedback: Set<ObjectCaptureSession.Feedback>) -> String? {
        if feedback.contains(.environmentTooDark) { return "الإضاءة مظلمة جدًا؛ زد الإضاءة." }
        if feedback.contains(.environmentLowLight) { return "الإضاءة منخفضة وقد تقل الجودة." }
        if feedback.contains(.movingTooFast) { return "تتحرك بسرعة؛ تحرك أبطأ." }
        if #available(iOS 17.4, *), feedback.contains(.objectNotDetected) {
            return "لم تتعرف Apple على المجسم جيدًا؛ عدّل الصندوق اليدوي أو أعد الاكتشاف."
        }
        if feedback.contains(.objectNotFlippable) { return "يفضل عدم قلب هذا المجسم؛ استخدم جولات إضافية من ارتفاعات مختلفة." }
        if feedback.contains(.objectTooClose) { return "أنت قريب جدًا من المجسم." }
        if feedback.contains(.objectTooFar) { return "أنت بعيد جدًا عن المجسم." }
        if feedback.contains(.outOfFieldOfView) { return "جزء من Bounding Box خارج مجال الكاميرا." }
        if feedback.contains(.overCapturing) { return "تم تجاوز عدد الصور المفيد لإعادة البناء على الهاتف."
        }
        return nil
    }

    // MARK: - Target selection helpers

    private func depthWorldPoint(at screenPoint: CGPoint, frame: ARFrame, arView: ARView) -> SIMD3<Float>? {
        let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth
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
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let x = min(max(Int(normalizedImage.x * CGFloat(width)), 0), width - 1)
        let y = min(max(Int(normalizedImage.y * CGFloat(height)), 0), height - 1)
        guard let depth = medianDepth(depthMap, x: x, y: y), depth > 0.08, depth < 8 else { return nil }

        let resolution = frame.camera.imageResolution
        let u = Float(normalizedImage.x) * Float(resolution.width)
        let v = Float(normalizedImage.y) * Float(resolution.height)
        let intrinsics = frame.camera.intrinsics
        let fx = intrinsics.columns.0.x
        let fy = intrinsics.columns.1.y
        let cx = intrinsics.columns.2.x
        let cy = intrinsics.columns.2.y
        guard fx > 0, fy > 0 else { return nil }

        let cameraPoint = SIMD4<Float>((u - cx) / fx * depth, -(v - cy) / fy * depth, -depth, 1)
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
        for yy in max(0, y - 1)...min(height - 1, y + 1) {
            for xx in max(0, x - 1)...min(width - 1, x + 1) {
                let value = values[yy * stride + xx]
                if value.isFinite, value > 0.05, value < 10 { samples.append(value) }
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
        let anchor = AnchorEntity(world: point)
        let material = SimpleMaterial(color: UIColor.systemCyan, isMetallic: false)
        let marker = ModelEntity(mesh: .generateSphere(radius: 0.025), materials: [material])
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
}

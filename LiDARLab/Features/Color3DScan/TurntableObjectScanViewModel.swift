import AVFoundation
import Combine
import Foundation
import RealityKit
import UIKit
import Vision

final class TurntableObjectScanViewModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Phase: Equatable {
        case idle
        case preparingCamera
        case ready
        case capturing
        case readyToReconstruct
        case reconstructing
        case completed
        case failed

        var title: String {
            switch self {
            case .idle: "جاهز"
            case .preparingCamera: "تهيئة الكاميرا"
            case .ready: "ثبّت الكاميرا والمجسم"
            case .capturing: "التقاط دورة Turntable"
            case .readyToReconstruct: "الدورة اكتملت"
            case .reconstructing: "بناء النموذج"
            case .completed: "اكتمل النموذج"
            case .failed: "حدث خطأ"
            }
        }
    }

    let captureSession = AVCaptureSession()

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var capturedImageCount = 0
    @Published private(set) var passImageCount = 0
    @Published private(set) var passNumber = 1
    @Published private(set) var targetImagesPerPass = 48
    @Published private(set) var reconstructionProgress: Double = 0
    @Published private(set) var invalidSampleCount = 0
    @Published private(set) var skippedSampleCount = 0
    @Published private(set) var modelURL: URL?
    @Published private(set) var sessionFolderURL: URL?
    @Published private(set) var statusMessage = "ثبّت الآيفون على حامل ثم لف المجسم بدل تحريك الكاميرا."
    @Published private(set) var cameraReady = false
    @Published private(set) var cameraLocked = false
    @Published private(set) var smartCaptureState = "—"
    @Published private(set) var visualChangeScore: Float = 0
    @Published private(set) var skippedDuplicateCount = 0
    @Published var errorMessage: String?

    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.essam.3E.LiDARLab.turntable.session", qos: .userInitiated)
    private let fileQueue = DispatchQueue(label: "com.essam.3E.LiDARLab.turntable.files", qos: .utility)
    private let analysisQueue = DispatchQueue(label: "com.essam.3E.LiDARLab.turntable.analysis", qos: .userInitiated)
    private let fileManager = FileManager.default
    private let featureLock = NSLock()

    private var cameraDevice: AVCaptureDevice?
    private var captureInFlight = false
    private var lastAnalysisTimestamp: TimeInterval = -100
    private var lastAcceptedCaptureTimestamp: TimeInterval = -100
    private var analysisPausedUntil: TimeInterval = -100
    private var previousFeaturePrint: VNFeaturePrintObservation?
    private var acceptedFeaturePrints: [VNFeaturePrintObservation] = []
    private var pendingCaptureFeaturePrint: VNFeaturePrintObservation?
    private var latestFeaturePrint: VNFeaturePrintObservation?
    private var pendingFinish = false
    private var workFolderURL: URL?
    private var imagesURL: URL?
    private var localModelURL: URL?
    private var finalFolderURL: URL?
    private var photogrammetrySession: PhotogrammetrySession?
    private var reconstructionTask: Task<Void, Never>?
    private var options = Color3DScanSettings.turntableOptions

    var isSupported: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
            && PhotogrammetrySession.isSupported
    }

    var captureModeTitle: String { options.captureMode.title }

    var isSmartAutomatic: Bool { options.captureMode == .smartAutomatic }

    var progress: Double {
        guard targetImagesPerPass > 0 else { return 0 }
        return min(Double(passImageCount) / Double(targetImagesPerPass), 1)
    }

    var canFinishCapture: Bool {
        capturedImageCount >= max(8, options.minimumImagesBeforeFinish)
    }

    var estimatedPassDurationSeconds: Int {
        max(1, Int((Double(targetImagesPerPass) * options.captureInterval).rounded()))
    }

    func prepare() {
        guard isSupported else {
            phase = .failed
            errorMessage = "هذا الجهاز لا يدعم كاميرا خلفية مناسبة أو Photogrammetry على الجهاز."
            return
        }

        cleanup(removeWorkingFiles: true)
        options = Color3DScanSettings.turntableOptions
        targetImagesPerPass = options.imagesPerPass
        capturedImageCount = 0
        passImageCount = 0
        passNumber = 1
        reconstructionProgress = 0
        invalidSampleCount = 0
        skippedSampleCount = 0
        modelURL = nil
        sessionFolderURL = nil
        cameraLocked = false
        cameraReady = false
        smartCaptureState = options.captureMode == .smartAutomatic ? "بانتظار ثبات الكاميرا" : "التقاط يدوي"
        visualChangeScore = 0
        skippedDuplicateCount = 0
        featureLock.lock()
        previousFeaturePrint = nil
        acceptedFeaturePrints.removeAll(keepingCapacity: true)
        pendingCaptureFeaturePrint = nil
        latestFeaturePrint = nil
        featureLock.unlock()
        phase = .preparingCamera
        statusMessage = "جاري تشغيل الكاميرا الخلفية…"

        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async {
                    self.phase = .failed
                    self.errorMessage = "يلزم السماح للتطبيق باستخدام الكاميرا."
                }
                return
            }
            self.configureAndStartCamera()
        }
    }

    func startPass() {
        guard phase == .ready || phase == .readyToReconstruct else { return }
        guard cameraReady else { return }

        if phase == .readyToReconstruct {
            passNumber += 1
            passImageCount = 0
        }

        lockCameraSettings()
        pendingFinish = false
        featureLock.lock()
        previousFeaturePrint = nil
        pendingCaptureFeaturePrint = nil
        latestFeaturePrint = nil
        featureLock.unlock()
        phase = .capturing
        lastAnalysisTimestamp = -100
        lastAcceptedCaptureTimestamp = -100
        analysisPausedUntil = -100
        smartCaptureState = options.captureMode == .smartAutomatic
            ? "لف المجسم ثم ثبته لحظة؛ سيتم التقاط المناظر الجديدة فقط"
            : "الوضع اليدوي: اضغط صورة الآن لكل زاوية تريدها"
        statusMessage = options.captureMode == .smartAutomatic
            ? "لف المجسم ببطء. التلقائي الذكي ينتظر زاوية جديدة ثم هدوء الحركة قبل التصوير."
            : "لف المجسم للزاوية المطلوبة ثم اضغط صورة الآن. لا يوجد التقاط تلقائي في هذا الوضع."
    }

    func notifyLightingChanged() {
        analysisPausedUntil = Date().timeIntervalSinceReferenceDate + 1.25
        featureLock.lock()
        previousFeaturePrint = nil
        latestFeaturePrint = nil
        featureLock.unlock()
        smartCaptureState = "تغيّرت الإضاءة — انتظار استقرار الكاميرا"

        guard phase == .capturing, let device = cameraDevice else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try device.lockForConfiguration()
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.cameraLocked = false }
                self.sessionQueue.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                    self?.lockCameraSettings()
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "تغيّرت الإضاءة. انتظر لحظة قبل متابعة الالتقاط."
                }
            }
        }
    }

    func captureManualPhoto() {
        guard phase == .capturing else { return }
        featureLock.lock()
        let feature = latestFeaturePrint
        featureLock.unlock()
        requestPhotoCapture(featurePrint: feature)
    }

    func stopPass() {
        guard phase == .capturing else { return }
        if captureInFlight {
            pendingFinish = true
            statusMessage = "انتظار حفظ آخر صورة…"
        } else {
            finishCurrentPass()
        }
    }

    func reconstructNow() {
        guard phase == .readyToReconstruct || (phase == .capturing && canFinishCapture) else { return }
        if captureInFlight {
            pendingFinish = true
            statusMessage = "انتظار حفظ آخر صورة قبل البناء…"
            return
        }
        beginReconstruction()
    }

    func cancelAndReset() {
        cleanup(removeWorkingFiles: true)
        phase = .idle
        capturedImageCount = 0
        passImageCount = 0
        passNumber = 1
        reconstructionProgress = 0
        invalidSampleCount = 0
        skippedSampleCount = 0
        modelURL = nil
        sessionFolderURL = nil
        cameraLocked = false
        cameraReady = false
        statusMessage = "ثبّت الآيفون على حامل ثم لف المجسم بدل تحريك الكاميرا."
        errorMessage = nil
    }

    func clearError() {
        errorMessage = nil
    }

    private func configureAndStartCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.createWorkingFolders()
                self.captureSession.beginConfiguration()
                self.captureSession.sessionPreset = .photo

                for input in self.captureSession.inputs {
                    self.captureSession.removeInput(input)
                }
                for output in self.captureSession.outputs {
                    self.captureSession.removeOutput(output)
                }

                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    throw TurntableScanError.cameraUnavailable
                }
                let input = try AVCaptureDeviceInput(device: device)
                guard self.captureSession.canAddInput(input) else {
                    throw TurntableScanError.cameraUnavailable
                }
                self.captureSession.addInput(input)

                guard self.captureSession.canAddOutput(self.photoOutput) else {
                    throw TurntableScanError.photoOutputUnavailable
                }
                self.captureSession.addOutput(self.photoOutput)
                self.photoOutput.maxPhotoQualityPrioritization = .quality

                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                ]
                self.videoOutput.setSampleBufferDelegate(self, queue: self.analysisQueue)
                guard self.captureSession.canAddOutput(self.videoOutput) else {
                    throw TurntableScanError.videoOutputUnavailable
                }
                self.captureSession.addOutput(self.videoOutput)

                self.cameraDevice = device
                self.captureSession.commitConfiguration()
                self.captureSession.startRunning()

                DispatchQueue.main.async {
                    self.cameraReady = true
                    self.phase = .ready
                    self.statusMessage = "ثبّت الهاتف، اجعل المجسم يملأ أغلب الإطار بدون قص، ثم اضغط بدء الدورة."
                }
            } catch {
                self.captureSession.commitConfiguration()
                DispatchQueue.main.async {
                    self.phase = .failed
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = "تعذر تجهيز كاميرا Turntable."
                }
            }
        }
    }

    private func createWorkingFolders() throws {
        let storage = LiDARLabStorage.shared
        try storage.ensureDirectories()

        let finalRoot = storage.capturesURL
            .appendingPathComponent("Color3D", isDirectory: true)
            .appendingPathComponent("Objects", isDirectory: true)
        try fileManager.createDirectory(at: finalRoot, withIntermediateDirectories: true)
        let uniqueName = storage.timestampedName(prefix: "TurntableScan") + "-" + String(UUID().uuidString.prefix(8))
        let finalFolder = finalRoot.appendingPathComponent(uniqueName, isDirectory: true)

        let cacheRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("3ELiDAR-TurntableWork", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let images = cacheRoot.appendingPathComponent("Images", isDirectory: true)
        let modelFolder = cacheRoot.appendingPathComponent("Model", isDirectory: true)
        try fileManager.createDirectory(at: images, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: modelFolder, withIntermediateDirectories: true)

        workFolderURL = cacheRoot
        imagesURL = images
        localModelURL = modelFolder.appendingPathComponent("model.usdz")
        finalFolderURL = finalFolder
        sessionFolderURL = finalFolder
    }

    private func lockCameraSettings() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.cameraDevice else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.locked) {
                    device.focusMode = .locked
                }
                if device.isExposureModeSupported(.locked) {
                    device.exposureMode = .locked
                }
                if device.isWhiteBalanceModeSupported(.locked) {
                    device.whiteBalanceMode = .locked
                }
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.cameraLocked = true }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "تعذر قفل بعض إعدادات الكاميرا؛ استمر لكن تجنب تغيّر الإضاءة."
                }
            }
        }
    }

    private func requestPhotoCapture(featurePrint: VNFeaturePrintObservation? = nil) {
        guard !captureInFlight else { return }
        captureInFlight = true
        featureLock.lock()
        pendingCaptureFeaturePrint = featurePrint
        featureLock.unlock()

        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }
            settings.photoQualityPrioritization = .quality
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            DispatchQueue.main.async {
                self.captureInFlight = false
                self.statusMessage = "تعذر حفظ صورة: \(error.localizedDescription)"
            }
            return
        }
        guard let data = photo.fileDataRepresentation(), let imagesURL else {
            DispatchQueue.main.async {
                self.captureInFlight = false
                self.statusMessage = "تعذر استخراج بيانات الصورة."
            }
            return
        }

        let nextIndex = capturedImageCount + 1
        let url = imagesURL.appendingPathComponent(String(format: "frame-%04d.jpg", nextIndex))

        fileQueue.async { [weak self] in
            guard let self else { return }
            do {
                try data.write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    self.capturedImageCount += 1
                    self.passImageCount += 1
                    self.captureInFlight = false
                    self.featureLock.lock()
                    if let accepted = self.pendingCaptureFeaturePrint {
                        self.acceptedFeaturePrints.append(accepted)
                    }
                    self.pendingCaptureFeaturePrint = nil
                    self.featureLock.unlock()
                    self.lastAcceptedCaptureTimestamp = Date().timeIntervalSinceReferenceDate
                    self.smartCaptureState = self.options.captureMode == .smartAutomatic
                        ? "تم التقاط منظر جديد — حرّك المجسم للزاوية التالية"
                        : "تم التقاط الصورة يدويًا"
                    self.statusMessage = "تم حفظ \(self.passImageCount) صورة في الجولة الحالية."

                    if self.options.captureMode == .smartAutomatic, self.passImageCount >= self.targetImagesPerPass {
                        self.stopPass()
                    } else if self.pendingFinish {
                        self.pendingFinish = false
                        self.finishCurrentPass()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.captureInFlight = false
                    self.statusMessage = "فشل حفظ الصورة: \(error.localizedDescription)"
                }
            }
        }
    }

    private func finishCurrentPass() {
        phase = .readyToReconstruct
        statusMessage = "اكتملت الجولة \(passNumber) بعد \(passImageCount) صورة. يمكنك بناء النموذج أو وضع المجسم على جانب آخر وبدء جولة إضافية."
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard output === videoOutput, phase == .capturing else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard timestamp.isFinite, timestamp - lastAnalysisTimestamp >= 0.18 else { return }
        lastAnalysisTimestamp = timestamp

        guard let feature = makeFeaturePrint(pixelBuffer: pixelBuffer) else { return }

        featureLock.lock()
        let previous = previousFeaturePrint
        let acceptedSnapshot = acceptedFeaturePrints
        latestFeaturePrint = feature
        previousFeaturePrint = feature
        featureLock.unlock()

        var motionDistance: Float = 0
        if let previous {
            try? previous.computeDistance(&motionDistance, to: feature)
        }

        var nearestAccepted = Float.greatestFiniteMagnitude
        for accepted in acceptedSnapshot {
            var distance: Float = 0
            if (try? accepted.computeDistance(&distance, to: feature)) != nil {
                nearestAccepted = min(nearestAccepted, distance)
            }
        }
        if acceptedSnapshot.isEmpty { nearestAccepted = Float.greatestFiniteMagnitude }

        DispatchQueue.main.async {
            self.visualChangeScore = nearestAccepted.isFinite ? nearestAccepted : 0
        }

        guard options.captureMode == .smartAutomatic else {
            DispatchQueue.main.async { self.smartCaptureState = "يدوي — اضغط صورة الآن عند الزاوية المطلوبة" }
            return
        }
        guard !captureInFlight else { return }

        let now = Date().timeIntervalSinceReferenceDate
        guard now >= analysisPausedUntil else { return }
        let elapsed = now - lastAcceptedCaptureTimestamp
        guard elapsed >= options.captureInterval else { return }

        if !acceptedSnapshot.isEmpty, nearestAccepted < options.noveltyThreshold {
            DispatchQueue.main.async {
                self.smartCaptureState = "منظر قريب من لقطة سابقة — واصل تدوير المجسم"
            }
            return
        }

        if motionDistance > options.stabilityThreshold {
            DispatchQueue.main.async {
                self.smartCaptureState = "المجسم يتحرك — ثبته لحظة عند الزاوية الجديدة"
            }
            return
        }

        DispatchQueue.main.async {
            guard self.phase == .capturing, !self.captureInFlight else { return }
            self.smartCaptureState = "زاوية جديدة وثابتة — التقاط"
            self.requestPhotoCapture(featurePrint: feature)
        }
    }

    private func makeFeaturePrint(pixelBuffer: CVPixelBuffer) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision1
        request.imageCropAndScaleOption = .scaleFill
        request.regionOfInterest = CGRect(x: 0.12, y: 0.10, width: 0.76, height: 0.80)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first
        } catch {
            return nil
        }
    }

    private func beginReconstruction() {
        guard let imagesURL, let localModelURL else {
            phase = .failed
            errorMessage = "صور Turntable غير متاحة لإعادة البناء."
            return
        }
        guard capturedImageCount >= max(8, options.minimumImagesBeforeFinish) else {
            statusMessage = "التقط صورًا أكثر قبل البناء."
            return
        }

        phase = .reconstructing
        reconstructionProgress = 0
        statusMessage = "جاري بناء USDZ من \(capturedImageCount) صورة…"
        try? fileManager.removeItem(at: localModelURL)

        let finalFolder = finalFolderURL
        let workFolder = workFolderURL
        let keepSourceImages = options.keepSourceImages
        let highFeatureSensitivity = options.highFeatureSensitivity
        let objectMasking = options.objectMasking

        reconstructionTask?.cancel()
        reconstructionTask = Task { [weak self] in
            guard let self else { return }
            do {
                var configuration = PhotogrammetrySession.Configuration()
                configuration.sampleOrdering = .sequential
                configuration.featureSensitivity = highFeatureSensitivity ? .high : .normal
                configuration.isObjectMaskingEnabled = objectMasking

                let session = try PhotogrammetrySession(input: imagesURL, configuration: configuration)
                self.photogrammetrySession = session
                let request = PhotogrammetrySession.Request.modelFile(url: localModelURL, detail: .reduced)
                try session.process(requests: [request])

                for try await output in session.outputs {
                    guard !Task.isCancelled else {
                        session.cancel()
                        return
                    }
                    await MainActor.run {
                        switch output {
                        case .requestProgress(_, fractionComplete: let fraction):
                            self.reconstructionProgress = fraction
                            self.statusMessage = "بناء النموذج… \(Int(fraction * 100))%"
                        case .requestError(_, let error):
                            self.phase = .failed
                            self.errorMessage = error.localizedDescription
                        case .invalidSample(_, _):
                            self.invalidSampleCount += 1
                        case .skippedSample(_):
                            self.skippedSampleCount += 1
                        default:
                            break
                        }
                    }

                    if case .processingComplete = output {
                        guard self.fileManager.fileExists(atPath: localModelURL.path), let finalFolder else {
                            await MainActor.run {
                                self.phase = .failed
                                self.errorMessage = "انتهت المعالجة بدون ملف USDZ."
                            }
                            continue
                        }
                        try self.fileManager.createDirectory(at: finalFolder, withIntermediateDirectories: true)
                        let finalModelFolder = finalFolder.appendingPathComponent("Model", isDirectory: true)
                        try self.fileManager.createDirectory(at: finalModelFolder, withIntermediateDirectories: true)
                        let published = finalModelFolder.appendingPathComponent("model.usdz")
                        try? self.fileManager.removeItem(at: published)
                        try self.fileManager.copyItem(at: localModelURL, to: published)

                        if keepSourceImages {
                            let finalImages = finalFolder.appendingPathComponent("Images", isDirectory: true)
                            try? self.fileManager.removeItem(at: finalImages)
                            try self.fileManager.copyItem(at: imagesURL, to: finalImages)
                        }

                        await MainActor.run {
                            self.modelURL = published
                            self.reconstructionProgress = 1
                            self.phase = .completed
                            self.statusMessage = "اكتمل نموذج Turntable الملوّن."
                        }
                        if let workFolder {
                            try? self.fileManager.removeItem(at: workFolder)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.phase = .failed
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = "فشلت إعادة بناء نموذج Turntable."
                }
            }
            self.photogrammetrySession = nil
        }
    }

    private func cleanup(removeWorkingFiles: Bool) {
        featureLock.lock()
        previousFeaturePrint = nil
        acceptedFeaturePrints.removeAll(keepingCapacity: false)
        pendingCaptureFeaturePrint = nil
        latestFeaturePrint = nil
        featureLock.unlock()
        pendingFinish = false
        reconstructionTask?.cancel()
        reconstructionTask = nil
        photogrammetrySession?.cancel()
        photogrammetrySession = nil

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }

        if removeWorkingFiles, let workFolderURL {
            try? fileManager.removeItem(at: workFolderURL)
        }
        workFolderURL = nil
        imagesURL = nil
        localModelURL = nil
        finalFolderURL = nil
    }
}

private enum TurntableScanError: LocalizedError {
    case cameraUnavailable
    case photoOutputUnavailable
    case videoOutputUnavailable

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "تعذر تشغيل الكاميرا الخلفية."
        case .photoOutputUnavailable:
            return "تعذر تشغيل التقاط الصور عالية الجودة."
        case .videoOutputUnavailable:
            return "تعذر تشغيل تحليل الفيديو الذكي للـTurntable."
        }
    }
}

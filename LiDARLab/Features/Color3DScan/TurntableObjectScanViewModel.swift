import AVFoundation
import Combine
import Foundation
import RealityKit
import UIKit

final class TurntableObjectScanViewModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
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
    @Published var errorMessage: String?

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.essam.3E.LiDARLab.turntable.session", qos: .userInitiated)
    private let fileQueue = DispatchQueue(label: "com.essam.3E.LiDARLab.turntable.files", qos: .utility)
    private let fileManager = FileManager.default

    private var cameraDevice: AVCaptureDevice?
    private var timer: DispatchSourceTimer?
    private var captureInFlight = false
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
        phase = .capturing
        statusMessage = "لف المجسم ببطء دورة كاملة بدون تحريك الهاتف. حافظ على سرعة ثابتة وخلفية سادة."

        if options.autoCapture {
            startAutoCaptureTimer()
        }
    }

    func captureManualPhoto() {
        guard phase == .capturing else { return }
        requestPhotoCapture()
    }

    func stopPass() {
        guard phase == .capturing else { return }
        stopAutoCaptureTimer()
        if captureInFlight {
            pendingFinish = true
            statusMessage = "انتظار حفظ آخر صورة…"
        } else {
            finishCurrentPass()
        }
    }

    func reconstructNow() {
        guard phase == .readyToReconstruct || (phase == .capturing && canFinishCapture) else { return }
        stopAutoCaptureTimer()
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

    private func startAutoCaptureTimer() {
        stopAutoCaptureTimer()
        let timer = DispatchSource.makeTimerSource(queue: sessionQueue)
        timer.schedule(deadline: .now() + 0.9, repeating: options.captureInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.phase == .capturing else { return }
                if self.passImageCount >= self.targetImagesPerPass {
                    self.stopPass()
                } else {
                    self.requestPhotoCapture()
                }
            }
        }
        self.timer = timer
        timer.resume()
    }

    private func stopAutoCaptureTimer() {
        timer?.cancel()
        timer = nil
    }

    private func requestPhotoCapture() {
        guard !captureInFlight else { return }
        captureInFlight = true

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
                    self.statusMessage = "تم التقاط \(self.passImageCount)/\(self.targetImagesPerPass) في الجولة الحالية."

                    if self.passImageCount >= self.targetImagesPerPass {
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
        stopAutoCaptureTimer()
        phase = .readyToReconstruct
        statusMessage = "اكتملت الجولة \(passNumber) بعد \(passImageCount) صورة. يمكنك بناء النموذج أو وضع المجسم على جانب آخر وبدء جولة إضافية."
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

        stopAutoCaptureTimer()
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
        stopAutoCaptureTimer()
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

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "تعذر تشغيل الكاميرا الخلفية."
        case .photoOutputUnavailable:
            return "تعذر تشغيل التقاط الصور عالية الجودة."
        }
    }
}

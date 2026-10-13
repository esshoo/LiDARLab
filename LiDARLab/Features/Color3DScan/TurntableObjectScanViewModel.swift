import AVFoundation
import Combine
import Foundation
import RealityKit
import UIKit

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
    private let signatureLock = NSLock()

    // Lightweight 32x24 luminance signatures. This intentionally replaces the old
    // continuous Vision feature-print pipeline, which was too heavy for a live photo
    // capture session on some phones and could terminate the app under memory pressure.
    private typealias FrameSignature = [UInt8]
    private var previousSignature: FrameSignature?
    private var acceptedSignatures: [FrameSignature] = []
    private var pendingCaptureSignature: FrameSignature?
    private var latestSignature: FrameSignature?

    private enum PendingAction {
        case none
        case finishPass
        case reconstruct
    }

    private var cameraDevice: AVCaptureDevice?
    private var captureInFlight = false
    private var lastAnalysisTimestamp: TimeInterval = -100
    private var lastAcceptedCaptureTimestamp: TimeInterval = -100
    private var analysisPausedUntil: TimeInterval = -100
    private var pendingAction: PendingAction = .none
    private var autoStableFrameCount = 0
    private var autoMovementArmed = false
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

    var canStopPass: Bool {
        phase == .capturing && passImageCount > 0
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
        resetSignatures(keepAccepted: false)
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

    func refreshCaptureOptionsForNextPass() {
        guard phase == .ready || phase == .readyToReconstruct else { return }
        options = Color3DScanSettings.turntableOptions
        targetImagesPerPass = options.imagesPerPass
        smartCaptureState = options.captureMode == .smartAutomatic ? "التقاط تلقائي ذكي" : "التقاط يدوي"
    }

    func startPass() {
        guard phase == .ready, cameraReady else { return }
        refreshCaptureOptionsForNextPass()
        beginCapturePass()
    }

    func startAdditionalPass() {
        guard phase == .readyToReconstruct else { return }

        options = Color3DScanSettings.turntableOptions
        targetImagesPerPass = options.imagesPerPass
        passNumber += 1
        passImageCount = 0
        phase = .preparingCamera
        statusMessage = "إعادة تشغيل الكاميرا للجولة \(passNumber)…"

        videoOutput.setSampleBufferDelegate(self, queue: analysisQueue)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
            DispatchQueue.main.async {
                self.cameraReady = self.captureSession.isRunning
                guard self.cameraReady else {
                    self.phase = .failed
                    self.errorMessage = "تعذر إعادة تشغيل كاميرا Turntable للجولة الإضافية."
                    return
                }
                self.beginCapturePass()
            }
        }
    }

    private func beginCapturePass() {
        guard cameraReady else { return }

        lockCameraSettings()
        pendingAction = .none
        resetSignatures(keepAccepted: true)
        autoStableFrameCount = 0
        autoMovementArmed = false
        phase = .capturing
        lastAnalysisTimestamp = -100
        lastAcceptedCaptureTimestamp = -100
        analysisPausedUntil = Date().timeIntervalSinceReferenceDate + 0.60
        smartCaptureState = options.captureMode == .smartAutomatic
            ? "ثبّت المجسم لحظة لالتقاط الصورة الأولى تلقائيًا"
            : "الوضع اليدوي: اضغط التقاط عند كل زاوية"
        statusMessage = options.captureMode == .smartAutomatic
            ? "سيتم التقاط الصورة الأولى تلقائيًا عند الثبات، ثم كل زاوية جديدة بعد تدوير المجسم."
            : "لف المجسم للزاوية المطلوبة ثم اضغط التقاط صورة."
    }

    func notifyLightingChanged() {
        analysisPausedUntil = Date().timeIntervalSinceReferenceDate + 1.25
        resetSignatures(keepAccepted: true)
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
        signatureLock.lock()
        let signature = latestSignature
        signatureLock.unlock()
        requestPhotoCapture(signature: signature)
    }

    func stopPass() {
        guard canStopPass else {
            statusMessage = "التقط صورة واحدة على الأقل قبل إنهاء الجولة."
            return
        }
        if captureInFlight {
            pendingAction = .finishPass
            statusMessage = "انتظار حفظ آخر صورة…"
        } else {
            finishCurrentPass()
        }
    }

    func reconstructNow() {
        guard phase == .readyToReconstruct, canFinishCapture else { return }
        phase = .reconstructing
        reconstructionProgress = 0
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
        smartCaptureState = "—"
        autoStableFrameCount = 0
        autoMovementArmed = false
        visualChangeScore = 0
        skippedDuplicateCount = 0
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

                for input in self.captureSession.inputs { self.captureSession.removeInput(input) }
                for output in self.captureSession.outputs { self.captureSession.removeOutput(output) }

                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    throw TurntableScanError.cameraUnavailable
                }
                let input = try AVCaptureDeviceInput(device: device)
                guard self.captureSession.canAddInput(input) else { throw TurntableScanError.cameraUnavailable }
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
                    self.statusMessage = "ثبّت الهاتف، اجعل المجسم داخل الإطار، ثم ابدأ الجولة."
                }
            } catch {
                if self.captureSession.isRunning == false {
                    self.captureSession.commitConfiguration()
                }
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
                if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
                if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
                if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.cameraLocked = true }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "تعذر قفل بعض إعدادات الكاميرا؛ تجنب تغيّر الإضاءة أثناء الجولة."
                }
            }
        }
    }

    private func requestPhotoCapture(signature: FrameSignature? = nil) {
        guard !captureInFlight else { return }
        captureInFlight = true
        signatureLock.lock()
        pendingCaptureSignature = signature
        signatureLock.unlock()

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
                if case .reconstruct = self.pendingAction {
                    self.pendingAction = .none
                    self.phase = .readyToReconstruct
                    self.statusMessage = "تعذر حفظ آخر صورة. يمكنك محاولة بناء النموذج مرة أخرى من الصور المحفوظة."
                } else {
                    self.pendingAction = .none
                    self.statusMessage = "تعذر حفظ صورة: \(error.localizedDescription)"
                }
            }
            return
        }
        guard let data = photo.fileDataRepresentation(), let imagesURL else {
            DispatchQueue.main.async {
                self.captureInFlight = false
                if case .reconstruct = self.pendingAction {
                    self.pendingAction = .none
                    self.phase = .readyToReconstruct
                    self.statusMessage = "تعذر استخراج آخر صورة. يمكنك محاولة بناء النموذج مرة أخرى من الصور المحفوظة."
                } else {
                    self.pendingAction = .none
                    self.statusMessage = "تعذر استخراج بيانات الصورة."
                }
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
                    self.signatureLock.lock()
                    if let accepted = self.pendingCaptureSignature {
                        self.acceptedSignatures.append(accepted)
                    }
                    self.pendingCaptureSignature = nil
                    self.signatureLock.unlock()
                    self.lastAcceptedCaptureTimestamp = Date().timeIntervalSinceReferenceDate
                    self.smartCaptureState = self.options.captureMode == .smartAutomatic
                        ? "تم التقاط زاوية جديدة — حرّك المجسم"
                        : "تم التقاط الصورة يدويًا"
                    self.statusMessage = "تم حفظ \(self.passImageCount) صورة في الجولة الحالية."

                    let pendingAction = self.pendingAction
                    self.pendingAction = .none

                    switch pendingAction {
                    case .reconstruct:
                        self.beginReconstruction()
                    case .finishPass:
                        self.finishCurrentPass()
                    case .none:
                        if self.options.captureMode == .smartAutomatic,
                           self.passImageCount >= self.targetImagesPerPass {
                            self.finishCurrentPass()
                        }
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
        guard passImageCount > 0 else {
            statusMessage = "لا يمكن إنهاء الجولة قبل التقاط صورة واحدة على الأقل."
            return
        }

        pauseLiveCameraForReview()
        phase = .readyToReconstruct
        statusMessage = "اكتملت الجولة \(passNumber) بعد \(passImageCount) صورة. راجع العدد ثم ابنِ النموذج أو ابدأ جولة إضافية."
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard output === videoOutput else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard timestamp.isFinite, timestamp - lastAnalysisTimestamp >= 0.24 else { return }
        lastAnalysisTimestamp = timestamp

        guard let signature = makeFrameSignature(pixelBuffer: pixelBuffer) else { return }

        signatureLock.lock()
        let previous = previousSignature
        let acceptedSnapshot = acceptedSignatures
        latestSignature = signature
        previousSignature = signature
        signatureLock.unlock()

        let motionDistance = previous.map { signatureDistance($0, signature) } ?? 0
        let changeFromLastAccepted = acceptedSnapshot.last.map { signatureDistance($0, signature) } ?? 1

        DispatchQueue.main.async {
            guard self.phase == .capturing else { return }
            self.visualChangeScore = changeFromLastAccepted

            guard self.options.captureMode == .smartAutomatic else {
                self.smartCaptureState = "يدوي — اضغط التقاط عند الزاوية المطلوبة"
                return
            }
            guard !self.captureInFlight else { return }

            let now = Date().timeIntervalSinceReferenceDate
            guard now >= self.analysisPausedUntil else {
                self.smartCaptureState = "تهيئة الالتقاط التلقائي…"
                return
            }
            guard now - self.lastAcceptedCaptureTimestamp >= self.options.captureInterval else { return }

            let isStable = motionDistance <= self.options.stabilityThreshold
            if isStable {
                self.autoStableFrameCount += 1
            } else {
                self.autoStableFrameCount = 0
                if !acceptedSnapshot.isEmpty {
                    self.autoMovementArmed = true
                }
                self.smartCaptureState = "المجسم يتحرك — استمر ثم توقف لحظة"
                return
            }

            // Always prove that Smart Auto is alive by taking the first image after
            // two stable analysis frames. Later images require a genuinely new view.
            if acceptedSnapshot.isEmpty {
                guard self.autoStableFrameCount >= 2 else {
                    self.smartCaptureState = "ثبّت المجسم لحظة للصورة الأولى"
                    return
                }
                self.smartCaptureState = "ثابت — التقاط الصورة الأولى تلقائيًا"
                self.autoStableFrameCount = 0
                self.requestPhotoCapture(signature: signature)
                return
            }

            if changeFromLastAccepted >= self.options.noveltyThreshold {
                self.autoMovementArmed = true
            }

            guard self.autoMovementArmed else {
                self.smartCaptureState = "نفس الزاوية — لف المجسم لمكان جديد"
                return
            }

            guard changeFromLastAccepted >= self.options.noveltyThreshold else {
                self.smartCaptureState = "التغيير قليل — لف المجسم أكثر"
                return
            }

            guard self.autoStableFrameCount >= 2 else {
                self.smartCaptureState = "زاوية جديدة — توقف لحظة"
                return
            }

            self.smartCaptureState = "زاوية جديدة وثابتة — التقاط تلقائي"
            self.autoStableFrameCount = 0
            self.autoMovementArmed = false
            self.requestPhotoCapture(signature: signature)
        }
    }

    private func makeFrameSignature(pixelBuffer: CVPixelBuffer) -> FrameSignature? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 40, height > 40 else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let cols = 32
        let rows = 24
        // Concentrate the signature on the framed object, not the static background.
        let x0 = Int(Double(width) * 0.20)
        let x1 = Int(Double(width) * 0.80)
        let y0 = Int(Double(height) * 0.18)
        let y1 = Int(Double(height) * 0.82)
        let roiWidth = max(1, x1 - x0)
        let roiHeight = max(1, y1 - y0)

        var signature = FrameSignature()
        signature.reserveCapacity(cols * rows)
        for row in 0..<rows {
            let y = min(height - 1, y0 + (row * roiHeight) / max(1, rows - 1))
            for col in 0..<cols {
                let x = min(width - 1, x0 + (col * roiWidth) / max(1, cols - 1))
                let offset = y * bytesPerRow + x * 4
                let b = UInt16(pixels[offset])
                let g = UInt16(pixels[offset + 1])
                let r = UInt16(pixels[offset + 2])
                let luminance = UInt8(min(255, (r + 2 * g + b) / 4))
                signature.append(luminance)
            }
        }
        return signature
    }

    private func signatureDistance(_ lhs: FrameSignature, _ rhs: FrameSignature) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 1 }
        var sum: UInt64 = 0
        for index in lhs.indices {
            sum += UInt64(abs(Int(lhs[index]) - Int(rhs[index])))
        }
        return Float(sum) / Float(lhs.count * 255)
    }

    private func resetSignatures(keepAccepted: Bool) {
        signatureLock.lock()
        previousSignature = nil
        pendingCaptureSignature = nil
        latestSignature = nil
        if !keepAccepted { acceptedSignatures.removeAll(keepingCapacity: false) }
        signatureLock.unlock()
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

        stopLiveCamera()

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
                            self.stopLiveCamera()
                            self.modelURL = published
                            self.reconstructionProgress = 1
                            self.phase = .completed
                            self.statusMessage = "اكتمل نموذج Turntable الملوّن."
                        }
                        if let workFolder { try? self.fileManager.removeItem(at: workFolder) }
                    }
                }
            } catch {
                await MainActor.run {
                    self.stopLiveCamera()
                    self.phase = .failed
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = "فشلت إعادة بناء نموذج Turntable."
                }
            }
            self.photogrammetrySession = nil
        }
    }

    private func pauseLiveCameraForReview() {
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        cameraReady = false
        cameraLocked = false
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    private func stopLiveCamera() {
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        cameraReady = false
        cameraLocked = false

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            self.cameraDevice = nil
        }
    }

    private func cleanup(removeWorkingFiles: Bool) {
        resetSignatures(keepAccepted: false)
        autoStableFrameCount = 0
        autoMovementArmed = false
        pendingAction = .none
        reconstructionTask?.cancel()
        reconstructionTask = nil
        photogrammetrySession?.cancel()
        photogrammetrySession = nil
        stopLiveCamera()

        if removeWorkingFiles, let workFolderURL { try? fileManager.removeItem(at: workFolderURL) }
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
        case .cameraUnavailable: "تعذر تشغيل الكاميرا الخلفية."
        case .photoOutputUnavailable: "تعذر تشغيل التقاط الصور عالية الجودة."
        case .videoOutputUnavailable: "تعذر تشغيل تحليل الفيديو للـTurntable."
        }
    }
}

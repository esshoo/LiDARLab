import Combine
import Foundation
import RealityKit

@MainActor
final class AreaScanViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case initializing
        case ready
        case capturing
        case finishing
        case reconstructing
        case completed
        case failed

        var title: String {
            switch self {
            case .idle: "جاهز"
            case .initializing: "تهيئة Area Mode"
            case .ready: "جاهز لبدء المسح"
            case .capturing: "مسح المكان"
            case .finishing: "إنهاء الالتقاط"
            case .reconstructing: "بناء النموذج"
            case .completed: "اكتمل النموذج"
            case .failed: "حدث خطأ"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var captureSession: ObjectCaptureSession?
    @Published private(set) var shotCount = 0
    @Published private(set) var maximumShotCount = 0
    @Published private(set) var reconstructionProgress: Double = 0
    @Published private(set) var modelURL: URL?
    @Published private(set) var sessionFolderURL: URL?
    @Published private(set) var statusMessage = "Area Mode يستخدم واجهة Object Capture الرسمية من Apple."
    @Published private(set) var feedbackMessage: String?
    @Published var errorMessage: String?

    private let fileManager = FileManager.default
    private var options = Color3DScanSettings.appleAreaOptions
    private var workFolderURL: URL?
    private var imagesURL: URL?
    private var checkpointsURL: URL?
    private var localModelURL: URL?
    private var finalFolderURL: URL?
    private var listenerTasks: [Task<Void, Never>] = []
    private var reconstructionTask: Task<Void, Never>?
    private var photogrammetrySession: PhotogrammetrySession?

    var isSupported: Bool {
        if #available(iOS 18.0, *) {
            return ObjectCaptureSession.isSupported && PhotogrammetrySession.isSupported
        }
        return false
    }

    var canStartCapture: Bool {
        phase == .ready
    }

    var canFinishCapture: Bool {
        phase == .capturing && shotCount >= options.minimumImagesBeforeFinish
    }

    var minimumImagesBeforeFinish: Int {
        options.minimumImagesBeforeFinish
    }

    func prepareSession() {
        guard #available(iOS 18.0, *) else {
            errorMessage = "Apple Object Capture Area Mode يحتاج iOS 18 أو أحدث."
            return
        }
        guard ObjectCaptureSession.isSupported, PhotogrammetrySession.isSupported else {
            errorMessage = "هذا الجهاز لا يدعم Object Capture Area Mode وإعادة البناء على الجهاز."
            return
        }

        cleanup(removeWorkingFiles: true)
        options = Color3DScanSettings.appleAreaOptions

        do {
            let storage = LiDARLabStorage.shared
            try storage.ensureDirectories()

            let finalRoot = storage.capturesURL
                .appendingPathComponent("Color3D", isDirectory: true)
                .appendingPathComponent("Areas", isDirectory: true)
            try fileManager.createDirectory(at: finalRoot, withIntermediateDirectories: true)

            let uniqueName = storage.timestampedName(prefix: "AreaScan") + "-" + String(UUID().uuidString.prefix(8))
            let finalFolder = finalRoot.appendingPathComponent(uniqueName, isDirectory: true)

            let cacheRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("3ELiDAR-AreaCaptureWork", isDirectory: true)
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
            localModelURL = modelFolder.appendingPathComponent("area-model.usdz")
            finalFolderURL = finalFolder
            sessionFolderURL = finalFolder
            modelURL = nil
            reconstructionProgress = 0
            shotCount = 0
            maximumShotCount = 0
            feedbackMessage = nil
            captureSession = session
            phase = .initializing
            statusMessage = "جاري تجهيز Apple Object Capture…"

            attachListeners(to: session)
            session.start(imagesDirectory: images, configuration: configuration)
            handleState(session.state)
            shotCount = session.numberOfShotsTaken
            maximumShotCount = session.maximumNumberOfInputImages
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
            statusMessage = "تعذر بدء Area Mode."
        }
    }

    /// Official Area Mode: intentionally skip startDetecting() and go straight to startCapturing().
    func startAreaCapture() {
        guard #available(iOS 18.0, *), let session = captureSession else { return }
        guard phase == .ready else { return }
        session.startCapturing()
        handleState(session.state)
        statusMessage = "امسح الأسطح ببطء كأن المؤشر فرشاة. حافظ على تداخل الصور وغيّر الارتفاع."
    }

    func requestManualShot() {
        guard let session = captureSession,
              phase == .capturing,
              session.canRequestImageCapture else { return }
        session.requestImageCapture()
    }

    func finishCapture() {
        guard let session = captureSession, phase == .capturing else { return }
        session.finish()
        handleState(session.state)
        statusMessage = "جاري حفظ بيانات الالتقاط قبل إعادة البناء…"
    }

    func cancelAndReset() {
        cleanup(removeWorkingFiles: true)
        phase = .idle
        shotCount = 0
        maximumShotCount = 0
        reconstructionProgress = 0
        modelURL = nil
        sessionFolderURL = nil
        feedbackMessage = nil
        errorMessage = nil
        statusMessage = "Area Mode يستخدم واجهة Object Capture الرسمية من Apple."
    }

    func clearError() {
        errorMessage = nil
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
            phase = .initializing
            statusMessage = "جاري تهيئة الكاميرا وLiDAR…"
        case .ready:
            phase = .ready
            statusMessage = "وجّه الهاتف للمكان ثم اضغط بدء المسح. لن يتم إنشاء Bounding Box في Area Mode."
        case .detecting:
            // Area Mode must never intentionally enter object detection.
            phase = .ready
            statusMessage = "تم إلغاء مسار اكتشاف جسم؛ Area Mode يبدأ مباشرة بالالتقاط."
        case .capturing:
            phase = .capturing
            statusMessage = "حرّك الهاتف ببطء وبمسارات متداخلة ومن ارتفاعات مختلفة."
        case .finishing:
            phase = .finishing
            statusMessage = "جاري إنهاء جلسة الالتقاط…"
        case .completed:
            phase = .reconstructing
            statusMessage = "اكتمل الالتقاط. جاري بناء USDZ باستخدام PhotogrammetrySession…"
            detachListeners()
            captureSession = nil
            startReconstruction()
        case .failed(let error):
            phase = .failed
            errorMessage = error.localizedDescription
            statusMessage = "فشل Object Capture: \(error.localizedDescription)"
        @unknown default:
            statusMessage = "تغيّرت حالة جلسة الالتقاط."
        }
    }

    private func startReconstruction() {
        reconstructionTask?.cancel()
        guard let imagesURL, let localModelURL else {
            phase = .failed
            errorMessage = "صور Area Mode غير متاحة لإعادة البناء."
            return
        }

        try? fileManager.removeItem(at: localModelURL)
        let keepSources = options.keepSourceImages
        let finalFolder = finalFolderURL
        let workingFolder = workFolderURL

        reconstructionTask = Task { [weak self] in
            guard let self else { return }
            do {
                var configuration = PhotogrammetrySession.Configuration()
                configuration.checkpointDirectory = self.checkpointsURL

                let session = try PhotogrammetrySession(input: imagesURL, configuration: configuration)
                self.photogrammetrySession = session
                self.reconstructionProgress = 0

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
                        self.statusMessage = "تعذر بناء نموذج Area Mode."
                    case .processingComplete:
                        guard self.fileManager.fileExists(atPath: localModelURL.path), let finalFolder else {
                            if self.phase != .failed {
                                self.phase = .failed
                                self.errorMessage = "انتهت المعالجة بدون ملف USDZ."
                            }
                            continue
                        }
                        try self.fileManager.createDirectory(at: finalFolder, withIntermediateDirectories: true)
                        let finalModelFolder = finalFolder.appendingPathComponent("Model", isDirectory: true)
                        try self.fileManager.createDirectory(at: finalModelFolder, withIntermediateDirectories: true)
                        let published = finalModelFolder.appendingPathComponent("area-model.usdz")
                        try? self.fileManager.removeItem(at: published)
                        try self.fileManager.copyItem(at: localModelURL, to: published)

                        if keepSources {
                            let sourceFolder = finalFolder.appendingPathComponent("Images", isDirectory: true)
                            try? self.fileManager.removeItem(at: sourceFolder)
                            try self.fileManager.copyItem(at: imagesURL, to: sourceFolder)
                        }

                        self.modelURL = published
                        self.reconstructionProgress = 1
                        self.phase = .completed
                        self.statusMessage = "اكتمل نموذج Apple Area Mode ويمكن فتحه في Quick Look."
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
                self.statusMessage = "فشلت إعادة بناء Area Mode."
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

        if removeWorkingFiles, let workFolderURL {
            try? fileManager.removeItem(at: workFolderURL)
        }
        workFolderURL = nil
        imagesURL = nil
        checkpointsURL = nil
        localModelURL = nil
        finalFolderURL = nil
    }

    private static func describe(feedback: Set<ObjectCaptureSession.Feedback>) -> String? {
        if feedback.contains(.environmentTooDark) { return "الإضاءة مظلمة جدًا؛ زد الإضاءة قبل المتابعة." }
        if feedback.contains(.environmentLowLight) { return "الإضاءة منخفضة وقد تقل جودة النموذج." }
        if feedback.contains(.movingTooFast) { return "الحركة سريعة؛ تحرك أبطأ للحصول على صور أوضح ومتداخلة." }
        if feedback.contains(.objectTooClose) { return "أنت قريب جدًا من السطح." }
        if feedback.contains(.objectTooFar) { return "أنت بعيد جدًا عن السطح." }
        if feedback.contains(.overCapturing) { return "تم تجاوز عدد الصور المفيد لإعادة البناء على الهاتف؛ يمكنك الإنهاء الآن." }
        return nil
    }
}

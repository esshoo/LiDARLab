import Combine
import Foundation
import RealityKit
import SwiftUI

@MainActor
final class ObjectScanViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case initializing
        case ready
        case detecting
        case capturing
        case finishing
        case reconstructing
        case completed
        case failed

        var title: String {
            switch self {
            case .idle: "جاهز للبدء"
            case .initializing: "تهيئة الكاميرا"
            case .ready: "جاهز لتحديد الجسم"
            case .detecting: "تحديد حدود الجسم"
            case .capturing: "التقاط الصور"
            case .finishing: "حفظ بيانات الالتقاط"
            case .reconstructing: "بناء النموذج ثلاثي الأبعاد"
            case .completed: "اكتمل النموذج"
            case .failed: "حدث خطأ"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var objectCaptureSession: ObjectCaptureSession?
    @Published private(set) var shotCount = 0
    @Published private(set) var maximumShotCount = 0
    @Published private(set) var scanPassComplete = false
    @Published private(set) var feedbackCount = 0
    @Published private(set) var objectMayBeFlipped = true
    @Published private(set) var reconstructionProgress: Double = 0
    @Published private(set) var modelURL: URL?
    @Published private(set) var sessionFolderURL: URL?
    @Published private(set) var statusMessage = "ابدأ جلسة جديدة لمسح جسم صغير بالألوان."
    @Published private(set) var initializationIsSlow = false
    @Published var errorMessage: String?

    private let fileManager = FileManager.default
    private var imagesURL: URL?
    private var snapshotsURL: URL?
    private var localOutputURL: URL?
    private var workingFolderURL: URL?
    private var finalFolderURL: URL?
    private var listenerTasks: [Task<Void, Never>] = []
    private var reconstructionTask: Task<Void, Never>?
    private var initializationWatchdogTask: Task<Void, Never>?
    private var photogrammetrySession: PhotogrammetrySession?
    private var runtimeOptions = Color3DScanSettings.objectOptions

    var isSupported: Bool {
        ObjectCaptureSession.isSupported && PhotogrammetrySession.isSupported
    }

    var canStartDetection: Bool { phase == .ready }
    var canStartCapturing: Bool { phase == .detecting || phase == .ready }
    var canFinishCapture: Bool {
        phase == .capturing && shotCount >= runtimeOptions.minimumImagesBeforeFinish
    }
    var canRequestManualShot: Bool {
        phase == .capturing && objectCaptureSession?.canRequestImageCapture == true
    }

    func startNewScan() {
        guard isSupported else {
            errorMessage = "هذا الجهاز لا يدعم Object Capture وإعادة البناء على الجهاز."
            return
        }

        cleanupActiveSessions(cancelCapture: true, removeWorkingFiles: true)
        runtimeOptions = Color3DScanSettings.objectOptions

        do {
            let storage = LiDARLabStorage.shared
            try storage.ensureDirectories()

            let finalRoot = storage.capturesURL
                .appendingPathComponent("Color3D", isDirectory: true)
                .appendingPathComponent("Objects", isDirectory: true)
            try fileManager.createDirectory(at: finalRoot, withIntermediateDirectories: true)

            let uniqueName = storage.timestampedName(prefix: "ObjectScan") + "-" + String(UUID().uuidString.prefix(8))
            let finalFolder = finalRoot.appendingPathComponent(String(uniqueName), isDirectory: true)

            // ObjectCaptureSession is intentionally given an app-local writable folder.
            // Some Files/security-scoped locations are valid for normal FileManager writes but are
            // unreliable for camera framework working data. We publish the result afterwards.
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let workFolder = caches
                .appendingPathComponent("3ELiDAR-ObjectCaptureWork", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let images = workFolder.appendingPathComponent("Images", isDirectory: true)
            let snapshots = workFolder.appendingPathComponent("Snapshots", isDirectory: true)
            let output = workFolder.appendingPathComponent("Model", isDirectory: true)

            try fileManager.createDirectory(at: images, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: snapshots, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: output, withIntermediateDirectories: true)

            let session = ObjectCaptureSession()
            var configuration = ObjectCaptureSession.Configuration()
            configuration.checkpointDirectory = snapshots
            configuration.isOverCaptureEnabled = false

            if #available(iOS 18.0, *) {
                session.isAutoCaptureEnabled = runtimeOptions.autoCapture
                session.shouldPlayHaptics = runtimeOptions.haptics
            }

            workingFolderURL = workFolder
            finalFolderURL = finalFolder
            sessionFolderURL = finalFolder
            imagesURL = images
            snapshotsURL = snapshots
            localOutputURL = output
            modelURL = nil
            reconstructionProgress = 0
            shotCount = 0
            maximumShotCount = 0
            scanPassComplete = false
            feedbackCount = 0
            initializationIsSlow = false
            objectCaptureSession = session
            phase = .initializing
            statusMessage = "جاري تجهيز Object Capture…"

            // Listen BEFORE start(). A fast state transition to .ready/.failed can otherwise be missed,
            // leaving our UI stuck forever on the locally stored .initializing state.
            attachListeners(to: session)
            session.start(imagesDirectory: images, configuration: configuration)

            // Reconcile synchronously as well, in case the transition happened before the async stream yielded.
            handleCaptureState(session.state)
            shotCount = session.numberOfShotsTaken
            maximumShotCount = session.maximumNumberOfInputImages
            scanPassComplete = session.userCompletedScanPass
            feedbackCount = session.feedback.count
            objectMayBeFlipped = !session.feedback.contains(.objectNotFlippable)
            startInitializationWatchdog(for: session)
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
            statusMessage = "تعذر بدء جلسة Object Capture."
        }
    }

    func startDetecting() {
        guard let session = objectCaptureSession else { return }
        guard session.startDetecting() else {
            statusMessage = "تعذر بدء اكتشاف الجسم الآن. وجّه الكاميرا للجسم وحاول مرة أخرى."
            return
        }
        handleCaptureState(session.state)
        statusMessage = "عدّل الصندوق ليحيط بالجسم فقط، ثم ابدأ الالتقاط."
    }

    func resetDetection() {
        guard let session = objectCaptureSession else { return }
        if session.resetDetection() {
            handleCaptureState(session.state)
            statusMessage = "تمت إعادة تحديد الجسم. وجّه الكاميرا إليه من جديد."
        }
    }

    func startCapturing() {
        guard let session = objectCaptureSession else { return }
        session.startCapturing()
        handleCaptureState(session.state)
        statusMessage = "تحرّك ببطء حول الجسم وحافظ عليه داخل الإطار."
    }

    func requestManualShot() {
        guard let session = objectCaptureSession,
              session.canRequestImageCapture else { return }
        session.requestImageCapture()
    }

    func beginAdditionalPass() {
        guard let session = objectCaptureSession, phase == .capturing else { return }
        session.beginNewScanPass()
        scanPassComplete = false
        statusMessage = "ابدأ جولة جديدة من ارتفاع مختلف حول الجسم."
    }

    func beginPassAfterFlip() {
        guard let session = objectCaptureSession, phase == .capturing else { return }
        session.beginNewScanPassAfterFlip()
        scanPassComplete = false
        statusMessage = "اقلب الجسم وثبته، ثم اضبط الصندوق وواصل الالتقاط."
    }

    func finishCapture() {
        guard let session = objectCaptureSession, phase == .capturing else { return }
        session.finish()
        handleCaptureState(session.state)
        statusMessage = "جاري تثبيت الصور وبيانات العمق…"
    }

    func pauseCapture() {
        guard let session = objectCaptureSession, !session.isPaused else { return }
        session.pause()
    }

    func resumeCapture() {
        guard let session = objectCaptureSession, session.isPaused else { return }
        session.resume()
    }

    func retryInitialization() {
        startNewScan()
    }

    func cancelAndReset() {
        cleanupActiveSessions(cancelCapture: true, removeWorkingFiles: true)
        phase = .idle
        modelURL = nil
        sessionFolderURL = nil
        imagesURL = nil
        snapshotsURL = nil
        localOutputURL = nil
        finalFolderURL = nil
        shotCount = 0
        maximumShotCount = 0
        scanPassComplete = false
        feedbackCount = 0
        reconstructionProgress = 0
        initializationIsSlow = false
        statusMessage = "ابدأ جلسة جديدة لمسح جسم صغير بالألوان."
    }

    func clearError() {
        errorMessage = nil
    }

    deinit {
        for task in listenerTasks { task.cancel() }
        reconstructionTask?.cancel()
        initializationWatchdogTask?.cancel()
    }

    private func attachListeners(to session: ObjectCaptureSession) {
        detachListeners()

        listenerTasks.append(Task { [weak self, weak session] in
            guard let session else { return }
            for await newState in session.stateUpdates {
                guard !Task.isCancelled else { return }
                self?.handleCaptureState(newState)
            }
        })

        listenerTasks.append(Task { [weak self, weak session] in
            guard let session else { return }
            for await count in session.numberOfShotsTakenUpdates {
                guard !Task.isCancelled else { return }
                self?.shotCount = count
            }
        })

        listenerTasks.append(Task { [weak self, weak session] in
            guard let session else { return }
            for await completed in session.userCompletedScanPassUpdates {
                guard !Task.isCancelled else { return }
                self?.scanPassComplete = completed
                if completed {
                    self?.statusMessage = "اكتملت جولة كاملة. يمكنك إضافة جولة أخرى أو إنهاء المسح وبناء النموذج."
                }
            }
        })

        listenerTasks.append(Task { [weak self, weak session] in
            guard let session else { return }
            for await feedback in session.feedbackUpdates {
                guard !Task.isCancelled else { return }
                self?.feedbackCount = feedback.count
                self?.objectMayBeFlipped = !feedback.contains(.objectNotFlippable)
            }
        })
    }

    private func detachListeners() {
        for task in listenerTasks { task.cancel() }
        listenerTasks.removeAll()
    }

    private func startInitializationWatchdog(for session: ObjectCaptureSession) {
        initializationWatchdogTask?.cancel()
        initializationWatchdogTask = Task { [weak self, weak session] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled, let self, let session else { return }
            if self.phase == .initializing {
                self.initializationIsSlow = true
                self.handleCaptureState(session.state)
                if self.phase == .initializing {
                    self.statusMessage = "التهيئة تستغرق وقتًا غير طبيعي. تأكد من إذن الكاميرا، أغلق أي تطبيق يستخدم الكاميرا، ثم اضغط إعادة المحاولة."
                }
            }
        }
    }

    private func handleCaptureState(_ state: ObjectCaptureSession.CaptureState) {
        switch state {
        case .initializing:
            phase = .initializing
            statusMessage = "جاري تهيئة الكاميرا وLiDAR…"
        case .ready:
            initializationWatchdogTask?.cancel()
            initializationIsSlow = false
            phase = .ready
            statusMessage = "ضع الجسم أمام الكاميرا ثم اضغط تحديد الجسم."
        case .detecting:
            initializationWatchdogTask?.cancel()
            initializationIsSlow = false
            phase = .detecting
            statusMessage = "اضبط صندوق الالتقاط حول الجسم ثم ابدأ المسح."
        case .capturing:
            initializationWatchdogTask?.cancel()
            initializationIsSlow = false
            phase = .capturing
            statusMessage = "تحرّك ببطء حول الجسم. الالتقاط يعمل الآن."
        case .finishing:
            initializationWatchdogTask?.cancel()
            phase = .finishing
            statusMessage = "جاري إنهاء جلسة الالتقاط وحفظ الصور…"
        case .completed:
            initializationWatchdogTask?.cancel()
            phase = .reconstructing
            statusMessage = "تم الالتقاط. جاري إنشاء USDZ ملوّن على الجهاز…"
            detachListeners()
            objectCaptureSession = nil
            startReconstruction()
        case .failed(let error):
            initializationWatchdogTask?.cancel()
            phase = .failed
            errorMessage = error.localizedDescription
            statusMessage = "فشلت جلسة Object Capture: \(error.localizedDescription)"
        @unknown default:
            statusMessage = "تغيّرت حالة جلسة الالتقاط."
        }
    }

    private func startReconstruction() {
        reconstructionTask?.cancel()
        guard let imagesURL, let localOutputURL else {
            phase = .failed
            errorMessage = "مجلد صور المسح غير متاح لإعادة البناء."
            return
        }

        let snapshotsURL = self.snapshotsURL
        let localModelURL = localOutputURL.appendingPathComponent("model.usdz")
        try? fileManager.removeItem(at: localModelURL)

        reconstructionTask = Task { [weak self] in
            guard let self else { return }
            do {
                var configuration = PhotogrammetrySession.Configuration()
                configuration.checkpointDirectory = snapshotsURL

                let session = try PhotogrammetrySession(
                    input: imagesURL,
                    configuration: configuration
                )
                self.photogrammetrySession = session
                self.reconstructionProgress = 0

                let request = PhotogrammetrySession.Request.modelFile(
                    url: localModelURL,
                    detail: .reduced
                )
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
                        self.statusMessage = "تعذر إنشاء النموذج ثلاثي الأبعاد."

                    case .processingComplete:
                        if self.fileManager.fileExists(atPath: localModelURL.path) {
                            try self.publishCompletedCapture(localModelURL: localModelURL)
                            self.reconstructionProgress = 1
                            self.phase = .completed
                            self.statusMessage = "اكتمل نموذج USDZ الملوّن ويمكن معاينته أو مشاركته."
                        } else if self.phase != .failed {
                            self.phase = .failed
                            self.errorMessage = "انتهت المعالجة لكن ملف النموذج لم يتم العثور عليه."
                        }

                    default:
                        break
                    }
                }
            } catch {
                self.phase = .failed
                self.errorMessage = error.localizedDescription
                self.statusMessage = "فشلت إعادة بناء النموذج."
            }
            self.photogrammetrySession = nil
        }
    }

    private func publishCompletedCapture(localModelURL: URL) throws {
        guard let finalFolderURL else {
            throw CocoaError(.fileNoSuchFile)
        }

        let modelFolder = finalFolderURL.appendingPathComponent("Model", isDirectory: true)
        try fileManager.createDirectory(at: modelFolder, withIntermediateDirectories: true)
        let publishedModel = modelFolder.appendingPathComponent("model.usdz")
        try? fileManager.removeItem(at: publishedModel)
        try fileManager.copyItem(at: localModelURL, to: publishedModel)

        if runtimeOptions.keepSourceImages, let imagesURL {
            let targetImages = finalFolderURL.appendingPathComponent("Images", isDirectory: true)
            try? fileManager.removeItem(at: targetImages)
            try fileManager.copyItem(at: imagesURL, to: targetImages)
        }

        modelURL = publishedModel
        sessionFolderURL = finalFolderURL
        writeManifestIfPossible(folder: finalFolderURL)

        if let workingFolderURL {
            try? fileManager.removeItem(at: workingFolderURL)
            self.workingFolderURL = nil
        }
    }

    private func writeManifestIfPossible(folder: URL) {
        let record = ObjectScanManifest(
            schemaVersion: 2,
            createdAt: Date(),
            imageCount: shotCount,
            modelFile: modelURL.map { "Model/\($0.lastPathComponent)" },
            keptSourceImages: runtimeOptions.keepSourceImages,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(
                to: folder.appendingPathComponent("scan.json"),
                options: .atomic
            )
        } catch {
            // The model is already complete; metadata failure must not discard it.
        }
    }

    private func cleanupActiveSessions(cancelCapture: Bool, removeWorkingFiles: Bool) {
        detachListeners()
        initializationWatchdogTask?.cancel()
        initializationWatchdogTask = nil
        reconstructionTask?.cancel()
        reconstructionTask = nil
        photogrammetrySession?.cancel()
        photogrammetrySession = nil
        if cancelCapture {
            objectCaptureSession?.cancel()
        }
        objectCaptureSession = nil
        if removeWorkingFiles, let workingFolderURL {
            try? fileManager.removeItem(at: workingFolderURL)
            self.workingFolderURL = nil
        }
    }
}

private struct ObjectScanManifest: Codable {
    let schemaVersion: Int
    let createdAt: Date
    let imageCount: Int
    let modelFile: String?
    let keptSourceImages: Bool
    let appVersion: String
}

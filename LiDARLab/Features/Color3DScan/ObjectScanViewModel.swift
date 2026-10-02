import Foundation
import Combine
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
    @Published var errorMessage: String?

    private var imagesURL: URL?
    private var snapshotsURL: URL?
    private var outputURL: URL?
    private var listenerTasks: [Task<Void, Never>] = []
    private var reconstructionTask: Task<Void, Never>?
    private var photogrammetrySession: PhotogrammetrySession?

    var isSupported: Bool {
        ObjectCaptureSession.isSupported && PhotogrammetrySession.isSupported
    }

    var canStartDetection: Bool { phase == .ready }
    var canStartCapturing: Bool { phase == .detecting || phase == .ready }
    var canFinishCapture: Bool { phase == .capturing && shotCount >= 10 }
    var canRequestManualShot: Bool {
        phase == .capturing && objectCaptureSession?.canRequestImageCapture == true
    }

    func startNewScan() {
        guard isSupported else {
            errorMessage = "هذا الجهاز لا يدعم Object Capture وإعادة البناء على الجهاز."
            return
        }

        cleanupActiveSessions(cancelCapture: true)

        do {
            let storage = LiDARLabStorage.shared
            try storage.ensureDirectories()

            let root = storage.capturesURL
                .appendingPathComponent("Color3D", isDirectory: true)
                .appendingPathComponent("Objects", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

            let folder = root.appendingPathComponent(
                storage.timestampedName(prefix: "ObjectScan"),
                isDirectory: true
            )
            let images = folder.appendingPathComponent("Images", isDirectory: true)
            let snapshots = folder.appendingPathComponent("Snapshots", isDirectory: true)
            let output = folder.appendingPathComponent("Model", isDirectory: true)
            try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

            let session = ObjectCaptureSession()
            var configuration = ObjectCaptureSession.Configuration()
            configuration.checkpointDirectory = snapshots
            configuration.isOverCaptureEnabled = false

            // These properties were introduced in iOS 18. Keep iOS 17 support intact.
            if #available(iOS 18.0, *) {
                session.isAutoCaptureEnabled = true
                session.shouldPlayHaptics = true
            }

            session.start(imagesDirectory: images, configuration: configuration)

            objectCaptureSession = session
            sessionFolderURL = folder
            imagesURL = images
            snapshotsURL = snapshots
            outputURL = output
            modelURL = nil
            reconstructionProgress = 0
            shotCount = session.numberOfShotsTaken
            maximumShotCount = session.maximumNumberOfInputImages
            scanPassComplete = session.userCompletedScanPass
            feedbackCount = session.feedback.count
            objectMayBeFlipped = !session.feedback.contains(.objectNotFlippable)
            phase = .initializing
            statusMessage = "جاري تجهيز Object Capture…"
            attachListeners(to: session)
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }

    func startDetecting() {
        guard let session = objectCaptureSession else { return }
        guard session.startDetecting() else {
            statusMessage = "تعذر بدء اكتشاف الجسم الآن. وجّه الكاميرا للجسم وحاول مرة أخرى."
            return
        }
        statusMessage = "عدّل الصندوق ليحيط بالجسم فقط، ثم ابدأ الالتقاط."
    }

    func resetDetection() {
        guard let session = objectCaptureSession else { return }
        if session.resetDetection() {
            statusMessage = "تمت إعادة تحديد الجسم. وجّه الكاميرا إليه من جديد."
        }
    }

    func startCapturing() {
        guard let session = objectCaptureSession else { return }
        session.startCapturing()
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
        statusMessage = "جاري تثبيت الصور وبيانات العمق…"
    }

    func pauseCapture() {
        objectCaptureSession?.pause()
    }

    func resumeCapture() {
        objectCaptureSession?.resume()
    }

    func cancelAndReset() {
        cleanupActiveSessions(cancelCapture: true)
        phase = .idle
        modelURL = nil
        sessionFolderURL = nil
        imagesURL = nil
        snapshotsURL = nil
        outputURL = nil
        shotCount = 0
        maximumShotCount = 0
        scanPassComplete = false
        feedbackCount = 0
        reconstructionProgress = 0
        statusMessage = "ابدأ جلسة جديدة لمسح جسم صغير بالألوان."
    }

    func clearError() {
        errorMessage = nil
    }

    deinit {
        for task in listenerTasks { task.cancel() }
        reconstructionTask?.cancel()
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

    private func handleCaptureState(_ state: ObjectCaptureSession.CaptureState) {
        switch state {
        case .initializing:
            phase = .initializing
            statusMessage = "جاري تهيئة الكاميرا وLiDAR…"
        case .ready:
            phase = .ready
            statusMessage = "ضع الجسم أمام الكاميرا ثم اضغط تحديد الجسم."
        case .detecting:
            phase = .detecting
            statusMessage = "اضبط صندوق الالتقاط حول الجسم ثم ابدأ المسح."
        case .capturing:
            phase = .capturing
            statusMessage = "تحرّك ببطء حول الجسم. الالتقاط يتم تلقائيًا."
        case .finishing:
            phase = .finishing
            statusMessage = "جاري إنهاء جلسة الالتقاط وحفظ الصور…"
        case .completed:
            phase = .reconstructing
            statusMessage = "تم الالتقاط. جاري إنشاء USDZ ملوّن على الجهاز…"
            detachListeners()
            objectCaptureSession = nil
            startReconstruction()
        case .failed(let error):
            phase = .failed
            errorMessage = error.localizedDescription
            statusMessage = "فشلت جلسة Object Capture."
        @unknown default:
            statusMessage = "تغيّرت حالة جلسة الالتقاط."
        }
    }

    private func startReconstruction() {
        reconstructionTask?.cancel()
        guard let imagesURL, let outputURL else {
            phase = .failed
            errorMessage = "مجلد صور المسح غير متاح لإعادة البناء."
            return
        }

        let snapshotsURL = self.snapshotsURL
        let finalURL = outputURL.appendingPathComponent("model.usdz")
        try? FileManager.default.removeItem(at: finalURL)

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
                    url: finalURL,
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

                    case .requestComplete(_, let result):
                        if case .modelFile(let url) = result {
                            self.modelURL = url
                        }

                    case .requestError(_, let error):
                        self.phase = .failed
                        self.errorMessage = error.localizedDescription
                        self.statusMessage = "تعذر إنشاء النموذج ثلاثي الأبعاد."

                    case .processingComplete:
                        if FileManager.default.fileExists(atPath: finalURL.path) {
                            self.modelURL = finalURL
                            self.reconstructionProgress = 1
                            self.phase = .completed
                            self.statusMessage = "اكتمل نموذج USDZ الملوّن ويمكن معاينته أو مشاركته."
                            self.writeManifestIfPossible()
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

    private func writeManifestIfPossible() {
        guard let folder = sessionFolderURL else { return }
        let record = ObjectScanManifest(
            schemaVersion: 1,
            createdAt: Date(),
            imageCount: shotCount,
            modelFile: modelURL.map { "Model/\($0.lastPathComponent)" },
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
            // The model is already complete; a metadata write failure should not discard it.
        }
    }

    private func cleanupActiveSessions(cancelCapture: Bool) {
        detachListeners()
        reconstructionTask?.cancel()
        reconstructionTask = nil
        photogrammetrySession?.cancel()
        photogrammetrySession = nil
        if cancelCapture {
            objectCaptureSession?.cancel()
        }
        objectCaptureSession = nil
    }
}

private struct ObjectScanManifest: Codable {
    let schemaVersion: Int
    let createdAt: Date
    let imageCount: Int
    let modelFile: String?
    let appVersion: String
}

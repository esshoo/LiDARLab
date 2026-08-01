import ARKit
import Combine
import RoomPlan
import UIKit

struct RoomScanExport: Identifiable {
    let id = UUID()
    let folderURL: URL
    let jsonURL: URL
    let usdzURL: URL
    let kind: String

    var shareItems: [Any] { [jsonURL, usdzURL] }
}

private struct MultiRoomScanManifest: Codable {
    let schemaVersion: Int
    let createdAt: Date
    let updatedAt: Date
    let roomCount: Int
    let isFinished: Bool
    let coordinateSpace: String
}

@MainActor
final class RoomScanViewModel: NSObject, ObservableObject, @preconcurrency RoomCaptureViewDelegate {
    // A single ARSession is intentionally reused across every individual room scan.
    // This keeps all CapturedRoom results in one common world coordinate system.
    let sharedARSession = ARSession()

    @Published private(set) var isScanning = false
    @Published private(set) var isProcessing = false
    @Published private(set) var isBuildingFinished = false
    @Published private(set) var activeRoomNumber = 0

    /// The last finalized room, kept for the existing metrics and room export controls.
    @Published private(set) var capturedRoom: CapturedRoom?

    /// Frozen value-type results. Later scans never replace or mutate previous entries.
    @Published private(set) var capturedRooms: [CapturedRoom] = []
    @Published private(set) var capturedStructure: CapturedStructure?

    @Published private(set) var latestExport: RoomScanExport?
    @Published private(set) var buildingFolderURL: URL?
    @Published private(set) var statusMessage = "ابدأ مسح المبنى، وامسح كل غرفة منفصلة."
    @Published private(set) var errorMessage: String?

    private weak var captureView: RoomCaptureView?
    private var pendingStart = false
    private var shouldAcceptNextProcessedRoom = false
    private var scanCreatedAt = Date()

    override init() {
        super.init()
    }

    required init?(coder: NSCoder) {
        super.init()
    }

    func encode(with coder: NSCoder) {
        // The view model owns live AR and RoomPlan state only.
    }

    var roomCount: Int { capturedRooms.count }
    var nextRoomNumber: Int { capturedRooms.count + 1 }
    var wallCount: Int { capturedRoom?.walls.count ?? 0 }
    var doorCount: Int { capturedRoom?.doors.count ?? 0 }
    var windowCount: Int { capturedRoom?.windows.count ?? 0 }
    var openingCount: Int { capturedRoom?.openings.count ?? 0 }
    var objectCount: Int { capturedRoom?.objects.count ?? 0 }

    var totalWallCount: Int { capturedRooms.reduce(0) { $0 + $1.walls.count } }
    var totalDoorCount: Int { capturedRooms.reduce(0) { $0 + $1.doors.count } }
    var totalWindowCount: Int { capturedRooms.reduce(0) { $0 + $1.windows.count } }

    var canStartNextRoom: Bool {
        !isScanning && !isProcessing && !isBuildingFinished && !capturedRooms.isEmpty
    }

    var canFinishBuilding: Bool {
        !isScanning && !isProcessing && !isBuildingFinished && !capturedRooms.isEmpty
    }

    func attach(to view: RoomCaptureView) {
        captureView = view
        view.delegate = self

        if pendingStart {
            pendingStart = false
            startBuildingScan()
        }
    }

    /// Starts a fresh building workflow and immediately begins room 1.
    func startBuildingScan() {
        guard RoomCaptureSession.isSupported else {
            errorMessage = "RoomPlan غير مدعوم على هذا الجهاز."
            return
        }
        guard captureView != nil else {
            pendingStart = true
            return
        }

        resetPublishedResults()
        scanCreatedAt = Date()
        prepareBuildingFolder()
        startNextRoomScan()
    }

    /// Starts another independent RoomPlan scan while preserving the shared ARSession.
    func startNextRoomScan() {
        guard RoomCaptureSession.isSupported else {
            errorMessage = "RoomPlan غير مدعوم على هذا الجهاز."
            return
        }
        guard !isScanning, !isProcessing, !isBuildingFinished else { return }
        guard let captureView else {
            pendingStart = true
            return
        }

        latestExport = nil
        capturedStructure = nil
        activeRoomNumber = capturedRooms.count + 1
        shouldAcceptNextProcessedRoom = false
        statusMessage = "امسح الغرفة رقم \(activeRoomNumber) فقط. قبل عبور أي باب اضغط «إنهاء الغرفة»."

        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
        isScanning = true
    }

    /// Finalizes only the current room. The underlying ARSession remains alive so the
    /// following room stays in the same world coordinate system.
    func finishCurrentRoom() {
        guard isScanning else { return }
        isScanning = false
        isProcessing = true
        shouldAcceptNextProcessedRoom = true
        statusMessage = "جارٍ تثبيت الغرفة رقم \(activeRoomNumber) بدون إيقاف تتبع المكان…"
        captureView?.captureSession.stop(pauseARSession: false)
    }

    /// Ends the multi-room workflow, pauses AR tracking, and creates a comparison merge.
    /// The original frozen rooms remain the source of truth even after StructureBuilder runs.
    func finishBuilding() {
        guard canFinishBuilding else { return }

        sharedARSession.pause()
        isBuildingFinished = true

        guard capturedRooms.count > 1 else {
            statusMessage = "انتهى المسح بغرفة واحدة. تم حفظ الغرفة كما هي."
            writeManifest()
            return
        }

        isProcessing = true
        statusMessage = "جارٍ إنشاء نموذج مجمّع للمقارنة مع الغرف المجمدة…"
        let frozenRooms = capturedRooms

        Task {
            do {
                let builder = StructureBuilder(options: [])
                let structure = try await builder.capturedStructure(from: frozenRooms)
                capturedStructure = structure
                isProcessing = false
                statusMessage = "تم إنهاء المبنى: \(capturedRooms.count) غرف مجمدة + نموذج مجمّع للمقارنة."
                persistStructureJSON(structure)
                writeManifest()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                isProcessing = false
                errorMessage = "تم حفظ الغرف منفصلة، لكن تعذر دمجها: \(error.localizedDescription)"
                statusMessage = "الغرف المجمدة سليمة، وفشل النموذج المجمّع فقط."
                writeManifest()
            }
        }
    }

    func resetBuilding() {
        shouldAcceptNextProcessedRoom = false
        pendingStart = false

        if isScanning {
            captureView?.captureSession.stop(pauseARSession: true)
        } else {
            sharedARSession.pause()
        }

        resetPublishedResults()
        buildingFolderURL = nil
        statusMessage = "ابدأ مسح المبنى، وامسح كل غرفة منفصلة."
    }

    func stopWithoutProcessing() {
        shouldAcceptNextProcessedRoom = false
        pendingStart = false
        isScanning = false
        isProcessing = false
        captureView?.captureSession.stop(pauseARSession: true)
        sharedARSession.pause()
    }

    func exportLatestRoomParametric() {
        exportLatestRoom(options: .parametric, kind: "Room-Parametric")
    }

    func exportLatestRoomMesh() {
        exportLatestRoom(options: .mesh, kind: "Room-Mesh")
    }

    func exportMergedStructure() {
        guard let capturedStructure else {
            errorMessage = "أنهِ مسح غرفتين على الأقل وانتظر اكتمال الدمج أولًا."
            return
        }

        do {
            let folder = try makeExportFolder(name: "Merged-Structure")
            let jsonURL = folder.appendingPathComponent("structure.json")
            let usdzURL = folder.appendingPathComponent("structure.usdz")
            let encoder = configuredEncoder()
            try encoder.encode(capturedStructure).write(to: jsonURL, options: .atomic)
            try capturedStructure.export(to: usdzURL)

            latestExport = RoomScanExport(
                folderURL: folder,
                jsonURL: jsonURL,
                usdzURL: usdzURL,
                kind: "Merged-Structure"
            )
            statusMessage = "تم تصدير النموذج المجمّع. الغرف الأصلية ما زالت محفوظة منفصلة."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        guard shouldAcceptNextProcessedRoom else {
            isProcessing = false
            return false
        }

        if let error {
            shouldAcceptNextProcessedRoom = false
            isProcessing = false
            errorMessage = error.localizedDescription
            statusMessage = "حدث خطأ أثناء تثبيت الغرفة."
            return false
        }

        isScanning = false
        isProcessing = true
        statusMessage = "جارٍ إنشاء النتيجة النهائية للغرفة رقم \(activeRoomNumber)…"
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        guard shouldAcceptNextProcessedRoom else { return }
        shouldAcceptNextProcessedRoom = false
        isProcessing = false

        if let error {
            errorMessage = error.localizedDescription
            statusMessage = "تعذر معالجة الغرفة رقم \(activeRoomNumber)."
            return
        }

        // CapturedRoom is a value result. Appending it freezes this scan independently
        // from all later RoomPlan sessions.
        capturedRooms.append(processedResult)
        capturedRoom = processedResult
        activeRoomNumber = 0
        persistFrozenRoom(processedResult, index: capturedRooms.count)
        writeManifest()

        statusMessage = "تم تثبيت الغرفة رقم \(capturedRooms.count). تحرك نحو الباب ثم ابدأ الغرفة التالية."
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Persistence and export

    private func resetPublishedResults() {
        isScanning = false
        isProcessing = false
        isBuildingFinished = false
        activeRoomNumber = 0
        capturedRoom = nil
        capturedRooms = []
        capturedStructure = nil
        latestExport = nil
        shouldAcceptNextProcessedRoom = false
    }

    private func prepareBuildingFolder() {
        do {
            let storage = LiDARLabStorage.shared
            try storage.ensureDirectories()
            let folderName = storage.timestampedName(prefix: "MultiRoom")
            let folder = storage.roomsURL.appendingPathComponent(folderName, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent("FrozenRooms", isDirectory: true),
                withIntermediateDirectories: true
            )
            buildingFolderURL = folder
            writeManifest()
        } catch {
            buildingFolderURL = nil
            errorMessage = "سيعمل المسح، لكن تعذر إنشاء مجلد الحفظ: \(error.localizedDescription)"
        }
    }

    private func persistFrozenRoom(_ room: CapturedRoom, index: Int) {
        guard let buildingFolderURL else { return }

        do {
            let roomFolder = buildingFolderURL
                .appendingPathComponent("FrozenRooms", isDirectory: true)
                .appendingPathComponent(String(format: "Room-%02d", index), isDirectory: true)
            try FileManager.default.createDirectory(at: roomFolder, withIntermediateDirectories: true)

            let jsonURL = roomFolder.appendingPathComponent("room.json")
            try configuredEncoder().encode(room).write(to: jsonURL, options: .atomic)
        } catch {
            errorMessage = "تم تثبيت الغرفة داخل الجلسة، لكن تعذر حفظ JSON: \(error.localizedDescription)"
        }
    }

    private func persistStructureJSON(_ structure: CapturedStructure) {
        guard let buildingFolderURL else { return }

        do {
            let jsonURL = buildingFolderURL.appendingPathComponent("structure.json")
            try configuredEncoder().encode(structure).write(to: jsonURL, options: .atomic)
        } catch {
            errorMessage = "اكتمل الدمج، لكن تعذر حفظ structure.json: \(error.localizedDescription)"
        }
    }

    private func writeManifest() {
        guard let buildingFolderURL else { return }

        do {
            let manifest = MultiRoomScanManifest(
                schemaVersion: 1,
                createdAt: scanCreatedAt,
                updatedAt: Date(),
                roomCount: capturedRooms.count,
                isFinished: isBuildingFinished,
                coordinateSpace: "continuous-shared-ARSession"
            )
            let url = buildingFolderURL.appendingPathComponent("manifest.json")
            try configuredEncoder().encode(manifest).write(to: url, options: .atomic)
        } catch {
            // Manifest failure must not interrupt or invalidate a room scan.
        }
    }

    private func exportLatestRoom(options: CapturedRoom.USDExportOptions, kind: String) {
        guard let capturedRoom else {
            errorMessage = "أنهِ مسح غرفة واحدة على الأقل أولًا."
            return
        }

        do {
            let folder = try makeExportFolder(name: kind)
            let jsonURL = folder.appendingPathComponent("room.json")
            let usdzURL = folder.appendingPathComponent("room.usdz")
            try configuredEncoder().encode(capturedRoom).write(to: jsonURL, options: .atomic)
            try capturedRoom.export(to: usdzURL, exportOptions: options)

            latestExport = RoomScanExport(
                folderURL: folder,
                jsonURL: jsonURL,
                usdzURL: usdzURL,
                kind: kind
            )
            statusMessage = "تم تصدير آخر غرفة بنمط \(kind)."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeExportFolder(name: String) throws -> URL {
        let storage = LiDARLabStorage.shared
        try storage.ensureDirectories()
        let folderName = storage.timestampedName(prefix: name)
        let folder = storage.roomsURL.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func configuredEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

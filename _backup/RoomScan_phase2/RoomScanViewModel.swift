import ARKit
import Combine
import RoomPlan
import simd
import UIKit

struct RoomScanExport: Identifiable {
    let id = UUID()
    let folderURL: URL
    let jsonURL: URL
    let usdzURL: URL
    let metadataURL: URL?
    let kind: String

    var shareItems: [Any] {
        var items: [Any] = [jsonURL, usdzURL]
        if let metadataURL {
            items.append(metadataURL)
        }
        return items
    }
}

private struct MultiRoomScanManifest: Codable {
    let schemaVersion: Int
    let createdAt: Date
    let updatedAt: Date
    let roomCount: Int
    let isFinished: Bool
    let coordinateSpace: String
    let buildingDefaultWallThicknessMeters: Double
    let physicalWallCount: Int
    let sharedPhysicalWallCount: Int
    let wallMetadataFile: String
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

    /// App-owned wall metadata. RoomPlan geometry is never rewritten.
    @Published private(set) var buildingDefaultWallThicknessMeters = 0.15
    @Published private(set) var roomWallConfigurations: [RoomWallConfiguration] = []
    @Published private(set) var buildingWallRecords: [BuildingWallRecord] = []
    @Published private(set) var roomWallAssignments: [RoomWallAssignment] = []

    @Published private(set) var latestExport: RoomScanExport?
    @Published private(set) var buildingFolderURL: URL?
    @Published private(set) var statusMessage = "ابدأ مسح المبنى، وامسح كل غرفة منفصلة."
    @Published private(set) var errorMessage: String?

    private weak var captureView: RoomCaptureView?
    private var pendingStartRequest: PendingStartRequest?
    private var shouldAcceptNextProcessedRoom = false
    private var activeRoomDefaultThicknessMeters = 0.15
    private var scanCreatedAt = Date()

    private enum PendingStartRequest {
        case building(defaultThicknessCentimeters: Double)
        case room(defaultThicknessCentimeters: Double)
    }

    private struct SharedWallMatch {
        let assignment: RoomWallAssignment
        let confidence: Double
        let faceSeparationMeters: Double
    }

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

    var buildingDefaultWallThicknessCentimeters: Double {
        buildingDefaultWallThicknessMeters * 100.0
    }

    var recommendedNextRoomThicknessCentimeters: Double {
        (roomWallConfigurations.last?.defaultThicknessMeters ?? buildingDefaultWallThicknessMeters) * 100.0
    }

    var physicalWallCount: Int { buildingWallRecords.count }

    var sharedPhysicalWallCount: Int {
        assignmentCountsByBuildingWallID.values.filter { $0 > 1 }.count
    }

    var latestRoomSharedFaceCount: Int {
        guard roomCount > 0 else { return 0 }
        return wallItems(for: roomCount).filter(\.isShared).count
    }

    var canStartNextRoom: Bool {
        !isScanning && !isProcessing && !isBuildingFinished && !capturedRooms.isEmpty
    }

    var canFinishBuilding: Bool {
        !isScanning && !isProcessing && !isBuildingFinished && !capturedRooms.isEmpty
    }

    func attach(to view: RoomCaptureView) {
        captureView = view
        view.delegate = self

        guard let request = pendingStartRequest else { return }
        pendingStartRequest = nil

        switch request {
        case .building(let centimeters):
            startBuildingScan(defaultWallThicknessCentimeters: centimeters)
        case .room(let centimeters):
            startNextRoomScan(defaultWallThicknessCentimeters: centimeters)
        }
    }

    /// Starts a fresh building workflow and immediately begins room 1.
    func startBuildingScan(defaultWallThicknessCentimeters: Double) {
        guard RoomCaptureSession.isSupported else {
            errorMessage = "RoomPlan غير مدعوم على هذا الجهاز."
            return
        }
        guard captureView != nil else {
            pendingStartRequest = .building(defaultThicknessCentimeters: defaultWallThicknessCentimeters)
            return
        }

        resetPublishedResults()
        buildingDefaultWallThicknessMeters = validatedThicknessMeters(fromCentimeters: defaultWallThicknessCentimeters)
        scanCreatedAt = Date()
        prepareBuildingFolder()
        beginRoomScan(defaultThicknessMeters: buildingDefaultWallThicknessMeters)
    }

    /// Starts another independent RoomPlan scan while preserving the shared ARSession.
    func startNextRoomScan(defaultWallThicknessCentimeters: Double) {
        guard RoomCaptureSession.isSupported else {
            errorMessage = "RoomPlan غير مدعوم على هذا الجهاز."
            return
        }
        guard !isScanning, !isProcessing, !isBuildingFinished else { return }
        guard captureView != nil else {
            pendingStartRequest = .room(defaultThicknessCentimeters: defaultWallThicknessCentimeters)
            return
        }

        let thicknessMeters = validatedThicknessMeters(fromCentimeters: defaultWallThicknessCentimeters)
        beginRoomScan(defaultThicknessMeters: thicknessMeters)
    }

    private func beginRoomScan(defaultThicknessMeters: Double) {
        guard let captureView else { return }

        latestExport = nil
        capturedStructure = nil
        activeRoomNumber = capturedRooms.count + 1
        activeRoomDefaultThicknessMeters = defaultThicknessMeters
        shouldAcceptNextProcessedRoom = false

        let thicknessText = centimetersText(defaultThicknessMeters * 100.0)
        statusMessage = "امسح الغرفة رقم \(activeRoomNumber) فقط. سماكة الجدران الجديدة \(thicknessText) سم، والمشتركة ترث قيمتها السابقة."

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
        statusMessage = "جارٍ تثبيت الغرفة رقم \(activeRoomNumber) وربط حوائطها المشتركة…"
        captureView?.captureSession.stop(pauseARSession: false)
    }

    /// Ends the multi-room workflow, pauses AR tracking, and creates a comparison merge.
    /// The original frozen rooms remain the source of truth even after StructureBuilder runs.
    func finishBuilding() {
        guard canFinishBuilding else { return }

        sharedARSession.pause()
        isBuildingFinished = true

        guard capturedRooms.count > 1 else {
            statusMessage = "انتهى المسح بغرفة واحدة. تم حفظ الغرفة وسماكات حوائطها كما هي."
            persistWallMetadata()
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
                statusMessage = "تم إنهاء المبنى: \(capturedRooms.count) غرف، و\(sharedPhysicalWallCount) حوائط مشتركة."
                persistStructureJSON(structure)
                persistWallMetadata()
                writeManifest()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                isProcessing = false
                errorMessage = "تم حفظ الغرف والسماكات منفصلة، لكن تعذر دمج RoomPlan: \(error.localizedDescription)"
                statusMessage = "الغرف وبيانات الحوائط سليمة، وفشل النموذج المجمّع فقط."
                persistWallMetadata()
                writeManifest()
            }
        }
    }

    func resetBuilding() {
        shouldAcceptNextProcessedRoom = false
        pendingStartRequest = nil

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
        pendingStartRequest = nil
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

            let metadataURL = folder.appendingPathComponent("wall-metadata.json")
            let wallDocument = BuildingWallMetadataDocument(
                schemaVersion: 1,
                updatedAt: Date(),
                buildingDefaultThicknessMeters: buildingDefaultWallThicknessMeters,
                roomConfigurations: roomWallConfigurations,
                wallRecords: buildingWallRecords,
                assignments: roomWallAssignments
            )
            try configuredEncoder().encode(wallDocument).write(to: metadataURL, options: .atomic)

            latestExport = RoomScanExport(
                folderURL: folder,
                jsonURL: jsonURL,
                usdzURL: usdzURL,
                metadataURL: metadataURL,
                kind: "Merged-Structure"
            )
            statusMessage = "تم تصدير النموذج المجمّع. الغرف وبيانات السماكات ما زالت محفوظة منفصلة."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Wall thickness metadata

    func wallItems(for roomIndex: Int) -> [RoomWallDisplayItem] {
        let recordsByID = Dictionary(uniqueKeysWithValues: buildingWallRecords.map { ($0.id, $0) })
        let counts = assignmentCountsByBuildingWallID

        return roomWallAssignments
            .filter { $0.roomIndex == roomIndex }
            .sorted { $0.wallNumber < $1.wallNumber }
            .compactMap { assignment in
                guard let record = recordsByID[assignment.buildingWallID] else { return nil }
                let displaySource: WallThicknessSource = record.source == .userConfirmed
                    ? .userConfirmed
                    : assignment.assignmentSource

                return RoomWallDisplayItem(
                    id: assignment.id,
                    roomIndex: assignment.roomIndex,
                    wallNumber: assignment.wallNumber,
                    wallIdentifier: assignment.wallIdentifier,
                    buildingWallID: assignment.buildingWallID,
                    thicknessCentimeters: record.thicknessMeters * 100.0,
                    source: displaySource,
                    isShared: (counts[assignment.buildingWallID] ?? 0) > 1,
                    matchConfidence: assignment.matchConfidence,
                    faceSeparationCentimeters: assignment.faceSeparationMeters.map { $0 * 100.0 }
                )
            }
    }

    func updateWallThickness(buildingWallID: UUID, centimeters: Double) {
        guard let index = buildingWallRecords.firstIndex(where: { $0.id == buildingWallID }) else { return }

        buildingWallRecords[index].thicknessMeters = validatedThicknessMeters(fromCentimeters: centimeters)
        buildingWallRecords[index].source = .userConfirmed
        buildingWallRecords[index].updatedAt = Date()

        persistWallMetadata()
        persistRoomWallMetadataFilesForWall(buildingWallID)
        writeManifest()
    }

    func applyThicknessToUnsharedWalls(roomIndex: Int, centimeters: Double) {
        let counts = assignmentCountsByBuildingWallID
        let wallIDs = Set(
            roomWallAssignments
                .filter { $0.roomIndex == roomIndex && (counts[$0.buildingWallID] ?? 0) == 1 }
                .map(\.buildingWallID)
        )

        guard !wallIDs.isEmpty else { return }
        let meters = validatedThicknessMeters(fromCentimeters: centimeters)
        let now = Date()

        for index in buildingWallRecords.indices where wallIDs.contains(buildingWallRecords[index].id) {
            buildingWallRecords[index].thicknessMeters = meters
            buildingWallRecords[index].source = .userConfirmed
            buildingWallRecords[index].updatedAt = now
        }

        persistWallMetadata()
        persistRoomWallMetadata(roomIndex: roomIndex)
        writeManifest()
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
        let finalizedRoomIndex = capturedRooms.count

        registerWallMetadata(
            for: processedResult,
            roomIndex: finalizedRoomIndex,
            defaultThicknessMeters: activeRoomDefaultThicknessMeters
        )

        activeRoomNumber = 0
        persistFrozenRoom(processedResult, index: finalizedRoomIndex)
        persistWallMetadata()
        persistRoomWallMetadata(roomIndex: finalizedRoomIndex)
        writeManifest()

        let sharedCount = wallItems(for: finalizedRoomIndex).filter(\.isShared).count
        if sharedCount > 0 {
            statusMessage = "تم تثبيت الغرفة رقم \(finalizedRoomIndex)، وربط \(sharedCount) وجه حائط بحوائط الغرف السابقة."
        } else {
            statusMessage = "تم تثبيت الغرفة رقم \(finalizedRoomIndex). لم يُعثر على حائط مشترك مؤكد تلقائيًا."
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Wall matching

    private func registerWallMetadata(
        for room: CapturedRoom,
        roomIndex: Int,
        defaultThicknessMeters: Double
    ) {
        roomWallConfigurations.append(
            RoomWallConfiguration(
                roomIndex: roomIndex,
                roomIdentifier: room.identifier,
                defaultThicknessMeters: defaultThicknessMeters,
                confirmedAt: Date()
            )
        )

        for (wallOffset, wall) in room.walls.enumerated() {
            let geometry = geometrySnapshot(for: wall)
            let match = bestSharedWallMatch(
                for: geometry,
                currentRoomIndex: roomIndex
            )

            let buildingWallID: UUID
            let source: WallThicknessSource
            let matchedWallIdentifier: UUID?
            let confidence: Double?
            let separation: Double?

            if let match {
                buildingWallID = match.assignment.buildingWallID
                source = .inheritedSharedWall
                matchedWallIdentifier = match.assignment.wallIdentifier
                confidence = match.confidence
                separation = match.faceSeparationMeters
            } else {
                let record = BuildingWallRecord(
                    id: UUID(),
                    thicknessMeters: defaultThicknessMeters,
                    source: roomIndex == 1 ? .buildingDefault : .roomDefault,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                buildingWallRecords.append(record)
                buildingWallID = record.id
                source = roomIndex == 1 ? .buildingDefault : .roomDefault
                matchedWallIdentifier = nil
                confidence = nil
                separation = nil
            }

            roomWallAssignments.append(
                RoomWallAssignment(
                    id: UUID(),
                    roomIndex: roomIndex,
                    roomIdentifier: room.identifier,
                    wallIdentifier: wall.identifier,
                    wallNumber: wallOffset + 1,
                    buildingWallID: buildingWallID,
                    geometry: geometry,
                    assignmentSource: source,
                    matchedPreviousWallIdentifier: matchedWallIdentifier,
                    matchConfidence: confidence,
                    faceSeparationMeters: separation
                )
            )
        }
    }

    private func bestSharedWallMatch(
        for current: RoomWallGeometrySnapshot,
        currentRoomIndex: Int
    ) -> SharedWallMatch? {
        let previousAssignments = roomWallAssignments.filter { $0.roomIndex < currentRoomIndex }
        guard !previousAssignments.isEmpty else { return nil }

        let recordsByID = Dictionary(uniqueKeysWithValues: buildingWallRecords.map { ($0.id, $0) })
        var best: SharedWallMatch?

        for previous in previousAssignments {
            guard let wallRecord = recordsByID[previous.buildingWallID] else { continue }
            guard let candidate = scoreSharedWallMatch(
                current: current,
                previous: previous.geometry,
                expectedThicknessMeters: wallRecord.thicknessMeters
            ) else { continue }

            if best == nil || candidate.confidence > best!.confidence {
                best = SharedWallMatch(
                    assignment: previous,
                    confidence: candidate.confidence,
                    faceSeparationMeters: candidate.separationMeters
                )
            }
        }

        guard let best, best.confidence >= 0.62 else { return nil }
        return best
    }

    private func scoreSharedWallMatch(
        current: RoomWallGeometrySnapshot,
        previous: RoomWallGeometrySnapshot,
        expectedThicknessMeters: Double
    ) -> (confidence: Double, separationMeters: Double)? {
        let currentTangent = normalized2D(SIMD2<Float>(current.tangentX, current.tangentZ))
        let previousTangent = normalized2D(SIMD2<Float>(previous.tangentX, previous.tangentZ))
        let currentNormal = normalized2D(SIMD2<Float>(current.normalX, current.normalZ))
        let previousNormal = normalized2D(SIMD2<Float>(previous.normalX, previous.normalZ))

        let tangentAlignment = abs(Double(simd_dot(currentTangent, previousTangent)))
        let normalAlignment = abs(Double(simd_dot(currentNormal, previousNormal)))
        guard tangentAlignment >= 0.965, normalAlignment >= 0.94 else { return nil }

        let currentCenter = SIMD2<Float>(current.centerX, current.centerZ)
        let previousCenter = SIMD2<Float>(previous.centerX, previous.centerZ)
        let delta = previousCenter - currentCenter

        let separation = abs(Double(simd_dot(delta, currentNormal)))
        guard separation <= 0.65 else { return nil }

        let axis = currentTangent
        let currentAxisCenter = Double(simd_dot(currentCenter, axis))
        let previousAxisCenter = Double(simd_dot(previousCenter, axis))
        let currentHalfWidth = Double(current.widthMeters) * 0.5
        let previousHalfWidth = Double(previous.widthMeters) * 0.5 * tangentAlignment

        let overlapStart = max(currentAxisCenter - currentHalfWidth, previousAxisCenter - previousHalfWidth)
        let overlapEnd = min(currentAxisCenter + currentHalfWidth, previousAxisCenter + previousHalfWidth)
        let horizontalOverlap = max(0.0, overlapEnd - overlapStart)
        let shorterWidth = max(0.01, min(Double(current.widthMeters), Double(previous.widthMeters)))
        let horizontalOverlapRatio = horizontalOverlap / shorterWidth
        guard horizontalOverlap >= 0.40, horizontalOverlapRatio >= 0.28 else { return nil }

        let currentBottom = Double(current.centerY) - Double(current.heightMeters) * 0.5
        let currentTop = Double(current.centerY) + Double(current.heightMeters) * 0.5
        let previousBottom = Double(previous.centerY) - Double(previous.heightMeters) * 0.5
        let previousTop = Double(previous.centerY) + Double(previous.heightMeters) * 0.5
        let verticalOverlap = max(0.0, min(currentTop, previousTop) - max(currentBottom, previousBottom))
        let shorterHeight = max(0.01, min(Double(current.heightMeters), Double(previous.heightMeters)))
        let verticalOverlapRatio = verticalOverlap / shorterHeight
        guard verticalOverlap >= 0.80, verticalOverlapRatio >= 0.25 else { return nil }

        let expected = max(0.05, expectedThicknessMeters)
        let thicknessError = abs(separation - expected)
        let thicknessScore = max(0.0, 1.0 - thicknessError / 0.35)
        let angleScore = min(tangentAlignment, normalAlignment)
        let overlapScore = min(1.0, horizontalOverlapRatio)
        let heightScore = min(1.0, verticalOverlapRatio)

        let confidence = (
            angleScore * 0.34
            + overlapScore * 0.34
            + heightScore * 0.17
            + thicknessScore * 0.15
        )

        return (confidence, separation)
    }

    private func geometrySnapshot(for wall: CapturedRoom.Surface) -> RoomWallGeometrySnapshot {
        let transform = wall.transform
        let center = transform.columns.3

        var tangent = normalized2D(SIMD2<Float>(transform.columns.0.x, transform.columns.0.z))
        var normal = normalized2D(SIMD2<Float>(transform.columns.2.x, transform.columns.2.z))

        if simd_length(tangent) < 0.5 {
            tangent = SIMD2<Float>(1, 0)
        }
        if simd_length(normal) < 0.5 || abs(simd_dot(tangent, normal)) > 0.35 {
            normal = SIMD2<Float>(-tangent.y, tangent.x)
        }

        return RoomWallGeometrySnapshot(
            centerX: center.x,
            centerY: center.y,
            centerZ: center.z,
            tangentX: tangent.x,
            tangentZ: tangent.y,
            normalX: normal.x,
            normalZ: normal.y,
            widthMeters: max(0.05, wall.dimensions.x),
            heightMeters: max(0.05, wall.dimensions.y)
        )
    }

    private func normalized2D(_ value: SIMD2<Float>) -> SIMD2<Float> {
        let length = simd_length(value)
        guard length > 0.0001 else { return SIMD2<Float>(0, 0) }
        return value / length
    }

    private var assignmentCountsByBuildingWallID: [UUID: Int] {
        Dictionary(grouping: roomWallAssignments, by: \.buildingWallID)
            .mapValues(\.count)
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
        roomWallConfigurations = []
        buildingWallRecords = []
        roomWallAssignments = []
        latestExport = nil
        shouldAcceptNextProcessedRoom = false
        activeRoomDefaultThicknessMeters = buildingDefaultWallThicknessMeters
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
            persistWallMetadata()
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

    private func persistWallMetadata() {
        guard let buildingFolderURL else { return }

        let document = BuildingWallMetadataDocument(
            schemaVersion: 1,
            updatedAt: Date(),
            buildingDefaultThicknessMeters: buildingDefaultWallThicknessMeters,
            roomConfigurations: roomWallConfigurations,
            wallRecords: buildingWallRecords,
            assignments: roomWallAssignments
        )

        do {
            let url = buildingFolderURL.appendingPathComponent("wall-metadata.json")
            try configuredEncoder().encode(document).write(to: url, options: .atomic)
        } catch {
            errorMessage = "تم حفظ الغرفة، لكن تعذر حفظ بيانات سماكات الحوائط: \(error.localizedDescription)"
        }
    }

    private func persistRoomWallMetadata(roomIndex: Int) {
        guard let buildingFolderURL else { return }
        guard let roomConfiguration = roomWallConfigurations.first(where: { $0.roomIndex == roomIndex }) else { return }

        let assignments = roomWallAssignments.filter { $0.roomIndex == roomIndex }
        let referencedIDs = Set(assignments.map(\.buildingWallID))
        let records = buildingWallRecords.filter { referencedIDs.contains($0.id) }
        let document = BuildingWallMetadataDocument(
            schemaVersion: 1,
            updatedAt: Date(),
            buildingDefaultThicknessMeters: buildingDefaultWallThicknessMeters,
            roomConfigurations: [roomConfiguration],
            wallRecords: records,
            assignments: assignments
        )

        do {
            let roomFolder = buildingFolderURL
                .appendingPathComponent("FrozenRooms", isDirectory: true)
                .appendingPathComponent(String(format: "Room-%02d", roomIndex), isDirectory: true)
            try FileManager.default.createDirectory(at: roomFolder, withIntermediateDirectories: true)
            let url = roomFolder.appendingPathComponent("wall-properties.json")
            try configuredEncoder().encode(document).write(to: url, options: .atomic)
        } catch {
            errorMessage = "تعذر تحديث ملف سماكات الغرفة رقم \(roomIndex): \(error.localizedDescription)"
        }
    }

    private func persistRoomWallMetadataFilesForWall(_ buildingWallID: UUID) {
        let roomIndices = Set(
            roomWallAssignments
                .filter { $0.buildingWallID == buildingWallID }
                .map(\.roomIndex)
        )
        for roomIndex in roomIndices {
            persistRoomWallMetadata(roomIndex: roomIndex)
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
                schemaVersion: 2,
                createdAt: scanCreatedAt,
                updatedAt: Date(),
                roomCount: capturedRooms.count,
                isFinished: isBuildingFinished,
                coordinateSpace: "continuous-shared-ARSession",
                buildingDefaultWallThicknessMeters: buildingDefaultWallThicknessMeters,
                physicalWallCount: physicalWallCount,
                sharedPhysicalWallCount: sharedPhysicalWallCount,
                wallMetadataFile: "wall-metadata.json"
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

            var wallMetadataURL: URL?
            if roomCount > 0 {
                let assignments = roomWallAssignments.filter { $0.roomIndex == roomCount }
                let referencedIDs = Set(assignments.map(\.buildingWallID))
                let wallDocument = BuildingWallMetadataDocument(
                    schemaVersion: 1,
                    updatedAt: Date(),
                    buildingDefaultThicknessMeters: buildingDefaultWallThicknessMeters,
                    roomConfigurations: roomWallConfigurations.filter { $0.roomIndex == roomCount },
                    wallRecords: buildingWallRecords.filter { referencedIDs.contains($0.id) },
                    assignments: assignments
                )
                let wallURL = folder.appendingPathComponent("wall-properties.json")
                try configuredEncoder().encode(wallDocument).write(to: wallURL, options: .atomic)
                wallMetadataURL = wallURL
            }

            latestExport = RoomScanExport(
                folderURL: folder,
                jsonURL: jsonURL,
                usdzURL: usdzURL,
                metadataURL: wallMetadataURL,
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

    private func validatedThicknessMeters(fromCentimeters centimeters: Double) -> Double {
        min(max(centimeters, 5.0), 60.0) / 100.0
    }

    private func centimetersText(_ centimeters: Double) -> String {
        if abs(centimeters.rounded() - centimeters) < 0.05 {
            return String(Int(centimeters.rounded()))
        }
        return String(format: "%.1f", centimeters)
    }
}

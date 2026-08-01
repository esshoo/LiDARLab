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
    let fragmentCount: Int
    let isFinished: Bool
    let isPaused: Bool
    let activeRoomNumber: Int
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
    @Published private(set) var isPaused = false
    @Published private(set) var isProcessing = false
    @Published private(set) var isBuildingFinished = false
    @Published private(set) var activeRoomNumber = 0
    @Published private(set) var activeRoomFragmentCount = 0

    /// The last finalized room, kept for the existing metrics and room export controls.
    @Published private(set) var capturedRoom: CapturedRoom?

    /// Frozen value-type results. Later scans never replace or mutate previous entries.
    @Published private(set) var capturedRooms: [CapturedRoom] = []
    @Published private(set) var capturedStructure: CapturedStructure?
    @Published private(set) var fragmentMetadata: [RoomScanFragmentMetadata] = []

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
    private var pendingStopAction: PendingStopAction?
    private var activeRoomDefaultThicknessMeters = 0.15
    private var scanCreatedAt = Date()
    private var capturedFragments: [CapturedFragment] = []

    private enum PendingStartRequest {
        case building(defaultThicknessCentimeters: Double)
        case room(defaultThicknessCentimeters: Double)
    }

    private enum PendingStopAction: Equatable {
        case pauseRoom
        case finalizeRoom
    }

    private struct CapturedFragment {
        let metadata: RoomScanFragmentMetadata
        let room: CapturedRoom
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

    var totalFragmentCount: Int { fragmentMetadata.count }

    var physicalWallCount: Int { buildingWallRecords.count }

    var sharedPhysicalWallCount: Int {
        distinctRoomCountsByBuildingWallID.values.filter { $0 > 1 }.count
    }

    var latestRoomSharedFaceCount: Int {
        guard roomCount > 0 else { return 0 }
        return wallItems(for: roomCount).filter(\.isShared).count
    }

    var canStartNextRoom: Bool {
        !isScanning && !isPaused && !isProcessing && !isBuildingFinished && !capturedRooms.isEmpty
    }

    var canFinishBuilding: Bool {
        !isScanning && !isPaused && !isProcessing && !isBuildingFinished && !capturedRooms.isEmpty
    }

    var canPauseCurrentRoom: Bool {
        isScanning && !isProcessing
    }

    var canResumePausedRoom: Bool {
        isPaused && !isScanning && !isProcessing && activeRoomNumber > 0
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
        beginRoomFragment(
            roomNumber: 1,
            defaultThicknessMeters: buildingDefaultWallThicknessMeters,
            isResume: false
        )
    }

    /// Starts another independent logical room while preserving the shared ARSession.
    func startNextRoomScan(defaultWallThicknessCentimeters: Double) {
        guard RoomCaptureSession.isSupported else {
            errorMessage = "RoomPlan غير مدعوم على هذا الجهاز."
            return
        }
        guard !isScanning, !isPaused, !isProcessing, !isBuildingFinished else { return }
        guard captureView != nil else {
            pendingStartRequest = .room(defaultThicknessCentimeters: defaultWallThicknessCentimeters)
            return
        }

        let thicknessMeters = validatedThicknessMeters(fromCentimeters: defaultWallThicknessCentimeters)
        beginRoomFragment(
            roomNumber: capturedRooms.count + 1,
            defaultThicknessMeters: thicknessMeters,
            isResume: false
        )
    }

    private func beginRoomFragment(
        roomNumber: Int,
        defaultThicknessMeters: Double,
        isResume: Bool
    ) {
        guard let captureView else { return }

        latestExport = nil
        capturedStructure = nil
        activeRoomNumber = roomNumber
        activeRoomDefaultThicknessMeters = defaultThicknessMeters
        activeRoomFragmentCount = fragmentMetadata.filter { $0.roomIndex == roomNumber }.count
        shouldAcceptNextProcessedRoom = false
        pendingStopAction = nil
        isPaused = false

        let nextFragment = activeRoomFragmentCount + 1
        let thicknessText = centimetersText(defaultThicknessMeters * 100.0)
        if isResume {
            statusMessage = "استكمال الغرفة رقم \(roomNumber)، الجزء \(nextFragment). وجّه الهاتف إلى مكان معروف ثم تحرك ببطء."
        } else {
            statusMessage = "امسح الغرفة رقم \(roomNumber) فقط. سماكة الجدران الجديدة \(thicknessText) سم، والمشتركة ترث قيمتها السابقة."
        }

        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
        isScanning = true
        persistSessionCheckpoint()
    }

    /// Stops the current partial capture and asks RoomPlan to pause the shared ARSession.
    /// Resuming starts a new RoomPlan fragment that belongs to the same logical room.
    func pauseCurrentRoom() {
        guard canPauseCurrentRoom else { return }
        isScanning = false
        isProcessing = true
        shouldAcceptNextProcessedRoom = true
        pendingStopAction = .pauseRoom
        statusMessage = "تم إيقاف الكاميرا، وجارٍ حفظ الجزء الحالي من الغرفة رقم \(activeRoomNumber)…"
        captureView?.captureSession.stop(pauseARSession: true)
    }

    func resumePausedRoom() {
        guard canResumePausedRoom else { return }
        let roomNumber = activeRoomNumber
        beginRoomFragment(
            roomNumber: roomNumber,
            defaultThicknessMeters: activeRoomDefaultThicknessMeters,
            isResume: true
        )
    }

    /// Finalizes only the current room. The underlying ARSession remains alive so the
    /// following room stays in the same world coordinate system.
    func finishCurrentRoom() {
        guard isScanning else { return }
        isScanning = false
        isProcessing = true
        shouldAcceptNextProcessedRoom = true
        pendingStopAction = .finalizeRoom
        statusMessage = "جارٍ تثبيت الغرفة رقم \(activeRoomNumber) وربط كل أجزائها وحوائطها المشتركة…"
        captureView?.captureSession.stop(pauseARSession: false)
    }

    /// Finalizes a paused room from its already saved fragments without reopening camera.
    func finishPausedRoom() {
        guard canResumePausedRoom else { return }
        guard capturedFragments.contains(where: { $0.metadata.roomIndex == activeRoomNumber }) else {
            errorMessage = "لا يوجد جزء محفوظ يمكن اعتماد الغرفة منه."
            return
        }

        let roomNumber = activeRoomNumber
        isPaused = false
        finalizeLogicalRoom(roomIndex: roomNumber)
        persistSessionCheckpoint()
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
            persistSessionCheckpoint()
            writeManifest()
            return
        }

        isProcessing = true
        statusMessage = "جارٍ إنشاء نموذج مجمّع للمقارنة مع الغرف المجمدة…"
        let frozenRooms = capturedFragments.isEmpty
            ? capturedRooms
            : capturedFragments.map(\.room)

        Task {
            do {
                let builder = StructureBuilder(options: [])
                let structure = try await builder.capturedStructure(from: frozenRooms)
                capturedStructure = structure
                isProcessing = false
                statusMessage = "تم إنهاء المبنى: \(capturedRooms.count) غرف، و\(sharedPhysicalWallCount) حوائط مشتركة."
                persistStructureJSON(structure)
                persistWallMetadata()
                persistSessionCheckpoint()
                writeManifest()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                isProcessing = false
                errorMessage = "تم حفظ الغرف والسماكات منفصلة، لكن تعذر دمج RoomPlan: \(error.localizedDescription)"
                statusMessage = "الغرف وبيانات الحوائط سليمة، وفشل النموذج المجمّع فقط."
                persistWallMetadata()
                persistSessionCheckpoint()
                writeManifest()
            }
        }
    }

    func resetBuilding() {
        shouldAcceptNextProcessedRoom = false
        pendingStartRequest = nil
        pendingStopAction = nil

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
        pendingStopAction = nil
        isScanning = false
        isPaused = false
        isProcessing = false
        activeRoomNumber = 0
        activeRoomFragmentCount = 0
        captureView?.captureSession.stop(pauseARSession: true)
        sharedARSession.pause()
        persistSessionCheckpoint()
        writeManifest()
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
                schemaVersion: 2,
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
        let distinctRoomCounts = distinctRoomCountsByBuildingWallID
        let groupedAssignments = Dictionary(
            grouping: roomWallAssignments.filter { $0.roomIndex == roomIndex },
            by: \.buildingWallID
        )

        return groupedAssignments.values
            .compactMap { group -> (RoomWallAssignment, BuildingWallRecord)? in
                guard let representative = group.min(by: {
                    if $0.wallNumber == $1.wallNumber {
                        return $0.fragmentIndex < $1.fragmentIndex
                    }
                    return $0.wallNumber < $1.wallNumber
                }), let record = recordsByID[representative.buildingWallID] else {
                    return nil
                }
                return (representative, record)
            }
            .sorted { $0.0.wallNumber < $1.0.wallNumber }
            .map { pair in
                let (assignment, record) = pair
                let group = groupedAssignments[assignment.buildingWallID] ?? [assignment]
                let displaySource: WallThicknessSource
                if record.source == .userConfirmed {
                    displaySource = .userConfirmed
                } else if group.contains(where: { $0.assignmentSource == .inheritedSharedWall }) {
                    displaySource = .inheritedSharedWall
                } else if group.contains(where: { $0.assignmentSource == .continuedFragment }) {
                    displaySource = .continuedFragment
                } else {
                    displaySource = assignment.assignmentSource
                }

                return RoomWallDisplayItem(
                    id: assignment.id,
                    roomIndex: assignment.roomIndex,
                    wallNumber: assignment.wallNumber,
                    wallIdentifier: assignment.wallIdentifier,
                    buildingWallID: assignment.buildingWallID,
                    thicknessCentimeters: record.thicknessMeters * 100.0,
                    source: displaySource,
                    isShared: (distinctRoomCounts[assignment.buildingWallID] ?? 0) > 1,
                    matchConfidence: group.compactMap(\.matchConfidence).max(),
                    faceSeparationCentimeters: group.compactMap(\.faceSeparationMeters).max().map { $0 * 100.0 }
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
        let counts = distinctRoomCountsByBuildingWallID
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
        guard shouldAcceptNextProcessedRoom, pendingStopAction != nil else {
            isProcessing = false
            return false
        }

        if let error {
            shouldAcceptNextProcessedRoom = false
            pendingStopAction = nil
            isProcessing = false
            sharedARSession.pause()
            isPaused = activeRoomNumber > 0
            errorMessage = error.localizedDescription
            statusMessage = "تعذر حفظ الجزء الحالي. يمكنك محاولة استكمال الغرفة من نفس المكان."
            persistSessionCheckpoint()
            writeManifest()
            return false
        }

        isScanning = false
        isProcessing = true
        let fragmentNumber = fragmentMetadata.filter { $0.roomIndex == activeRoomNumber }.count + 1
        statusMessage = "جارٍ إنشاء نتيجة الجزء \(fragmentNumber) من الغرفة رقم \(activeRoomNumber)…"
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        guard shouldAcceptNextProcessedRoom, let stopAction = pendingStopAction else { return }
        shouldAcceptNextProcessedRoom = false
        pendingStopAction = nil
        isProcessing = false

        if let error {
            sharedARSession.pause()
            isPaused = activeRoomNumber > 0
            errorMessage = error.localizedDescription
            statusMessage = "تعذر معالجة الجزء الحالي من الغرفة رقم \(activeRoomNumber). يمكنك محاولة الاستكمال من نفس المكان."
            persistSessionCheckpoint()
            writeManifest()
            return
        }

        let roomIndex = activeRoomNumber
        let fragmentIndex = fragmentMetadata.filter { $0.roomIndex == roomIndex }.count + 1
        let reason: RoomScanFragmentReason = stopAction == .pauseRoom ? .manualPause : .roomCompletion
        let metadata = makeFragmentMetadata(
            for: processedResult,
            roomIndex: roomIndex,
            fragmentIndex: fragmentIndex,
            reason: reason
        )

        capturedFragments.append(CapturedFragment(metadata: metadata, room: processedResult))
        fragmentMetadata.append(metadata)
        activeRoomFragmentCount = fragmentIndex

        registerWallMetadata(
            for: processedResult,
            roomIndex: roomIndex,
            fragmentIndex: fragmentIndex,
            defaultThicknessMeters: activeRoomDefaultThicknessMeters
        )

        persistRoomFragment(processedResult, metadata: metadata)
        persistWallMetadata()
        persistRoomWallMetadata(roomIndex: roomIndex)
        persistRoomFragmentsDocument(roomIndex: roomIndex, isFinalized: stopAction == .finalizeRoom)

        switch stopAction {
        case .pauseRoom:
            sharedARSession.pause()
            isPaused = true
            statusMessage = "تم حفظ الجزء \(fragmentIndex) من الغرفة \(roomIndex) وإغلاق الكاميرا. لا تحرك الهاتف كثيرًا قبل الاستكمال."
            persistSessionCheckpoint()
            writeManifest()
            UINotificationFeedbackGenerator().notificationOccurred(.success)

        case .finalizeRoom:
            finalizeLogicalRoom(roomIndex: roomIndex)
        }
    }

    private func finalizeLogicalRoom(roomIndex: Int) {
        let roomFragments = capturedFragments.filter { $0.metadata.roomIndex == roomIndex }
        guard let primary = roomFragments.max(by: { fragmentQualityScore($0.room) < fragmentQualityScore($1.room) }) else {
            errorMessage = "لا توجد نتيجة محفوظة لاعتماد الغرفة رقم \(roomIndex)."
            return
        }

        if capturedRooms.count < roomIndex {
            capturedRooms.append(primary.room)
        } else if roomIndex > 0 && roomIndex <= capturedRooms.count {
            capturedRooms[roomIndex - 1] = primary.room
        }
        capturedRoom = primary.room

        persistFrozenRoom(primary.room, index: roomIndex)
        persistRoomFragmentsDocument(roomIndex: roomIndex, isFinalized: true)
        persistWallMetadata()
        persistRoomWallMetadata(roomIndex: roomIndex)

        isPaused = false
        activeRoomNumber = 0
        activeRoomFragmentCount = 0
        writeManifest()
        persistSessionCheckpoint()

        let sharedCount = wallItems(for: roomIndex).filter(\.isShared).count
        let fragmentCount = roomFragments.count
        if sharedCount > 0 {
            statusMessage = "تم تثبيت الغرفة رقم \(roomIndex) من \(fragmentCount) أجزاء، وربط \(sharedCount) حائط بالغرف السابقة."
        } else {
            statusMessage = "تم تثبيت الغرفة رقم \(roomIndex) من \(fragmentCount) أجزاء. لم يُعثر على حائط مشترك مؤكد تلقائيًا."
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func fragmentQualityScore(_ room: CapturedRoom) -> Int {
        room.walls.count * 100
            + room.doors.count * 20
            + room.windows.count * 15
            + room.openings.count * 10
            + room.objects.count
    }

    private func makeFragmentMetadata(
        for room: CapturedRoom,
        roomIndex: Int,
        fragmentIndex: Int,
        reason: RoomScanFragmentReason
    ) -> RoomScanFragmentMetadata {
        let relativePath = String(
            format: "FrozenRooms/Room-%02d/Fragments/Fragment-%02d/room.json",
            roomIndex,
            fragmentIndex
        )
        return RoomScanFragmentMetadata(
            id: UUID(),
            roomIndex: roomIndex,
            fragmentIndex: fragmentIndex,
            capturedRoomIdentifier: room.identifier,
            reason: reason,
            createdAt: Date(),
            wallCount: room.walls.count,
            doorCount: room.doors.count,
            windowCount: room.windows.count,
            openingCount: room.openings.count,
            objectCount: room.objects.count,
            relativeJSONPath: relativePath
        )
    }

    // MARK: - Wall matching

    private func registerWallMetadata(
        for room: CapturedRoom,
        roomIndex: Int,
        fragmentIndex: Int,
        defaultThicknessMeters: Double
    ) {
        if !roomWallConfigurations.contains(where: { $0.roomIndex == roomIndex }) {
            roomWallConfigurations.append(
                RoomWallConfiguration(
                    roomIndex: roomIndex,
                    roomIdentifier: room.identifier,
                    defaultThicknessMeters: defaultThicknessMeters,
                    confirmedAt: Date()
                )
            )
        }

        var nextWallNumber = (roomWallAssignments
            .filter { $0.roomIndex == roomIndex }
            .map(\.wallNumber)
            .max() ?? 0) + 1

        for wall in room.walls {
            let geometry = geometrySnapshot(for: wall)
            let continuationMatch = bestContinuationWallMatch(
                for: geometry,
                roomIndex: roomIndex
            )
            let sharedMatch = continuationMatch == nil
                ? bestSharedWallMatch(for: geometry, currentRoomIndex: roomIndex)
                : nil

            let buildingWallID: UUID
            let source: WallThicknessSource
            let matchedWallIdentifier: UUID?
            let confidence: Double?
            let separation: Double?
            let wallNumber: Int

            if let continuationMatch {
                buildingWallID = continuationMatch.assignment.buildingWallID
                source = .continuedFragment
                matchedWallIdentifier = continuationMatch.assignment.wallIdentifier
                confidence = continuationMatch.confidence
                separation = continuationMatch.faceSeparationMeters
                wallNumber = continuationMatch.assignment.wallNumber
            } else if let sharedMatch {
                buildingWallID = sharedMatch.assignment.buildingWallID
                source = .inheritedSharedWall
                matchedWallIdentifier = sharedMatch.assignment.wallIdentifier
                confidence = sharedMatch.confidence
                separation = sharedMatch.faceSeparationMeters
                wallNumber = nextWallNumber
                nextWallNumber += 1
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
                wallNumber = nextWallNumber
                nextWallNumber += 1
            }

            roomWallAssignments.append(
                RoomWallAssignment(
                    id: UUID(),
                    roomIndex: roomIndex,
                    roomIdentifier: room.identifier,
                    fragmentIndex: fragmentIndex,
                    wallIdentifier: wall.identifier,
                    wallNumber: wallNumber,
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

    private func bestContinuationWallMatch(
        for current: RoomWallGeometrySnapshot,
        roomIndex: Int
    ) -> SharedWallMatch? {
        let previousAssignments = roomWallAssignments.filter { $0.roomIndex == roomIndex }
        guard !previousAssignments.isEmpty else { return nil }

        var best: SharedWallMatch?
        for previous in previousAssignments {
            guard let candidate = scoreContinuationWallMatch(
                current: current,
                previous: previous.geometry
            ) else { continue }

            if best == nil || candidate.confidence > best!.confidence {
                best = SharedWallMatch(
                    assignment: previous,
                    confidence: candidate.confidence,
                    faceSeparationMeters: candidate.separationMeters
                )
            }
        }

        guard let best, best.confidence >= 0.70 else { return nil }
        return best
    }

    private func scoreContinuationWallMatch(
        current: RoomWallGeometrySnapshot,
        previous: RoomWallGeometrySnapshot
    ) -> (confidence: Double, separationMeters: Double)? {
        let currentTangent = normalized2D(SIMD2<Float>(current.tangentX, current.tangentZ))
        let previousTangent = normalized2D(SIMD2<Float>(previous.tangentX, previous.tangentZ))
        let currentNormal = normalized2D(SIMD2<Float>(current.normalX, current.normalZ))
        let previousNormal = normalized2D(SIMD2<Float>(previous.normalX, previous.normalZ))

        let tangentAlignment = abs(Double(simd_dot(currentTangent, previousTangent)))
        let normalAlignment = abs(Double(simd_dot(currentNormal, previousNormal)))
        guard tangentAlignment >= 0.975, normalAlignment >= 0.95 else { return nil }

        let currentCenter = SIMD2<Float>(current.centerX, current.centerZ)
        let previousCenter = SIMD2<Float>(previous.centerX, previous.centerZ)
        let delta = previousCenter - currentCenter
        let planeSeparation = abs(Double(simd_dot(delta, currentNormal)))
        guard planeSeparation <= 0.18 else { return nil }

        let axis = currentTangent
        let currentAxisCenter = Double(simd_dot(currentCenter, axis))
        let previousAxisCenter = Double(simd_dot(previousCenter, axis))
        let currentHalfWidth = Double(current.widthMeters) * 0.5
        let previousHalfWidth = Double(previous.widthMeters) * 0.5 * tangentAlignment
        let currentStart = currentAxisCenter - currentHalfWidth
        let currentEnd = currentAxisCenter + currentHalfWidth
        let previousStart = previousAxisCenter - previousHalfWidth
        let previousEnd = previousAxisCenter + previousHalfWidth
        let overlap = max(0.0, min(currentEnd, previousEnd) - max(currentStart, previousStart))
        let gap = max(0.0, max(currentStart, previousStart) - min(currentEnd, previousEnd))
        guard overlap >= 0.15 || gap <= 0.45 else { return nil }

        let currentBottom = Double(current.centerY) - Double(current.heightMeters) * 0.5
        let currentTop = Double(current.centerY) + Double(current.heightMeters) * 0.5
        let previousBottom = Double(previous.centerY) - Double(previous.heightMeters) * 0.5
        let previousTop = Double(previous.centerY) + Double(previous.heightMeters) * 0.5
        let verticalOverlap = max(0.0, min(currentTop, previousTop) - max(currentBottom, previousBottom))
        let shorterHeight = max(0.01, min(Double(current.heightMeters), Double(previous.heightMeters)))
        let verticalRatio = verticalOverlap / shorterHeight
        guard verticalOverlap >= 0.50, verticalRatio >= 0.25 else { return nil }

        let shorterWidth = max(0.01, min(Double(current.widthMeters), Double(previous.widthMeters)))
        let overlapRatio = min(1.0, overlap / shorterWidth)
        let horizontalScore = overlap > 0
            ? max(0.45, overlapRatio)
            : max(0.0, 1.0 - gap / 0.45) * 0.70
        let planeScore = max(0.0, 1.0 - planeSeparation / 0.18)
        let angleScore = min(tangentAlignment, normalAlignment)
        let heightScore = min(1.0, verticalRatio)

        let confidence = (
            angleScore * 0.36
            + planeScore * 0.26
            + horizontalScore * 0.24
            + heightScore * 0.14
        )
        return (confidence, planeSeparation)
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

    private var distinctRoomCountsByBuildingWallID: [UUID: Int] {
        Dictionary(grouping: roomWallAssignments, by: \.buildingWallID)
            .mapValues { assignments in Set(assignments.map(\.roomIndex)).count }
    }

    // MARK: - Persistence and export

    private func resetPublishedResults() {
        isScanning = false
        isPaused = false
        isProcessing = false
        isBuildingFinished = false
        activeRoomNumber = 0
        activeRoomFragmentCount = 0
        capturedRoom = nil
        capturedRooms = []
        capturedStructure = nil
        fragmentMetadata = []
        capturedFragments = []
        roomWallConfigurations = []
        buildingWallRecords = []
        roomWallAssignments = []
        latestExport = nil
        shouldAcceptNextProcessedRoom = false
        pendingStopAction = nil
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
            persistSessionCheckpoint()
            writeManifest()
        } catch {
            buildingFolderURL = nil
            errorMessage = "سيعمل المسح، لكن تعذر إنشاء مجلد الحفظ: \(error.localizedDescription)"
        }
    }

    private func persistRoomFragment(
        _ room: CapturedRoom,
        metadata: RoomScanFragmentMetadata
    ) {
        guard let buildingFolderURL else { return }

        do {
            let jsonURL = buildingFolderURL.appendingPathComponent(metadata.relativeJSONPath)
            try FileManager.default.createDirectory(
                at: jsonURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try configuredEncoder().encode(room).write(to: jsonURL, options: .atomic)
        } catch {
            errorMessage = "تم حفظ الجزء داخل الجلسة، لكن تعذر كتابة ملفه: \(error.localizedDescription)"
        }
    }

    private func persistRoomFragmentsDocument(roomIndex: Int, isFinalized: Bool) {
        guard let buildingFolderURL else { return }

        let document = RoomFragmentsDocument(
            schemaVersion: 1,
            updatedAt: Date(),
            roomIndex: roomIndex,
            isRoomFinalized: isFinalized,
            fragments: fragmentMetadata
                .filter { $0.roomIndex == roomIndex }
                .sorted { $0.fragmentIndex < $1.fragmentIndex }
        )

        do {
            let roomFolder = buildingFolderURL
                .appendingPathComponent("FrozenRooms", isDirectory: true)
                .appendingPathComponent(String(format: "Room-%02d", roomIndex), isDirectory: true)
            try FileManager.default.createDirectory(at: roomFolder, withIntermediateDirectories: true)
            let url = roomFolder.appendingPathComponent("fragments.json")
            try configuredEncoder().encode(document).write(to: url, options: .atomic)
        } catch {
            errorMessage = "تعذر تحديث فهرس أجزاء الغرفة رقم \(roomIndex): \(error.localizedDescription)"
        }
    }

    private func persistSessionCheckpoint() {
        guard let buildingFolderURL else { return }

        let checkpoint = RoomScanSessionCheckpoint(
            schemaVersion: 1,
            updatedAt: Date(),
            completedRoomCount: capturedRooms.count,
            totalFragmentCount: fragmentMetadata.count,
            isPaused: isPaused,
            activeRoomNumber: activeRoomNumber,
            activeRoomFragmentCount: activeRoomFragmentCount,
            resumeScope: "same-app-process-shared-ARSession"
        )

        do {
            let url = buildingFolderURL.appendingPathComponent("session-checkpoint.json")
            try configuredEncoder().encode(checkpoint).write(to: url, options: .atomic)
        } catch {
            // A checkpoint failure must not invalidate frozen room and wall files.
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
            schemaVersion: 2,
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
            schemaVersion: 2,
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
                schemaVersion: 3,
                createdAt: scanCreatedAt,
                updatedAt: Date(),
                roomCount: capturedRooms.count,
                fragmentCount: fragmentMetadata.count,
                isFinished: isBuildingFinished,
                isPaused: isPaused,
                activeRoomNumber: activeRoomNumber,
                coordinateSpace: "continuous-shared-ARSession-with-room-fragments",
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
                    schemaVersion: 2,
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

import RoomPlan
import SceneKit
import SwiftUI
import UIKit
import simd

/// Interactive Apple SceneKit view of the app-owned building model.
/// Rooms are moved as rigid parent nodes and wall openings are rendered as
/// real voids by decomposing each wall around its door/window rectangles.
struct RoomScanProject3DView: UIViewRepresentable {
    /// Frozen logical rooms as captured by each RoomPlan session.
    let rooms: [CapturedRoom]
    /// Rooms returned by StructureBuilder. These provide Apple's canonical
    /// placement of every scan inside the combined building coordinate space.
    let mergedRooms: [CapturedRoom]
    let corrections: [AcceptedRoomCorrectionLayer]
    let wallAssignments: [RoomWallAssignment]
    let wallRecords: [BuildingWallRecord]
    let manualOpenings: [ManualOpeningRecord]
    let suppressedSurfaceIdentifiers: Set<UUID>
    let geometryOverrides: [WallGeometryOverrideRecord]
    let roomTransforms: [RoomRigidTransformRecord]
    let levelProfiles: [RoomLevelProfileRecord]
    let ceilingZones: [CeilingZoneRecord]
    let issueWallIdentifiers: Set<UUID>

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .secondarySystemBackground
        view.scene = makeScene()
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.scene = makeScene()
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        let modelRoot = SCNNode()
        modelRoot.name = "3EProjectModel"
        scene.rootNode.addChildNode(modelRoot)

        let thicknessByWallID = Dictionary(uniqueKeysWithValues: wallRecords.map { ($0.id, $0.thicknessMeters) })
        let profileByRoom = Dictionary(uniqueKeysWithValues: levelProfiles.map { ($0.roomIndex, $0) })
        let transformByRoom = Dictionary(uniqueKeysWithValues: roomTransforms.map { ($0.roomIndex, $0) })
        let overrideByAssignment = Dictionary(uniqueKeysWithValues: geometryOverrides.map { ($0.assignmentID, $0) })
        var assignmentByFace: [FaceKey: RoomWallAssignment] = [:]
        for assignment in wallAssignments {
            let key = FaceKey(roomIndex: assignment.roomIndex, wallIdentifier: assignment.wallIdentifier)
            if assignmentByFace[key] == nil { assignmentByFace[key] = assignment }
        }

        let mergedRoomByIndex = matchedMergedRoomsByLogicalIndex()

        var roomRoots: [Int: SCNNode] = [:]
        for (offset, room) in rooms.enumerated() {
            let roomIndex = offset + 1
            let seed = RoomLevelGeometrySeed.make(room: room)
            let roomPlanAlignment = roomAlignmentTransform(
                from: room,
                to: mergedRoomByIndex[roomIndex]
            )
            let alignedPivot = transformedPoint(
                SIMD2<Float>(Float(seed.centerX), Float(seed.centerZ)),
                by: roomPlanAlignment
            )
            let userCorrection = transformByRoom[roomIndex]?.sceneTransform(
                pivotX: Double(alignedPivot.x),
                pivotZ: Double(alignedPivot.y)
            ) ?? matrix_identity_float4x4

            let roomRoot = SCNNode()
            roomRoot.name = "RigidRoom-\(roomIndex)"
            // First place the original room in Apple's merged structure space,
            // then apply only the app-owned user correction in that final space.
            roomRoot.simdTransform = simd_mul(userCorrection, roomPlanAlignment)
            modelRoot.addChildNode(roomRoot)
            roomRoots[roomIndex] = roomRoot

            let profile = profileByRoom[roomIndex]
            let targetFloorY = Float(profile?.floorElevationMeters ?? seed.floorElevationMeters)
            let verticalOffset = targetFloorY - Float(seed.floorElevationMeters)
            addRoom(
                room,
                roomIndex: roomIndex,
                isCorrection: false,
                verticalOffset: verticalOffset,
                targetFloorY: targetFloorY,
                targetStructuralHeight: profile.map { Float($0.structuralCeilingHeightMeters) },
                to: roomRoot,
                assignmentByFace: assignmentByFace,
                thicknessByWallID: thicknessByWallID,
                overrideByAssignment: overrideByAssignment
            )
            addFloors(room, roomIndex: roomIndex, profile: profile, seed: seed, to: roomRoot)
        }

        for layer in corrections {
            let roomRoot = roomRoots[layer.roomIndex] ?? modelRoot
            let profile = profileByRoom[layer.roomIndex]
            let seed = rooms.indices.contains(layer.roomIndex - 1)
                ? RoomLevelGeometrySeed.make(room: rooms[layer.roomIndex - 1])
                : RoomLevelGeometrySeed.make(room: layer.room)
            let targetFloorY = Float(profile?.floorElevationMeters ?? seed.floorElevationMeters)
            let verticalOffset = targetFloorY - Float(seed.floorElevationMeters)
            addRoom(
                layer.room,
                roomIndex: layer.roomIndex,
                isCorrection: true,
                verticalOffset: verticalOffset,
                targetFloorY: targetFloorY,
                targetStructuralHeight: profile.map { Float($0.structuralCeilingHeightMeters) },
                to: roomRoot,
                assignmentByFace: assignmentByFace,
                thicknessByWallID: thicknessByWallID,
                overrideByAssignment: overrideByAssignment
            )
        }

        for zone in ceilingZones {
            guard let profile = profileByRoom[zone.roomIndex] else { continue }
            let roomRoot = roomRoots[zone.roomIndex] ?? modelRoot
            roomRoot.addChildNode(ceilingZoneNode(zone, floorElevation: profile.floorElevationMeters))
        }

        addReferenceFloor(to: scene.rootNode, modelRoot: modelRoot)
        addCamera(to: scene.rootNode, modelRoot: modelRoot)
        return scene
    }

    /// Matches StructureBuilder rooms back to the app's logical room order.
    /// RoomPlan normally preserves identifiers; index matching is a guarded
    /// fallback for older saved structures.
    private func matchedMergedRoomsByLogicalIndex() -> [Int: CapturedRoom] {
        guard !rooms.isEmpty, !mergedRooms.isEmpty else { return [:] }
        let mergedByIdentifier = Dictionary(
            mergedRooms.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var result: [Int: CapturedRoom] = [:]
        for (offset, room) in rooms.enumerated() {
            let logicalIndex = offset + 1
            if let exact = mergedByIdentifier[room.identifier] {
                result[logicalIndex] = exact
            } else if mergedRooms.count == rooms.count {
                result[logicalIndex] = mergedRooms[offset]
            }
        }
        return result
    }

    /// Derives a horizontal rigid transform from the frozen room into the
    /// corresponding StructureBuilder room. This is the missing transform that
    /// Apple's USDZ export already applies and the custom SceneKit renderer must
    /// also apply exactly once.
    private func roomAlignmentTransform(
        from sourceRoom: CapturedRoom,
        to mergedRoom: CapturedRoom?
    ) -> simd_float4x4 {
        guard let mergedRoom else { return matrix_identity_float4x4 }

        let mergedWallsByIdentifier = Dictionary(
            mergedRoom.walls.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var pairs: [(source: CapturedRoom.Surface, target: CapturedRoom.Surface)] = sourceRoom.walls.compactMap { wall in
            mergedWallsByIdentifier[wall.identifier].map { (source: wall, target: $0) }
        }

        if pairs.isEmpty, sourceRoom.walls.count == mergedRoom.walls.count {
            pairs = Array(zip(sourceRoom.walls, mergedRoom.walls)).map { (source: $0.0, target: $0.1) }
        }
        guard !pairs.isEmpty else { return matrix_identity_float4x4 }

        let sourceCenters = pairs.map { SIMD2<Float>($0.source.transform.columns.3.x, $0.source.transform.columns.3.z) }
        let targetCenters = pairs.map { SIMD2<Float>($0.target.transform.columns.3.x, $0.target.transform.columns.3.z) }
        let sourceCenter = sourceCenters.reduce(SIMD2<Float>.zero, +) / Float(sourceCenters.count)
        let targetCenter = targetCenters.reduce(SIMD2<Float>.zero, +) / Float(targetCenters.count)

        var dotSum: Float = 0
        var crossSum: Float = 0
        for index in sourceCenters.indices {
            let source = sourceCenters[index] - sourceCenter
            let target = targetCenters[index] - targetCenter
            dotSum += simd_dot(source, target)
            crossSum += source.x * target.y - source.y * target.x
        }

        var angle = atan2(crossSum, dotSum)
        if abs(dotSum) + abs(crossSum) < 0.0001,
           let firstPair = pairs.first {
            let sourceTangent = normalized2D(
                SIMD2<Float>(firstPair.source.transform.columns.0.x, firstPair.source.transform.columns.0.z)
            )
            let targetTangent = normalized2D(
                SIMD2<Float>(firstPair.target.transform.columns.0.x, firstPair.target.transform.columns.0.z)
            )
            angle = atan2(
                sourceTangent.x * targetTangent.y - sourceTangent.y * targetTangent.x,
                simd_dot(sourceTangent, targetTangent)
            )
        }

        let cosine = cos(angle)
        let sine = sin(angle)
        let rotatedSourceCenter = SIMD2<Float>(
            sourceCenter.x * cosine - sourceCenter.y * sine,
            sourceCenter.x * sine + sourceCenter.y * cosine
        )
        let translation = targetCenter - rotatedSourceCenter

        var transform = matrix_identity_float4x4
        transform.columns.0 = SIMD4<Float>(cosine, 0, sine, 0)
        transform.columns.2 = SIMD4<Float>(-sine, 0, cosine, 0)
        transform.columns.3 = SIMD4<Float>(translation.x, 0, translation.y, 1)
        return transform
    }

    private func transformedPoint(
        _ point: SIMD2<Float>,
        by transform: simd_float4x4
    ) -> SIMD2<Float> {
        let transformed = simd_mul(transform, SIMD4<Float>(point.x, 0, point.y, 1))
        return SIMD2<Float>(transformed.x, transformed.z)
    }

    private func normalized2D(_ value: SIMD2<Float>) -> SIMD2<Float> {
        let length = simd_length(value)
        return length > 0.0001 ? value / length : SIMD2<Float>(1, 0)
    }

    private func addRoom(
        _ room: CapturedRoom,
        roomIndex: Int,
        isCorrection: Bool,
        verticalOffset: Float,
        targetFloorY: Float,
        targetStructuralHeight: Float?,
        to root: SCNNode,
        assignmentByFace: [FaceKey: RoomWallAssignment],
        thicknessByWallID: [UUID: Double],
        overrideByAssignment: [UUID: WallGeometryOverrideRecord]
    ) {
        for wall in room.walls {
            let key = FaceKey(roomIndex: roomIndex, wallIdentifier: wall.identifier)
            let assignment = assignmentByFace[key]
            let thickness = assignment.flatMap { thicknessByWallID[$0.buildingWallID] } ?? 0.12
            let hasIssue = issueWallIdentifiers.contains(wall.identifier)
            let wallMaterial = material(
                color: hasIssue ? .systemRed : (isCorrection ? .systemPurple : .systemGray),
                opacity: hasIssue ? 0.88 : (isCorrection ? 0.35 : 0.72)
            )

            let geometry: EffectiveWallGeometry
            let hasManualHeight: Bool
            if let assignment {
                geometry = EffectiveWallGeometry(
                    base: assignment.geometry,
                    adjustment: overrideByAssignment[assignment.id]
                )
                hasManualHeight = overrideByAssignment[assignment.id] != nil
            } else {
                geometry = EffectiveWallGeometry(base: snapshot(for: wall), adjustment: nil)
                hasManualHeight = false
            }
            let displayHeight = hasManualHeight
                ? geometry.heightMeters
                : max(targetStructuralHeight ?? geometry.heightMeters, 0.05)
            let centerY = targetFloorY + displayHeight / 2
            let cuts = openingCuts(
                room: room,
                wall: wall,
                assignment: assignment,
                geometry: geometry,
                displayHeight: displayHeight,
                targetFloorY: targetFloorY,
                verticalOffset: verticalOffset
            )
            let node = cutWallNode(
                geometry: geometry,
                displayHeight: displayHeight,
                centerY: centerY,
                depth: max(thickness, 0.03),
                material: wallMaterial,
                cuts: cuts
            )
            root.addChildNode(node)
        }
    }

    private func openingCuts(
        room: CapturedRoom,
        wall: CapturedRoom.Surface,
        assignment: RoomWallAssignment?,
        geometry: EffectiveWallGeometry,
        displayHeight: Float,
        targetFloorY: Float,
        verticalOffset: Float
    ) -> [WallOpeningCut] {
        var cuts: [WallOpeningCut] = []

        if let assignment {
            for opening in manualOpenings where opening.buildingWallID == assignment.buildingWallID {
                var ratio = Float(min(max(opening.positionRatio, 0), 1))
                if let sourceAssignment = wallAssignments.first(where: {
                    $0.roomIndex == opening.sourceRoomIndex
                        && ($0.wallIdentifier == opening.sourceWallIdentifier || $0.buildingWallID == opening.buildingWallID)
                }) {
                    let sourceGeometry = EffectiveWallGeometry(
                        base: sourceAssignment.geometry,
                        adjustment: geometryOverrides.first { $0.assignmentID == sourceAssignment.id }
                    )
                    if simd_dot(sourceGeometry.tangent2D, geometry.tangent2D) < 0 {
                        ratio = 1 - ratio
                    }
                }
                cuts.append(
                    WallOpeningCut(
                        id: opening.id,
                        kind: opening.kind,
                        centerOffsetMeters: (ratio - 0.5) * geometry.widthMeters,
                        bottomMeters: Float(max(opening.sillHeightMeters, 0)),
                        widthMeters: Float(max(opening.widthMeters, 0.05)),
                        heightMeters: Float(max(opening.heightMeters, 0.05))
                    )
                )
            }
        }

        func appendDetected(_ surfaces: [CapturedRoom.Surface], kind: ManualOpeningKind) {
            for surface in surfaces where !suppressedSurfaceIdentifiers.contains(surface.identifier) {
                guard surface.parentIdentifier == wall.identifier else { continue }
                let center2D = SIMD2<Float>(surface.transform.columns.3.x, surface.transform.columns.3.z)
                let baseWall = snapshot(for: wall)
                let baseTangent = SIMD2<Float>(baseWall.tangentX, baseWall.tangentZ)
                let baseCenter = SIMD2<Float>(baseWall.centerX, baseWall.centerZ)
                let baseOffset = simd_dot(center2D - baseCenter, baseTangent)
                let ratio = baseWall.widthMeters > 0.001 ? baseOffset / baseWall.widthMeters : 0
                let offset = ratio * geometry.widthMeters
                let bottom = surface.transform.columns.3.y + verticalOffset
                    - surface.dimensions.y / 2 - targetFloorY
                cuts.append(
                    WallOpeningCut(
                        id: surface.identifier,
                        kind: kind,
                        centerOffsetMeters: offset,
                        bottomMeters: max(bottom, 0),
                        widthMeters: max(surface.dimensions.x, 0.05),
                        heightMeters: max(surface.dimensions.y, 0.05)
                    )
                )
            }
        }
        appendDetected(room.doors, kind: .door)
        appendDetected(room.openings, kind: .opening)
        appendDetected(room.windows, kind: .window)

        return cuts.compactMap { cut in
            let minX = max(cut.minX, -geometry.widthMeters / 2)
            let maxX = min(cut.maxX, geometry.widthMeters / 2)
            let minY = max(cut.minY, 0)
            let maxY = min(cut.maxY, displayHeight)
            guard maxX - minX > 0.02, maxY - minY > 0.02 else { return nil }
            return WallOpeningCut(
                id: cut.id,
                kind: cut.kind,
                centerOffsetMeters: (minX + maxX) / 2,
                bottomMeters: minY,
                widthMeters: maxX - minX,
                heightMeters: maxY - minY
            )
        }
    }

    private func cutWallNode(
        geometry: EffectiveWallGeometry,
        displayHeight: Float,
        centerY: Float,
        depth: Double,
        material: SCNMaterial,
        cuts: [WallOpeningCut]
    ) -> SCNNode {
        let group = SCNNode()
        var transform = geometry.transform
        transform.columns.3.y = centerY
        group.simdTransform = transform

        if cuts.isEmpty {
            group.addChildNode(boxNode(
                width: geometry.widthMeters,
                height: displayHeight,
                depth: Float(depth),
                centerX: 0,
                centerY: 0,
                material: material
            ))
            return group
        }

        var xBreaks: [Float] = [-geometry.widthMeters / 2, geometry.widthMeters / 2]
        var yBreaks: [Float] = [0, displayHeight]
        for cut in cuts {
            xBreaks += [cut.minX, cut.maxX]
            yBreaks += [cut.minY, cut.maxY]
        }
        xBreaks = uniqueSorted(xBreaks)
        yBreaks = uniqueSorted(yBreaks)

        for xIndex in 0..<(xBreaks.count - 1) {
            for yIndex in 0..<(yBreaks.count - 1) {
                let x0 = xBreaks[xIndex]
                let x1 = xBreaks[xIndex + 1]
                let y0 = yBreaks[yIndex]
                let y1 = yBreaks[yIndex + 1]
                guard x1 - x0 > 0.005, y1 - y0 > 0.005 else { continue }
                let midpoint = SIMD2<Float>((x0 + x1) / 2, (y0 + y1) / 2)
                let isVoid = cuts.contains {
                    midpoint.x > $0.minX + 0.001 && midpoint.x < $0.maxX - 0.001
                        && midpoint.y > $0.minY + 0.001 && midpoint.y < $0.maxY - 0.001
                }
                guard !isVoid else { continue }
                group.addChildNode(boxNode(
                    width: x1 - x0,
                    height: y1 - y0,
                    depth: Float(depth),
                    centerX: (x0 + x1) / 2,
                    centerY: (y0 + y1) / 2 - displayHeight / 2,
                    material: material
                ))
            }
        }

        for cut in cuts {
            group.addChildNode(openingOutlineNode(
                cut: cut,
                wallHeight: displayHeight,
                depth: Float(depth)
            ))
        }
        return group
    }

    private func boxNode(
        width: Float,
        height: Float,
        depth: Float,
        centerX: Float,
        centerY: Float,
        material: SCNMaterial
    ) -> SCNNode {
        let box = SCNBox(
            width: CGFloat(max(width, 0.005)),
            height: CGFloat(max(height, 0.005)),
            length: CGFloat(max(depth, 0.005)),
            chamferRadius: 0.003
        )
        box.materials = [material]
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(centerX, centerY, 0)
        return node
    }

    private func openingOutlineNode(cut: WallOpeningCut, wallHeight: Float, depth: Float) -> SCNNode {
        let root = SCNNode()
        let color: UIColor
        switch cut.kind {
        case .door: color = .systemOrange
        case .opening: color = .systemGreen
        case .window: color = .systemBlue
        }
        let outlineMaterial = material(color: color, opacity: 0.88)
        let strip: Float = min(max(min(cut.widthMeters, cut.heightMeters) * 0.025, 0.012), 0.035)
        let localCenterY = cut.bottomMeters + cut.heightMeters / 2 - wallHeight / 2
        let frontZ = depth / 2 + 0.008

        func add(width: Float, height: Float, x: Float, y: Float) {
            let node = boxNode(
                width: width,
                height: height,
                depth: 0.012,
                centerX: x,
                centerY: y,
                material: outlineMaterial
            )
            node.position.z = frontZ
            root.addChildNode(node)
        }
        add(width: cut.widthMeters, height: strip, x: cut.centerOffsetMeters, y: localCenterY + cut.heightMeters / 2)
        add(width: strip, height: cut.heightMeters, x: cut.centerOffsetMeters - cut.widthMeters / 2, y: localCenterY)
        add(width: strip, height: cut.heightMeters, x: cut.centerOffsetMeters + cut.widthMeters / 2, y: localCenterY)
        if cut.kind == .window {
            add(width: cut.widthMeters, height: strip, x: cut.centerOffsetMeters, y: localCenterY - cut.heightMeters / 2)
        }
        return root
    }

    private func uniqueSorted(_ values: [Float]) -> [Float] {
        let sorted = values.sorted()
        var result: [Float] = []
        for value in sorted where result.last.map({ abs($0 - value) > 0.001 }) ?? true {
            result.append(value)
        }
        return result
    }

    private func snapshot(for surface: CapturedRoom.Surface) -> RoomWallGeometrySnapshot {
        var tangent = SIMD2<Float>(surface.transform.columns.0.x, surface.transform.columns.0.z)
        let tangentLength = simd_length(tangent)
        tangent = tangentLength > 0.0001 ? tangent / tangentLength : SIMD2<Float>(1, 0)
        var normal = SIMD2<Float>(surface.transform.columns.2.x, surface.transform.columns.2.z)
        let normalLength = simd_length(normal)
        normal = normalLength > 0.0001 ? normal / normalLength : SIMD2<Float>(-tangent.y, tangent.x)
        return RoomWallGeometrySnapshot(
            centerX: surface.transform.columns.3.x,
            centerY: surface.transform.columns.3.y,
            centerZ: surface.transform.columns.3.z,
            tangentX: tangent.x,
            tangentZ: tangent.y,
            normalX: normal.x,
            normalZ: normal.y,
            widthMeters: max(surface.dimensions.x, 0.05),
            heightMeters: max(surface.dimensions.y, 0.05)
        )
    }

    private func addFloors(
        _ room: CapturedRoom,
        roomIndex: Int,
        profile: RoomLevelProfileRecord?,
        seed: RoomLevelGeometrySeed,
        to root: SCNNode
    ) {
        let targetY = Float(profile?.floorElevationMeters ?? seed.floorElevationMeters)
        if room.floors.isEmpty {
            let box = SCNBox(
                width: CGFloat(max(seed.widthMeters, 0.20)),
                height: 0.025,
                length: CGFloat(max(seed.depthMeters, 0.20)),
                chamferRadius: 0
            )
            box.materials = [material(color: .systemBrown, opacity: 0.24)]
            let node = SCNNode(geometry: box)
            node.eulerAngles.y = Float(-seed.rotationDegrees * .pi / 180)
            node.position = SCNVector3(Float(seed.centerX), targetY - 0.015, Float(seed.centerZ))
            node.name = "FallbackFloor-Room-\(roomIndex)"
            root.addChildNode(node)
            return
        }

        for floor in room.floors {
            let box = SCNBox(
                width: CGFloat(max(floor.dimensions.x, 0.05)),
                height: 0.025,
                length: CGFloat(max(floor.dimensions.y, 0.05)),
                chamferRadius: 0
            )
            box.materials = [material(color: .systemBrown, opacity: 0.24)]
            let node = SCNNode(geometry: box)
            var transform = matrix_identity_float4x4
            let axisX = simd_normalize(SIMD3<Float>(
                floor.transform.columns.0.x, floor.transform.columns.0.y, floor.transform.columns.0.z
            ))
            let planeAxis = simd_normalize(SIMD3<Float>(
                floor.transform.columns.1.x, floor.transform.columns.1.y, floor.transform.columns.1.z
            ))
            var normal = simd_normalize(simd_cross(axisX, planeAxis))
            if abs(normal.y) < 0.5 { normal = SIMD3<Float>(0, 1, 0) }
            transform.columns.0 = SIMD4<Float>(axisX.x, axisX.y, axisX.z, 0)
            transform.columns.1 = SIMD4<Float>(normal.x, normal.y, normal.z, 0)
            transform.columns.2 = SIMD4<Float>(planeAxis.x, planeAxis.y, planeAxis.z, 0)
            transform.columns.3 = SIMD4<Float>(
                floor.transform.columns.3.x,
                targetY - 0.015,
                floor.transform.columns.3.z,
                1
            )
            node.simdTransform = transform
            node.name = "RoomPlanFloor-\(floor.identifier.uuidString)"
            root.addChildNode(node)
        }
    }

    private func ceilingZoneNode(_ zone: CeilingZoneRecord, floorElevation: Double) -> SCNNode {
        let box = SCNBox(
            width: CGFloat(max(zone.widthMeters, 0.05)),
            height: 0.045,
            length: CGFloat(max(zone.depthMeters, 0.05)),
            chamferRadius: 0.01
        )
        let color: UIColor
        switch zone.kind {
        case .falseCeiling: color = .systemIndigo
        case .soffit: color = .systemPurple
        case .beam: color = .systemOrange
        case .raisedCeiling: color = .systemBlue
        case .custom: color = .systemTeal
        }
        box.materials = [material(color: color, opacity: 0.48)]
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(
            Float(zone.centerX),
            Float(floorElevation + zone.heightAboveFloorMeters),
            Float(zone.centerZ)
        )
        node.eulerAngles.y = Float(-zone.rotationDegrees * .pi / 180)
        node.name = "CeilingZone-\(zone.id.uuidString)"
        return node
    }

    private func material(color: UIColor, opacity: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.transparency = opacity
        material.isDoubleSided = true
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.8
        return material
    }

    private func addReferenceFloor(to root: SCNNode, modelRoot: SCNNode) {
        guard let bounds = modelBounds(modelRoot) else { return }
        let width = max(bounds.max.x - bounds.min.x, 2)
        let depth = max(bounds.max.z - bounds.min.z, 2)
        let floor = SCNFloor()
        floor.reflectivity = 0
        floor.firstMaterial = material(color: .tertiarySystemFill, opacity: 0.55)
        let node = SCNNode(geometry: floor)
        node.position = SCNVector3(
            (bounds.min.x + bounds.max.x) / 2,
            bounds.min.y - 0.02,
            (bounds.min.z + bounds.max.z) / 2
        )
        node.scale = SCNVector3(width, 1, depth)
        root.addChildNode(node)
    }

    private func addCamera(to root: SCNNode, modelRoot: SCNNode) {
        guard let bounds = modelBounds(modelRoot) else { return }
        let center = SIMD3<Float>(
            (bounds.min.x + bounds.max.x) / 2,
            (bounds.min.y + bounds.max.y) / 2,
            (bounds.min.z + bounds.max.z) / 2
        )
        let horizontalExtent = max(bounds.max.x - bounds.min.x, bounds.max.z - bounds.min.z)
        let extent = max(max(horizontalExtent, bounds.max.y - bounds.min.y), 2)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.01
        cameraNode.camera?.zFar = Double(max(extent * 20, 100))
        cameraNode.simdPosition = center + SIMD3<Float>(extent * 1.25, extent * 1.05, extent * 1.25)

        let target = SCNNode()
        target.simdPosition = center
        root.addChildNode(target)
        let constraint = SCNLookAtConstraint(target: target)
        constraint.isGimbalLockEnabled = true
        cameraNode.constraints = [constraint]
        root.addChildNode(cameraNode)
    }

    private func modelBounds(_ node: SCNNode) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        let box = node.boundingBox
        guard box.min.x.isFinite, box.max.x.isFinite else { return nil }
        return (
            SIMD3<Float>(box.min.x, box.min.y, box.min.z),
            SIMD3<Float>(box.max.x, box.max.y, box.max.z)
        )
    }

    private struct FaceKey: Hashable {
        let roomIndex: Int
        let wallIdentifier: UUID
    }
}

import RoomPlan
import SceneKit
import SwiftUI
import UIKit
import simd

/// Interactive Apple SceneKit view of the app-owned building model.
/// Unlike Quick Look, this layer can display supplemental scans, manual openings,
/// wall thickness metadata, and hidden RoomPlan surfaces.
struct RoomScanProject3DView: UIViewRepresentable {
    let rooms: [CapturedRoom]
    let corrections: [AcceptedRoomCorrectionLayer]
    let wallAssignments: [RoomWallAssignment]
    let wallRecords: [BuildingWallRecord]
    let manualOpenings: [ManualOpeningRecord]
    let suppressedSurfaceIdentifiers: Set<UUID>
    let geometryOverrides: [WallGeometryOverrideRecord]
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
        var assignmentByFace: [FaceKey: RoomWallAssignment] = [:]
        let overrideByAssignment = Dictionary(
            uniqueKeysWithValues: geometryOverrides.map { ($0.assignmentID, $0) }
        )
        for assignment in wallAssignments {
            let key = FaceKey(roomIndex: assignment.roomIndex, wallIdentifier: assignment.wallIdentifier)
            if assignmentByFace[key] == nil {
                assignmentByFace[key] = assignment
            }
        }

        for (offset, room) in rooms.enumerated() {
            let roomIndex = offset + 1
            let profile = profileByRoom[roomIndex]
            let seed = RoomLevelGeometrySeed.make(room: room)
            let verticalOffset = Float((profile?.floorElevationMeters ?? seed.floorElevationMeters) - seed.floorElevationMeters)
            addRoom(
                room,
                roomIndex: roomIndex,
                isCorrection: false,
                verticalOffset: verticalOffset,
                targetFloorY: Float(profile?.floorElevationMeters ?? seed.floorElevationMeters),
                targetStructuralHeight: profile.map { Float($0.structuralCeilingHeightMeters) },
                to: modelRoot,
                assignmentByFace: assignmentByFace,
                thicknessByWallID: thicknessByWallID,
                overrideByAssignment: overrideByAssignment
            )
            addFloors(
                room,
                roomIndex: roomIndex,
                profile: profile,
                seed: seed,
                to: modelRoot
            )
        }

        for layer in corrections {
            let profile = profileByRoom[layer.roomIndex]
            let seed = rooms.indices.contains(layer.roomIndex - 1)
                ? RoomLevelGeometrySeed.make(room: rooms[layer.roomIndex - 1])
                : RoomLevelGeometrySeed.make(room: layer.room)
            let verticalOffset = Float((profile?.floorElevationMeters ?? seed.floorElevationMeters) - seed.floorElevationMeters)
            addRoom(
                layer.room,
                roomIndex: layer.roomIndex,
                isCorrection: true,
                verticalOffset: verticalOffset,
                targetFloorY: Float(profile?.floorElevationMeters ?? seed.floorElevationMeters),
                targetStructuralHeight: profile.map { Float($0.structuralCeilingHeightMeters) },
                to: modelRoot,
                assignmentByFace: assignmentByFace,
                thicknessByWallID: thicknessByWallID,
                overrideByAssignment: overrideByAssignment
            )
        }

        for opening in manualOpenings {
            let profile = profileByRoom[opening.sourceRoomIndex]
            let seed = rooms.indices.contains(opening.sourceRoomIndex - 1)
                ? RoomLevelGeometrySeed.make(room: rooms[opening.sourceRoomIndex - 1])
                : nil
            let verticalOffset = Float((profile?.floorElevationMeters ?? seed?.floorElevationMeters ?? 0) - (seed?.floorElevationMeters ?? 0))
            modelRoot.addChildNode(manualOpeningNode(opening, verticalOffset: verticalOffset))
        }

        for zone in ceilingZones {
            guard let profile = profileByRoom[zone.roomIndex] else { continue }
            modelRoot.addChildNode(ceilingZoneNode(zone, floorElevation: profile.floorElevationMeters))
        }

        addReferenceFloor(to: scene.rootNode, modelRoot: modelRoot)
        addCamera(to: scene.rootNode, modelRoot: modelRoot)
        return scene
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
            if let assignment {
                let geometry = EffectiveWallGeometry(
                    base: assignment.geometry,
                    adjustment: overrideByAssignment[assignment.id]
                )
                let hasManualHeight = overrideByAssignment[assignment.id] != nil
                let displayHeight = hasManualHeight
                    ? geometry.heightMeters
                    : max(targetStructuralHeight ?? geometry.heightMeters, 0.05)
                let node = wallNode(
                    geometry: geometry,
                    displayHeight: displayHeight,
                    centerY: targetFloorY + displayHeight / 2,
                    depth: max(thickness, 0.03),
                    material: wallMaterial
                )
                root.addChildNode(node)
            } else {
                let displayHeight = max(targetStructuralHeight ?? wall.dimensions.y, 0.05)
                let node = surfaceNode(
                    wall,
                    depth: max(thickness, 0.03),
                    material: wallMaterial,
                    displayHeight: displayHeight,
                    centerY: targetFloorY + displayHeight / 2
                )
                root.addChildNode(node)
            }
        }

        addDetectedSurfaces(room.doors, color: .systemOrange, isCorrection: isCorrection, verticalOffset: verticalOffset, to: root)
        addDetectedSurfaces(room.windows, color: .systemBlue, isCorrection: isCorrection, verticalOffset: verticalOffset, to: root)
        addDetectedSurfaces(room.openings, color: .systemGreen, isCorrection: isCorrection, verticalOffset: verticalOffset, to: root)
    }

    private func addDetectedSurfaces(
        _ surfaces: [CapturedRoom.Surface],
        color: UIColor,
        isCorrection: Bool,
        verticalOffset: Float,
        to root: SCNNode
    ) {
        for surface in surfaces where !suppressedSurfaceIdentifiers.contains(surface.identifier) {
            let node = surfaceNode(
                surface,
                depth: isCorrection ? 0.025 : 0.04,
                material: material(color: color, opacity: isCorrection ? 0.40 : 0.90)
            )
            node.simdPosition.y += verticalOffset
            root.addChildNode(node)
        }
    }

    private func wallNode(
        geometry: EffectiveWallGeometry,
        displayHeight: Float,
        centerY: Float,
        depth: Double,
        material: SCNMaterial
    ) -> SCNNode {
        let box = SCNBox(
            width: CGFloat(max(geometry.widthMeters, 0.03)),
            height: CGFloat(max(displayHeight, 0.03)),
            length: CGFloat(max(depth, 0.01)),
            chamferRadius: 0.005
        )
        box.materials = [material]
        let node = SCNNode(geometry: box)
        var transform = geometry.transform
        transform.columns.3.y = centerY
        node.simdTransform = transform
        return node
    }

    private func surfaceNode(
        _ surface: CapturedRoom.Surface,
        depth: Double,
        material: SCNMaterial,
        displayHeight: Float? = nil,
        centerY: Float? = nil
    ) -> SCNNode {
        let geometry = SCNBox(
            width: CGFloat(max(surface.dimensions.x, 0.03)),
            height: CGFloat(max(displayHeight ?? surface.dimensions.y, 0.03)),
            length: CGFloat(max(depth, 0.01)),
            chamferRadius: 0.005
        )
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        var transform = surface.transform
        if let centerY { transform.columns.3.y = centerY }
        node.simdTransform = transform
        return node
    }

    private func manualOpeningNode(_ record: ManualOpeningRecord, verticalOffset: Float) -> SCNNode {
        let geometry = SCNBox(
            width: CGFloat(max(record.widthMeters, 0.05)),
            height: CGFloat(max(record.heightMeters, 0.05)),
            length: 0.06,
            chamferRadius: 0.01
        )
        let color: UIColor
        switch record.kind {
        case .door: color = .systemRed
        case .opening: color = .systemTeal
        case .window: color = .systemCyan
        }
        geometry.materials = [material(color: color, opacity: 0.92)]

        let tangent = simd_normalize(SIMD3<Float>(record.tangentX, 0, record.tangentZ))
        let normal = simd_normalize(SIMD3<Float>(record.normalX, 0, record.normalZ))
        var transform = matrix_identity_float4x4
        transform.columns.0 = SIMD4<Float>(tangent.x, tangent.y, tangent.z, 0)
        transform.columns.1 = SIMD4<Float>(0, 1, 0, 0)
        transform.columns.2 = SIMD4<Float>(normal.x, normal.y, normal.z, 0)
        transform.columns.3 = SIMD4<Float>(record.centerX, record.centerY + verticalOffset, record.centerZ, 1)

        let node = SCNNode(geometry: geometry)
        node.simdTransform = transform
        node.name = "Manual-\(record.kind.rawValue)-\(record.id.uuidString)"
        return node
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
            node.position = SCNVector3(
                Float(seed.centerX),
                targetY - 0.015,
                Float(seed.centerZ)
            )
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
        let horizontalExtent = max(
            bounds.max.x - bounds.min.x,
            bounds.max.z - bounds.min.z
        )
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

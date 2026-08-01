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
            addRoom(
                room,
                roomIndex: offset + 1,
                isCorrection: false,
                to: modelRoot,
                assignmentByFace: assignmentByFace,
                thicknessByWallID: thicknessByWallID,
                overrideByAssignment: overrideByAssignment
            )
        }

        for layer in corrections {
            addRoom(
                layer.room,
                roomIndex: layer.roomIndex,
                isCorrection: true,
                to: modelRoot,
                assignmentByFace: assignmentByFace,
                thicknessByWallID: thicknessByWallID,
                overrideByAssignment: overrideByAssignment
            )
        }

        for opening in manualOpenings {
            modelRoot.addChildNode(manualOpeningNode(opening))
        }

        addReferenceFloor(to: scene.rootNode, modelRoot: modelRoot)
        addCamera(to: scene.rootNode, modelRoot: modelRoot)
        return scene
    }

    private func addRoom(
        _ room: CapturedRoom,
        roomIndex: Int,
        isCorrection: Bool,
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
                root.addChildNode(
                    wallNode(
                        geometry: geometry,
                        depth: max(thickness, 0.03),
                        material: wallMaterial
                    )
                )
            } else {
                root.addChildNode(
                    surfaceNode(
                        wall,
                        depth: max(thickness, 0.03),
                        material: wallMaterial
                    )
                )
            }
        }

        addDetectedSurfaces(room.doors, color: .systemOrange, isCorrection: isCorrection, to: root)
        addDetectedSurfaces(room.windows, color: .systemBlue, isCorrection: isCorrection, to: root)
        addDetectedSurfaces(room.openings, color: .systemGreen, isCorrection: isCorrection, to: root)
    }

    private func addDetectedSurfaces(
        _ surfaces: [CapturedRoom.Surface],
        color: UIColor,
        isCorrection: Bool,
        to root: SCNNode
    ) {
        for surface in surfaces where !suppressedSurfaceIdentifiers.contains(surface.identifier) {
            root.addChildNode(
                surfaceNode(
                    surface,
                    depth: isCorrection ? 0.025 : 0.04,
                    material: material(color: color, opacity: isCorrection ? 0.40 : 0.90)
                )
            )
        }
    }

    private func wallNode(
        geometry: EffectiveWallGeometry,
        depth: Double,
        material: SCNMaterial
    ) -> SCNNode {
        let box = SCNBox(
            width: CGFloat(max(geometry.widthMeters, 0.03)),
            height: CGFloat(max(geometry.heightMeters, 0.03)),
            length: CGFloat(max(depth, 0.01)),
            chamferRadius: 0.005
        )
        box.materials = [material]
        let node = SCNNode(geometry: box)
        node.simdTransform = geometry.transform
        return node
    }

    private func surfaceNode(
        _ surface: CapturedRoom.Surface,
        depth: Double,
        material: SCNMaterial
    ) -> SCNNode {
        let geometry = SCNBox(
            width: CGFloat(max(surface.dimensions.x, 0.03)),
            height: CGFloat(max(surface.dimensions.y, 0.03)),
            length: CGFloat(max(depth, 0.01)),
            chamferRadius: 0.005
        )
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.simdTransform = surface.transform
        return node
    }

    private func manualOpeningNode(_ record: ManualOpeningRecord) -> SCNNode {
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
        transform.columns.3 = SIMD4<Float>(record.centerX, record.centerY, record.centerZ, 1)

        let node = SCNNode(geometry: geometry)
        node.simdTransform = transform
        node.name = "Manual-\(record.kind.rawValue)-\(record.id.uuidString)"
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

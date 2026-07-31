import ARKit
import Combine
import SceneKit

final class SurfaceClassificationViewModel: NSObject, ObservableObject, ARSCNViewDelegate, ARSessionDelegate {
    @Published private(set) var classificationCounts: [String: Int] = [:]
    @Published private(set) var anchorCount = 0
    @Published private(set) var totalFaceCount = 0
    @Published private(set) var trackingState = "بدء التتبع"
    @Published private(set) var errorMessage: String?

    private weak var sceneView: ARSCNView?
    private let dataLock = NSLock()
    private var anchorCounts: [UUID: [String: Int]] = [:]
    private var currentFilter = "all"
    private var showUnknown = false
    private var currentOpacity: CGFloat = 0.46
    private var wireframe = false

    var classifiedPercentageText: String {
        guard totalFaceCount > 0 else { return "0%" }
        let unknown = classificationCounts[SurfaceClassKind.none.rawValue, default: 0]
        let classified = max(0, totalFaceCount - unknown)
        return "\(Int((Double(classified) / Double(totalFaceCount)) * 100))%"
    }

    func attach(to sceneView: ARSCNView) {
        self.sceneView = sceneView
        sceneView.delegate = self
        sceneView.session.delegate = self
        run(reset: true)
    }

    func updateDisplaySettings(filter: String, showUnknown: Bool, opacity: CGFloat, wireframe: Bool) {
        dataLock.lock()
        currentFilter = filter
        self.showUnknown = showUnknown
        currentOpacity = opacity
        self.wireframe = wireframe
        dataLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.applyDisplaySettingsToAllNodes()
        }
    }

    func restart() {
        dataLock.lock()
        anchorCounts.removeAll()
        dataLock.unlock()
        publishCounts()
        run(reset: true)
    }

    func stop() { sceneView?.session.pause() }
    func clearError() { errorMessage = nil }

    private func run(reset: Bool) {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) else {
            errorMessage = "تصنيف Scene Mesh غير مدعوم على هذا الجهاز."
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.sceneReconstruction = .meshWithClassification
        let options: ARSession.RunOptions = reset ? [.resetTracking, .removeExistingAnchors] : []
        sceneView?.session.run(configuration, options: options)
    }

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return nil }
        let result = buildNode(for: meshAnchor)
        recordCounts(result.counts, for: meshAnchor.identifier)
        applyDisplaySettings(to: result.node)
        return result.node
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return }
        let result = buildNode(for: meshAnchor)
        node.childNodes.forEach { $0.removeFromParentNode() }
        for child in result.node.childNodes {
            child.removeFromParentNode()
            node.addChildNode(child)
        }
        recordCounts(result.counts, for: meshAnchor.identifier)
        applyDisplaySettings(to: node)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        dataLock.lock()
        for anchor in anchors { anchorCounts.removeValue(forKey: anchor.identifier) }
        dataLock.unlock()
        publishCounts()
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let text: String
        switch camera.trackingState {
        case .normal: text = "طبيعي"
        case .notAvailable: text = "غير متاح"
        case .limited(let reason):
            switch reason {
            case .initializing: text = "تهيئة"
            case .excessiveMotion: text = "حركة سريعة"
            case .insufficientFeatures: text = "تفاصيل قليلة"
            case .relocalizing: text = "إعادة تحديد الموقع"
            @unknown default: text = "محدود"
            }
        }
        DispatchQueue.main.async { [weak self] in self?.trackingState = text }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.errorMessage = error.localizedDescription }
    }

    private func buildNode(for anchor: ARMeshAnchor) -> (node: SCNNode, counts: [String: Int]) {
        let rootNode = SCNNode()
        rootNode.name = "classification-anchor"
        let geometry = anchor.geometry
        let vertices = (0..<geometry.vertices.count).map { index in
            let value = geometry.vertex(at: index)
            return SCNVector3(value.x, value.y, value.z)
        }
        let vertexSource = SCNGeometrySource(vertices: vertices)

        var groupedIndices: [String: [UInt32]] = [:]
        var counts: [String: Int] = [:]

        for faceIndex in 0..<geometry.faces.count {
            let kind = SurfaceClassKind(classification: geometry.classificationOf(faceWithIndex: faceIndex))
            let key = kind.rawValue
            groupedIndices[key, default: []].append(contentsOf: geometry.vertexIndicesOf(faceWithIndex: faceIndex))
            counts[key, default: 0] += 1
        }

        for kind in SurfaceClassKind.allCases {
            guard let indices = groupedIndices[kind.rawValue], !indices.isEmpty else { continue }
            let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
            let meshGeometry = SCNGeometry(sources: [vertexSource], elements: [element])
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = kind.uiColor
            material.emission.contents = kind.uiColor.withAlphaComponent(0.18)
            material.isDoubleSided = true
            material.writesToDepthBuffer = true
            material.readsFromDepthBuffer = true
            meshGeometry.materials = [material]

            let child = SCNNode(geometry: meshGeometry)
            child.name = "surface-\(kind.rawValue)"
            rootNode.addChildNode(child)
        }

        return (rootNode, counts)
    }

    private func recordCounts(_ counts: [String: Int], for id: UUID) {
        dataLock.lock()
        anchorCounts[id] = counts
        dataLock.unlock()
        publishCounts()
    }

    private func publishCounts() {
        dataLock.lock()
        let snapshot = anchorCounts
        dataLock.unlock()

        var totals: [String: Int] = [:]
        for counts in snapshot.values {
            for (key, count) in counts { totals[key, default: 0] += count }
        }
        let faceCount = totals.values.reduce(0, +)

        DispatchQueue.main.async { [weak self] in
            self?.classificationCounts = totals
            self?.anchorCount = snapshot.count
            self?.totalFaceCount = faceCount
        }
    }

    private func applyDisplaySettingsToAllNodes() {
        guard let root = sceneView?.scene.rootNode else { return }
        root.enumerateChildNodes { [weak self] node, _ in
            if node.name == "classification-anchor" { self?.applyDisplaySettings(to: node) }
        }
    }

    private func applyDisplaySettings(to rootNode: SCNNode) {
        dataLock.lock()
        let filter = currentFilter
        let includeUnknown = showUnknown
        let opacity = currentOpacity
        let useWireframe = wireframe
        dataLock.unlock()

        rootNode.enumerateChildNodes { node, _ in
            guard let name = node.name, name.hasPrefix("surface-") else { return }
            let kind = String(name.dropFirst("surface-".count))
            let visible: Bool
            if filter == "all" {
                visible = kind != SurfaceClassKind.none.rawValue || includeUnknown
            } else {
                visible = kind == filter
            }
            node.isHidden = !visible
            node.opacity = opacity
            node.geometry?.materials.forEach { $0.fillMode = useWireframe ? .lines : .fill }
        }
    }
}

private extension SurfaceClassKind {
    init(classification: ARMeshClassification) {
        switch classification {
        case .wall: self = .wall
        case .floor: self = .floor
        case .ceiling: self = .ceiling
        case .table: self = .table
        case .seat: self = .seat
        case .window: self = .window
        case .door: self = .door
        case .none: self = .none
        @unknown default: self = .none
        }
    }
}

private extension ARMeshGeometry {
    func classificationOf(faceWithIndex faceIndex: Int) -> ARMeshClassification {
        guard let classification else { return .none }
        let pointer = classification.buffer.contents().advanced(
            by: classification.offset + classification.stride * faceIndex
        )
        let rawValue = pointer.assumingMemoryBound(to: UInt8.self).pointee
        return ARMeshClassification(rawValue: Int(rawValue)) ?? .none
    }

    func vertex(at index: Int) -> SIMD3<Float> {
        let pointer = vertices.buffer.contents().advanced(by: vertices.offset + vertices.stride * index)
        return pointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
    }

    func vertexIndicesOf(faceWithIndex faceIndex: Int) -> [UInt32] {
        let indexCount = faces.indexCountPerPrimitive
        let faceOffset = faceIndex * indexCount * faces.bytesPerIndex

        return (0..<indexCount).map { index in
            let pointer = faces.buffer.contents().advanced(by: faceOffset + index * faces.bytesPerIndex)
            if faces.bytesPerIndex == MemoryLayout<UInt16>.size {
                return UInt32(pointer.assumingMemoryBound(to: UInt16.self).pointee)
            }
            return pointer.assumingMemoryBound(to: UInt32.self).pointee
        }
    }
}

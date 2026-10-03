import SceneKit
import SwiftUI

/// Uses the same Apple SceneKit camera-control style as the established RoomScan 3D viewer.
/// SceneKit handles orbit, pan and zoom instead of the previous custom fly-camera mode.
struct AreaScanPreviewView: UIViewRepresentable {
    let mesh: AreaScanTexturedMesh

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = Color3DMeshExporter.makeScene(mesh: mesh)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .secondarySystemBackground
        view.rendersContinuously = false
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.scene = Color3DMeshExporter.makeScene(mesh: mesh)
        uiView.allowsCameraControl = true
        uiView.autoenablesDefaultLighting = true
    }
}

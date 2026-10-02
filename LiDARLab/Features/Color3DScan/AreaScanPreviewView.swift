import SceneKit
import SwiftUI

struct AreaScanPreviewView: UIViewRepresentable {
    let mesh: AreaScanColoredMesh

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = Color3DMeshExporter.makeScene(mesh: mesh)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

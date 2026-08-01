import RealityKit
import SwiftUI
import UIKit

struct MeasurementARViewContainer: UIViewRepresentable {
    @ObservedObject var model: MeasurementViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTap(_:)))
        arView.addGestureRecognizer(tap)
        context.coordinator.arView = arView
        model.attach(to: arView)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    final class Coordinator: NSObject {
        let model: MeasurementViewModel
        weak var arView: ARView?

        init(model: MeasurementViewModel) {
            self.model = model
        }

        @objc func didTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView else { return }
            model.addPoint(at: recognizer.location(in: arView))
        }
    }
}

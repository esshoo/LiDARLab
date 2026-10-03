import RealityKit
import SwiftUI

struct ObjectScanARViewContainer: UIViewRepresentable {
    @ObservedObject var model: ObjectScanViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false
        model.attach(to: view)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var model: ObjectScanViewModel?

        init(model: ObjectScanViewModel) {
            self.model = model
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let view = recognizer.view as? ARView else { return }
            model?.selectTarget(at: recognizer.location(in: view))
        }
    }
}

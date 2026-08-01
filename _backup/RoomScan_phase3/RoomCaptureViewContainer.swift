import RoomPlan
import SwiftUI

/// Keeps one RoomCaptureView and one ARSession alive for the whole multi-room workflow.
/// Every room is still captured as a separate RoomPlan scan.
struct RoomCaptureViewContainer: UIViewRepresentable {
    @ObservedObject var model: RoomScanViewModel

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero, arSession: model.sharedARSession)
        view.isModelEnabled = true
        model.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}

    static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: Void) {
        uiView.captureSession.stop(pauseARSession: true)
    }
}

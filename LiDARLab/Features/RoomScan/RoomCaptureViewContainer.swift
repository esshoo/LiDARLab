import RoomPlan
import SwiftUI

struct RoomCaptureViewContainer: UIViewRepresentable {
    @ObservedObject var model: RoomScanViewModel

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.isModelEnabled = true
        model.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}

    static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: Void) {
        uiView.captureSession.stop(pauseARSession: true)
    }
}

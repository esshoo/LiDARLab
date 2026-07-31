import RealityKit
import SwiftUI

struct ARPlaygroundView: View {
    @StateObject private var model = ARPlaygroundViewModel()

    var body: some View {
        ZStack {
            ARPlaygroundContainer(model: model)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        objectCountLabel
                        Spacer(minLength: 8)
                        clearButton
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        objectCountLabel
                        clearButton
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                Spacer()

                Text(model.statusMessage)
                    .font(.subheadline.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(14)
        }
        .background(.black)
        .navigationTitle("مختبر الواقع المعزز")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.stop() }
    }

    private var objectCountLabel: some View {
        Label("المجسمات: \(model.objectCount)", systemImage: "cube.fill")
            .font(.subheadline.bold())
    }

    private var clearButton: some View {
        Button(role: .destructive) {
            model.clearObjects()
        } label: {
            Label("مسح المجسمات", systemImage: "trash")
                .font(.caption.bold())
        }
        .buttonStyle(.bordered)
        .disabled(model.objectCount == 0)
    }
}

struct ARPlaygroundContainer: UIViewRepresentable {
    @ObservedObject var model: ARPlaygroundViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        model.attach(to: arView)

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        context.coordinator.arView = arView
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    @MainActor
    final class Coordinator: NSObject {
        let model: ARPlaygroundViewModel
        weak var arView: ARView?

        init(model: ARPlaygroundViewModel) {
            self.model = model
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView else { return }
            model.placeObject(at: gesture.location(in: arView))
        }
    }
}

import RealityKit
import SwiftUI

struct ARPlaygroundView: View {
    @StateObject private var model = ARPlaygroundViewModel()
    @State private var showHelp = false

    var body: some View {
        ZStack {
            ARPlaygroundContainer(model: model)
                .ignoresSafeArea(edges: .bottom)

            VStack {
                HStack {
                    LiveCameraStatusBadge(
                        title: "\(model.objectCount) مجسم",
                        detail: model.statusMessage,
                        systemImage: "cube.fill",
                        accent: .cyan
                    )
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .allowsHitTesting(false)

            HStack {
                Spacer()
                VStack {
                    LiveCameraSideRail {
                        LiveCameraSideButton(
                            systemImage: "questionmark.circle",
                            accessibilityLabel: "طريقة الاستخدام",
                            isSelected: showHelp
                        ) {
                            showHelp.toggle()
                        }

                        LiveCameraSideButton(
                            systemImage: "trash",
                            accessibilityLabel: "مسح المجسمات",
                            tint: .red,
                            isEnabled: model.objectCount > 0
                        ) {
                            model.clearObjects()
                        }
                    }
                    Spacer()
                }
                .padding(.top, 66)
                .padding(.bottom, 80)
            }
            .padding(.trailing, 10)

            if showHelp {
                HStack {
                    Spacer(minLength: 14)
                    LiveCameraFloatingPanel(
                        title: "مختبر الواقع المعزز",
                        systemImage: "hand.tap",
                        onClose: { showHelp = false }
                    ) {
                        Text("المس أي سطح ظاهر في الكاميرا لإضافة مجسم. استخدم زر الحذف على جانب الشاشة لمسح كل المجسمات.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Color.clear.frame(width: 62)
                }
                .padding(.horizontal, 10)
            }
        }
        .background(.black)
        .navigationTitle("مختبر الواقع المعزز")
        .navigationBarTitleDisplayMode(.inline)
        .keepScreenAwakeForLiveTool(id: "playground.live")
        .onDisappear { model.stop() }
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

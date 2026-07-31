import RealityKit
import SwiftUI

struct SceneMeshView: View {
    @StateObject private var model = SceneMeshViewModel()
    @State private var showMesh = true

    var body: some View {
        ZStack {
            SceneMeshARViewContainer(model: model, showMesh: $showMesh)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 12) {
                HStack {
                    Toggle("إظهار الشبكة", isOn: $showMesh)
                        .font(.subheadline.bold())

                    Spacer()

                    Button {
                        model.run(reset: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                Spacer()

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        MetricChip(title: "الأجزاء", value: "\(model.anchorCount)", systemImage: "square.stack.3d.up")
                        MetricChip(title: "الرؤوس", value: formatted(model.vertexCount), systemImage: "circle.grid.3x3")
                        MetricChip(title: "المثلثات", value: formatted(model.faceCount), systemImage: "triangle")
                    }

                    HStack {
                        Label("التتبع: \(model.trackingState)", systemImage: "location.viewfinder")
                            .font(.caption.bold())
                        Spacer()
                        Text("تحرّك ببطء حول المكان")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(14)
        }
        .background(.black)
        .navigationTitle("شبكة المكان")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.stop() }
        .alert("تعذر تشغيل الشبكة", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "خطأ غير معروف")
        }
    }

    private func formatted(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName))
    }
}

struct SceneMeshARViewContainer: UIViewRepresentable {
    @ObservedObject var model: SceneMeshViewModel
    @Binding var showMesh: Bool

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        updateDebugOptions(for: arView)
        model.attach(to: arView)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        updateDebugOptions(for: uiView)
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Void) {
        uiView.session.pause()
    }

    private func updateDebugOptions(for arView: ARView) {
        if showMesh {
            arView.debugOptions.insert(.showSceneUnderstanding)
        } else {
            arView.debugOptions.remove(.showSceneUnderstanding)
        }
    }
}

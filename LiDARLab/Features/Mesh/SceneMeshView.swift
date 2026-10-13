import RealityKit
import SwiftUI

struct SceneMeshView: View {
    private enum Panel { case controls, metrics }

    @StateObject private var model = SceneMeshViewModel()
    @State private var showMesh = true
    @State private var panel: Panel?

    var body: some View {
        ZStack {
            SceneMeshARViewContainer(model: model, showMesh: $showMesh)
                .ignoresSafeArea(edges: .bottom)

            VStack {
                HStack {
                    LiveCameraStatusBadge(
                        title: "\(model.faceCount.formatted(.number.notation(.compactName))) مثلث",
                        detail: "AR: \(model.trackingState)",
                        systemImage: "cube.transparent"
                    )
                    Spacer()
                }
                .padding(.leading, 12)
                .padding(.top, 10)
                Spacer()
            }

            HStack {
                Spacer()
                LiveCameraSideRail {
                    LiveCameraSideButton(systemImage: "slider.horizontal.3", accessibilityLabel: "إعدادات الشبكة", isSelected: panel == .controls) { toggle(.controls) }
                    LiveCameraSideButton(systemImage: "chart.bar.xaxis", accessibilityLabel: "إحصائيات الشبكة", isSelected: panel == .metrics) { toggle(.metrics) }
                    LiveCameraSideButton(systemImage: "arrow.clockwise", accessibilityLabel: "إعادة المسح") { model.run(reset: true) }
                }
                .padding(.trailing, 10)
            }

            if let panel {
                HStack {
                    Spacer()
                    panelView(panel).padding(.trailing, 72)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(.black)
        .navigationTitle("شبكة المكان")
        .navigationBarTitleDisplayMode(.inline)
        .keepScreenAwakeForLiveTool(id: "mesh.live")
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

    private func toggle(_ newPanel: Panel) { panel = panel == newPanel ? nil : newPanel }

    @ViewBuilder
    private func panelView(_ panel: Panel) -> some View {
        switch panel {
        case .controls:
            LiveCameraFloatingPanel(title: "إعدادات الشبكة", systemImage: "slider.horizontal.3", onClose: { self.panel = nil }) {
                Toggle("إظهار شبكة المكان", isOn: $showMesh)
                Text("أخفِ الشبكة مؤقتًا لرؤية الكاميرا بوضوح من غير إيقاف جلسة المسح.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .metrics:
            LiveCameraFloatingPanel(title: "إحصائيات الشبكة", systemImage: "chart.bar.xaxis", onClose: { self.panel = nil }) {
                VStack(spacing: 10) {
                    MetricChip(title: "الأجزاء", value: "\(model.anchorCount)", systemImage: "square.stack.3d.up")
                    MetricChip(title: "الرؤوس", value: model.vertexCount.formatted(.number.notation(.compactName)), systemImage: "circle.grid.3x3")
                    MetricChip(title: "المثلثات", value: model.faceCount.formatted(.number.notation(.compactName)), systemImage: "triangle")
                    Text("تحرّك ببطء حول المكان لتحسين التغطية.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
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

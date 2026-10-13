import ARKit
import SceneKit
import SwiftUI

private enum PointCloudColorMode: String, CaseIterable, Identifiable {
    case depth, confidence, monochrome
    var id: String { rawValue }
    var title: String {
        switch self {
        case .depth: "المسافة"
        case .confidence: "الثقة"
        case .monochrome: "لون واحد"
        }
    }
}

private enum PointCloudDensity: String, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var title: String {
        switch self {
        case .low: "خفيفة"
        case .medium: "متوسطة"
        case .high: "عالية"
        }
    }
    var samplingStep: Int {
        switch self {
        case .low: 8
        case .medium: 6
        case .high: 4
        }
    }
}

struct PointCloudView: View {
    private enum Panel { case controls, metrics }

    @StateObject private var model = PointCloudViewModel()
    @State private var accumulatesPoints = true
    @State private var highConfidenceOnly = false
    @State private var colorMode: PointCloudColorMode = .depth
    @State private var density: PointCloudDensity = .medium
    @State private var pointSize = 5.0
    @State private var panel: Panel?

    var body: some View {
        ZStack {
            PointCloudARViewContainer(
                model: model,
                accumulatesPoints: accumulatesPoints,
                highConfidenceOnly: highConfidenceOnly,
                colorMode: colorMode,
                density: density,
                pointSize: pointSize
            )
            .ignoresSafeArea(edges: .bottom)

            VStack {
                HStack {
                    LiveCameraStatusBadge(
                        title: "\(model.pointCount.formatted(.number.notation(.compactName))) نقطة",
                        detail: "AR: \(model.trackingState)",
                        systemImage: "circle.grid.3x3.fill"
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
                    LiveCameraSideButton(systemImage: "slider.horizontal.3", accessibilityLabel: "إعدادات السحابة", isSelected: panel == .controls) { toggle(.controls) }
                    LiveCameraSideButton(systemImage: "chart.bar.xaxis", accessibilityLabel: "إحصائيات السحابة", isSelected: panel == .metrics) { toggle(.metrics) }
                    LiveCameraSideButton(systemImage: "trash", accessibilityLabel: "مسح النقاط", tint: .red) { model.clearCloud() }
                }
                .padding(.trailing, 10)
            }

            if let panel {
                HStack {
                    Spacer()
                    panelView(panel)
                        .padding(.trailing, 72)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(.black)
        .navigationTitle("السحابة النقطية")
        .navigationBarTitleDisplayMode(.inline)
        .keepScreenAwakeForLiveTool(id: "pointcloud.live")
        .onDisappear { model.stop() }
        .alert("تعذر تشغيل السحابة النقطية", isPresented: Binding(
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
            LiveCameraFloatingPanel(title: "إعدادات السحابة", systemImage: "slider.horizontal.3", onClose: { self.panel = nil }) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("تجميع النقاط", isOn: $accumulatesPoints)
                    Toggle("ثقة مرتفعة فقط", isOn: $highConfidenceOnly)
                    Picker("التلوين", selection: $colorMode) {
                        ForEach(PointCloudColorMode.allCases) { item in Text(item.title).tag(item) }
                    }
                    Picker("الكثافة", selection: $density) {
                        ForEach(PointCloudDensity.allCases) { item in Text(item.title).tag(item) }
                    }
                    HStack {
                        Text("حجم النقطة")
                        Slider(value: $pointSize, in: 2...10, step: 1)
                        Text("\(Int(pointSize))").font(.caption.monospacedDigit())
                    }
                }
            }
        case .metrics:
            LiveCameraFloatingPanel(title: "إحصائيات السحابة", systemImage: "chart.bar.xaxis", onClose: { self.panel = nil }) {
                VStack(spacing: 10) {
                    MetricChip(title: "النقاط", value: model.pointCount.formatted(.number.notation(.compactName)), systemImage: "circle.grid.3x3.fill")
                    MetricChip(title: "الإطارات", value: "\(model.processedFrameCount)", systemImage: "rectangle.stack")
                    MetricChip(title: "المعدل", value: String(format: "%.1f Hz", model.processingRate), systemImage: "speedometer")
                    Text(accumulatesPoints ? "تحرّك ببطء لبناء السحابة." : "عرض مباشر للإطار الحالي.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct PointCloudARViewContainer: UIViewRepresentable {
    @ObservedObject var model: PointCloudViewModel
    let accumulatesPoints: Bool
    let highConfidenceOnly: Bool
    let colorMode: PointCloudColorMode
    let density: PointCloudDensity
    let pointSize: Double

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = false
        view.antialiasingMode = .multisampling2X
        model.attach(to: view)
        updateSettings()
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) { updateSettings() }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Void) {
        uiView.session.pause()
    }

    private func updateSettings() {
        model.updateSettings(
            accumulatesPoints: accumulatesPoints,
            highConfidenceOnly: highConfidenceOnly,
            colorMode: colorMode.rawValue,
            samplingStep: density.samplingStep,
            pointSize: CGFloat(pointSize)
        )
    }
}

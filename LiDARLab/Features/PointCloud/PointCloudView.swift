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
    @StateObject private var model = PointCloudViewModel()
    @State private var accumulatesPoints = true
    @State private var highConfidenceOnly = false
    @State private var colorMode: PointCloudColorMode = .depth
    @State private var density: PointCloudDensity = .medium
    @State private var pointSize = 5.0

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

            VStack(spacing: 12) {
                controls
                Spacer()
                metricsPanel
            }
            .padding(12)
        }
        .background(.black)
        .navigationTitle("السحابة النقطية")
        .navigationBarTitleDisplayMode(.inline)
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

    private var controls: some View {
        VStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Toggle("تجميع النقاط", isOn: $accumulatesPoints)
                    Toggle("ثقة مرتفعة فقط", isOn: $highConfidenceOnly)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("تجميع النقاط", isOn: $accumulatesPoints)
                    Toggle("ثقة مرتفعة فقط", isOn: $highConfidenceOnly)
                }
            }
            .font(.subheadline.bold())

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    menuPicker(title: "التلوين", value: colorMode.title) {
                        ForEach(PointCloudColorMode.allCases) { item in
                            Button(item.title) { colorMode = item }
                        }
                    }
                    menuPicker(title: "الكثافة", value: density.title) {
                        ForEach(PointCloudDensity.allCases) { item in
                            Button(item.title) { density = item }
                        }
                    }
                    Spacer(minLength: 6)
                    resetButton
                }

                VStack(spacing: 9) {
                    HStack(spacing: 10) {
                        menuPicker(title: "التلوين", value: colorMode.title) {
                            ForEach(PointCloudColorMode.allCases) { item in
                                Button(item.title) { colorMode = item }
                            }
                        }
                        menuPicker(title: "الكثافة", value: density.title) {
                            ForEach(PointCloudDensity.allCases) { item in
                                Button(item.title) { density = item }
                            }
                        }
                    }
                    resetButton.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "circle.fill")
                    .font(.system(size: pointSize))
                Slider(value: $pointSize, in: 2...10, step: 1)
                Text("\(Int(pointSize))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 22)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("حجم النقطة")
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var resetButton: some View {
        Button { model.clearCloud() } label: {
            Label("مسح النقاط", systemImage: "trash")
                .font(.caption.bold())
        }
        .buttonStyle(.bordered)
    }

    private func menuPicker<MenuContent: View>(
        title: String,
        value: String,
        @ViewBuilder content: () -> MenuContent
    ) -> some View {
        Menu(content: content) {
            HStack(spacing: 5) {
                Text(title).foregroundStyle(.secondary)
                Text(value).fontWeight(.semibold)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var metricsPanel: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 8)], spacing: 8) {
                MetricChip(title: "النقاط", value: model.pointCount.formatted(.number.notation(.compactName)), systemImage: "circle.grid.3x3.fill")
                MetricChip(title: "الإطارات", value: "\(model.processedFrameCount)", systemImage: "rectangle.stack")
                MetricChip(title: "المعدل", value: String(format: "%.1f Hz", model.processingRate), systemImage: "speedometer")
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    Label("التتبع: \(model.trackingState)", systemImage: "location.viewfinder")
                    Spacer(minLength: 8)
                    Text(accumulatesPoints ? "تحرّك ببطء لبناء السحابة" : "عرض مباشر للإطار الحالي")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label("التتبع: \(model.trackingState)", systemImage: "location.viewfinder")
                    Text(accumulatesPoints ? "تحرّك ببطء لبناء السحابة" : "عرض مباشر للإطار الحالي")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

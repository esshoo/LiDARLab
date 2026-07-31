import RealityKit
import SwiftUI

private enum LevelToolMode: String, CaseIterable, Identifiable {
    case automatic
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "تلقائي"
        case .manual: "يدوي"
        }
    }
}

struct LevelToolView: View {
    @StateObject private var model = LevelToolViewModel()
    @State private var mode: LevelToolMode = .automatic
    @State private var manualCenter = CGPoint(x: 0.5, y: 0.5)
    @State private var manualAngleDegrees: Double = 0

    private var activeLineAngle: Double? {
        switch mode {
        case .automatic:
            model.selectedLine?.angleDegrees
        case .manual:
            manualAngleDegrees
        }
    }

    private var measurement: LevelMeasurement? {
        guard let activeLineAngle else { return nil }
        return LevelMeasurement.calculate(
            lineAngle: activeLineAngle,
            horizonAngle: model.horizonAngleDegrees
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LevelARViewContainer(model: model, automaticMode: mode == .automatic)
                    .ignoresSafeArea(edges: .bottom)

                if mode == .manual {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture().onEnded { value in
                                manualCenter = normalized(value.location, in: geometry.size)
                            }
                        )
                }

                ReferenceAxesOverlay(
                    horizonAngleDegrees: model.horizonAngleDegrees,
                    isLevel: measurement?.isLevel == true
                )
                .allowsHitTesting(false)

                if mode == .automatic {
                    DetectedRectanglesOverlay(
                        rectangles: model.rectangles,
                        selectedID: model.selectedRectangleID,
                        selectedLine: model.selectedLine
                    )
                    .allowsHitTesting(false)
                } else {
                    ManualLevelLineOverlay(
                        center: $manualCenter,
                        angleDegrees: $manualAngleDegrees
                    )
                }

                VStack(spacing: 12) {
                    controls
                    Spacer(minLength: 90)
                    measurementPanel
                }
                .padding(.horizontal, adaptiveHorizontalPadding(for: geometry.size.width))
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
        }
        .background(.black)
        .navigationTitle("ميزان الميل والزاوية")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: mode) { _, newMode in
            if newMode == .manual {
                model.clearSelection()
            }
        }
        .onDisappear {
            model.stop()
        }
        .alert("تعذر تشغيل أداة الميل", isPresented: Binding(
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
            Picker("طريقة القياس", selection: $mode) {
                ForEach(LevelToolMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    modeActions
                    Spacer(minLength: 8)
                    trackingLabel
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        modeActions
                        Spacer(minLength: 0)
                    }
                    trackingLabel
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var modeActions: some View {
        if mode == .automatic {
            Button {
                model.scanForRectangles()
            } label: {
                Label(model.isDetecting ? "جاري الاكتشاف" : "اكتشاف اللوحة", systemImage: model.isDetecting ? "viewfinder.circle" : "viewfinder")
                    .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isDetecting)

            Button {
                model.clearSelection()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
            .disabled(model.rectangles.isEmpty)
        } else {
            Button {
                manualCenter = CGPoint(x: 0.5, y: 0.5)
                manualAngleDegrees = model.horizonAngleDegrees
            } label: {
                Label("محاذاة مع الأفقي", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var trackingLabel: some View {
        HStack(spacing: 8) {
            Label("التتبع: \(model.trackingState)", systemImage: "location.viewfinder")
            Text("•")
                .foregroundStyle(.tertiary)
            Text(model.gravityReliabilityText)
        }
        .font(.caption.bold())
        .lineLimit(2)
        .minimumScaleFactor(0.75)
    }

    private var measurementPanel: some View {
        VStack(spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: measurement?.isLevel == true ? "checkmark.circle.fill" : "angle")
                    .font(.title2)
                    .foregroundStyle(measurement?.isLevel == true ? .green : .orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text(measurement?.statusText ?? model.statusMessage)
                        .font(.headline)
                    Text(instructionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 9)], spacing: 9) {
                MetricChip(
                    title: "الميل عن الأفقي",
                    value: measurement.map { signedDegrees($0.signedHorizontalDeviation) } ?? "—",
                    systemImage: "arrow.left.and.right"
                )
                MetricChip(
                    title: "الزاوية مع الرأسي",
                    value: measurement.map { degrees($0.verticalAngle) } ?? "—",
                    systemImage: "arrow.up.and.down"
                )
                MetricChip(
                    title: "خط الجاذبية",
                    value: degrees(model.horizonAngleDegrees),
                    systemImage: "level"
                )
            }

            if mode == .manual {
                HStack(spacing: 10) {
                    Image(systemName: "rotate.right")
                    Slider(value: $manualAngleDegrees, in: -90...90, step: 0.1)
                    Text(degrees(manualAngleDegrees))
                        .font(.caption.monospacedDigit().bold())
                        .frame(minWidth: 54, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var instructionText: String {
        switch mode {
        case .automatic:
            model.selectedRectangle == nil
                ? "اضغط مباشرة على اللوحة، أو استخدم زر الاكتشاف."
                : "الخط البرتقالي يمثل أقرب ضلع أفقي للعنصر المكتشف."
        case .manual:
            "اضغط لنقل الخط، واسحب الدائرة الصغيرة لتغيير زاويته."
        }
    }

    private func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(
            x: min(max(point.x / size.width, 0.03), 0.97),
            y: min(max(point.y / size.height, 0.08), 0.92)
        )
    }

    private func degrees(_ value: Double) -> String {
        String(format: "%.1f°", value)
    }

    private func signedDegrees(_ value: Double) -> String {
        String(format: "%+.1f°", value)
    }

    private func adaptiveHorizontalPadding(for width: CGFloat) -> CGFloat {
        width >= 900 ? 28 : (width >= 600 ? 20 : 12)
    }
}

private struct ReferenceAxesOverlay: View {
    let horizonAngleDegrees: Double
    let isLevel: Bool

    var body: some View {
        GeometryReader { geometry in
            let length = hypot(geometry.size.width, geometry.size.height) * 1.35

            ZStack {
                Rectangle()
                    .fill(isLevel ? Color.green : Color.white.opacity(0.92))
                    .frame(width: length, height: 1.5)
                    .rotationEffect(.degrees(horizonAngleDegrees))
                    .shadow(color: .black.opacity(0.75), radius: 1)

                Rectangle()
                    .fill(Color.cyan.opacity(0.92))
                    .frame(width: length, height: 1.5)
                    .rotationEffect(.degrees(horizonAngleDegrees + 90))
                    .shadow(color: .black.opacity(0.75), radius: 1)

                Circle()
                    .stroke(isLevel ? Color.green : Color.white, lineWidth: 1.5)
                    .frame(width: 18, height: 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct DetectedRectanglesOverlay: View {
    let rectangles: [DetectedLevelRectangle]
    let selectedID: UUID?
    let selectedLine: LevelLine?

    var body: some View {
        Canvas { context, _ in
            for rectangle in rectangles {
                var path = Path()
                path.move(to: rectangle.topLeft)
                path.addLine(to: rectangle.topRight)
                path.addLine(to: rectangle.bottomRight)
                path.addLine(to: rectangle.bottomLeft)
                path.closeSubpath()

                let isSelected = rectangle.id == selectedID
                context.stroke(
                    path,
                    with: .color(isSelected ? .green : .yellow.opacity(0.75)),
                    lineWidth: isSelected ? 3 : 1.5
                )
            }

            if let selectedLine {
                var line = Path()
                line.move(to: selectedLine.start)
                line.addLine(to: selectedLine.end)
                context.stroke(line, with: .color(.orange), style: StrokeStyle(lineWidth: 5, lineCap: .round))

                context.fill(
                    Path(ellipseIn: CGRect(x: selectedLine.start.x - 6, y: selectedLine.start.y - 6, width: 12, height: 12)),
                    with: .color(.orange)
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: selectedLine.end.x - 6, y: selectedLine.end.y - 6, width: 12, height: 12)),
                    with: .color(.orange)
                )
            }
        }
    }
}

private struct ManualLevelLineOverlay: View {
    @Binding var center: CGPoint
    @Binding var angleDegrees: Double

    var body: some View {
        GeometryReader { geometry in
            let actualCenter = CGPoint(
                x: center.x * geometry.size.width,
                y: center.y * geometry.size.height
            )
            let angleRadians = angleDegrees * .pi / 180
            let lineLength = hypot(geometry.size.width, geometry.size.height) * 1.4
            let handleDistance = min(max(min(geometry.size.width, geometry.size.height) * 0.24, 72), 132)
            let rotationHandle = CGPoint(
                x: actualCenter.x + CGFloat(cos(angleRadians)) * handleDistance,
                y: actualCenter.y + CGFloat(sin(angleRadians)) * handleDistance
            )

            ZStack {
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: lineLength, height: 4)
                    .rotationEffect(.degrees(angleDegrees))
                    .position(actualCenter)
                    .shadow(color: .black.opacity(0.7), radius: 2)
                    .allowsHitTesting(false)

                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(Color.orange, lineWidth: 3))
                    .frame(width: 34, height: 34)
                    .position(actualCenter)
                    .contentShape(Circle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                center = normalized(value.location, size: geometry.size)
                            }
                    )

                Circle()
                    .fill(Color.orange)
                    .overlay(Image(systemName: "rotate.right").font(.caption.bold()).foregroundStyle(.black))
                    .frame(width: 34, height: 34)
                    .position(rotationHandle)
                    .contentShape(Circle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let dx = value.location.x - actualCenter.x
                                let dy = value.location.y - actualCenter.y
                                angleDegrees = normalizedAxisAngle(Double(atan2(dy, dx)) * 180 / Double.pi)
                            }
                    )
            }
        }
    }

    private func normalized(_ point: CGPoint, size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return center }
        return CGPoint(
            x: min(max(point.x / size.width, 0.03), 0.97),
            y: min(max(point.y / size.height, 0.08), 0.92)
        )
    }

    private func normalizedAxisAngle(_ angle: Double) -> Double {
        var value = angle
        while value > 90 { value -= 180 }
        while value < -90 { value += 180 }
        return value
    }
}

private struct LevelARViewContainer: UIViewRepresentable {
    @ObservedObject var model: LevelToolViewModel
    let automaticMode: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, automaticMode: automaticMode)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        model.attach(to: arView)

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        context.coordinator.arView = arView
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.automaticMode = automaticMode
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    @MainActor
    final class Coordinator: NSObject {
        let model: LevelToolViewModel
        weak var arView: ARView?
        var automaticMode: Bool

        init(model: LevelToolViewModel, automaticMode: Bool) {
            self.model = model
            self.automaticMode = automaticMode
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard automaticMode, let arView else { return }
            model.handleTap(at: gesture.location(in: arView))
        }
    }
}

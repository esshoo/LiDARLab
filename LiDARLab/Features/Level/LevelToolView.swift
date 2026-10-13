import RealityKit
import SwiftUI
import UIKit

fileprivate enum LevelToolMode: String, CaseIterable, Identifiable {
    case automatic
    case fourPoints
    case manualLine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "تلقائي"
        case .fourPoints: "4 نقاط"
        case .manualLine: "خط يدوي"
        }
    }
}

struct LevelToolView: View {
    private enum Panel { case mode, result }

    @StateObject private var model = LevelToolViewModel()
    @State private var mode: LevelToolMode = .automatic
    @State private var manualCenter = CGPoint(x: 0.5, y: 0.5)
    @State private var manualAngleDegrees: Double = 0
    @State private var lastLevelState = false
    @State private var panel: Panel?

    private var measurement: LevelMeasurement? {
        switch mode {
        case .automatic, .fourPoints:
            model.automaticMeasurement
        case .manualLine:
            LevelMeasurement.screenMeasurement(
                lineAngle: manualAngleDegrees,
                horizonAngle: model.horizonAngleDegrees
            )
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LevelARViewContainer(model: model, mode: mode)
                    .ignoresSafeArea(edges: .bottom)

                if mode == .manualLine {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture().onEnded { value in
                                manualCenter = normalized(value.location, in: geometry.size)
                            }
                        )
                }

                if let screenAxes = model.screenReferenceAxes {
                    ReferenceAxesOverlay(axes: screenAxes, isLevel: measurement?.isLevel == true, style: .screenCompass)
                        .allowsHitTesting(false)
                }

                if let wallAxes = model.wallReferenceAxes, mode != .manualLine {
                    ReferenceAxesOverlay(axes: wallAxes, isLevel: measurement?.isLevel == true, style: .wallAnchor)
                        .allowsHitTesting(false)
                }

                if let target = model.target, mode != .manualLine {
                    TrackedTargetOverlay(target: target)
                        .allowsHitTesting(false)
                }

                if mode == .fourPoints, !model.draftCornerPoints.isEmpty {
                    DraftCornersOverlay(points: model.draftCornerPoints)
                        .allowsHitTesting(false)
                }

                if mode == .manualLine {
                    ManualLevelLineOverlay(center: $manualCenter, angleDegrees: $manualAngleDegrees)
                }

                VStack {
                    HStack {
                        LiveCameraStatusBadge(
                            title: measurement?.statusText ?? model.statusMessage,
                            detail: "\(mode.title) • AR: \(model.trackingState)",
                            systemImage: measurement?.isLevel == true ? "checkmark.circle.fill" : "level",
                            accent: measurement?.isLevel == true ? .green : .orange
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
                        LiveCameraSideButton(systemImage: "slider.horizontal.3", accessibilityLabel: "وضع القياس", isSelected: panel == .mode) { toggle(.mode) }
                        LiveCameraSideButton(systemImage: "chart.bar.xaxis", accessibilityLabel: "نتيجة القياس", isSelected: panel == .result) { toggle(.result) }
                        if mode == .fourPoints {
                            LiveCameraSideButton(systemImage: "arrow.uturn.backward", accessibilityLabel: "تراجع", isEnabled: !model.draftCornerPoints.isEmpty) { model.undoDraftCorner() }
                        }
                        LiveCameraSideButton(systemImage: "xmark", accessibilityLabel: "مسح التحديد", tint: .red) {
                            if mode == .fourPoints { model.beginFourPointSelection() } else { model.clearSelection() }
                        }
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

                VStack {
                    Spacer()
                    primaryBar
                        .padding(.bottom, 12)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: panel != nil)
        }
        .background(.black)
        .navigationTitle("ميزان الميل والزاوية")
        .navigationBarTitleDisplayMode(.inline)
        .keepScreenAwakeForLiveTool(id: "level.live")
        .onChange(of: mode) { _, newMode in
            switch newMode {
            case .automatic:
                model.clearSelection()
            case .fourPoints:
                model.beginFourPointSelection()
            case .manualLine:
                model.clearSelection()
                manualCenter = CGPoint(x: 0.5, y: 0.5)
                manualAngleDegrees = model.horizonAngleDegrees
            }
        }
        .onChange(of: measurement?.isLevel) { _, isLevel in
            guard isLevel == true, !lastLevelState else {
                lastLevelState = isLevel == true
                return
            }
            lastLevelState = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        .onDisappear { model.stop() }
        .alert("تعذر تشغيل أداة الميل", isPresented: Binding(
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
    private var primaryBar: some View {
        switch mode {
        case .automatic:
            LiveCameraBottomBar {
                Button {
                    model.scanForRectangle()
                } label: {
                    Label(model.isDetecting ? "جاري التحديد" : "تحديد من المنتصف", systemImage: model.isDetecting ? "viewfinder.circle" : "viewfinder")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isDetecting)
            }
        case .fourPoints:
            LiveCameraStatusBadge(
                title: "اضغط الزوايا الأربع على الشكل",
                detail: "\(model.draftCornerPoints.count) / 4",
                systemImage: "rectangle.dashed"
            )
        case .manualLine:
            LiveCameraBottomBar {
                Button {
                    manualCenter = CGPoint(x: 0.5, y: 0.5)
                    manualAngleDegrees = model.horizonAngleDegrees
                } label: {
                    Label("محاذاة بالأفقي", systemImage: "level")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func panelView(_ panel: Panel) -> some View {
        switch panel {
        case .mode:
            LiveCameraFloatingPanel(title: "طريقة القياس", systemImage: "slider.horizontal.3", onClose: { self.panel = nil }) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("طريقة القياس", selection: $mode) {
                        ForEach(LevelToolMode.allCases) { item in Text(item.title).tag(item) }
                    }
                    .pickerStyle(.segmented)
                    Text(instructionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if mode == .manualLine {
                        HStack {
                            Image(systemName: "rotate.right")
                            Slider(value: $manualAngleDegrees, in: -90...90, step: 0.1)
                            Text(degrees(manualAngleDegrees))
                                .font(.caption.monospacedDigit().bold())
                        }
                    }
                }
            }
        case .result:
            LiveCameraFloatingPanel(title: "القياس", systemImage: "chart.bar.xaxis", onClose: { self.panel = nil }) {
                VStack(spacing: 10) {
                    MetricChip(title: "الميل عن الأفقي", value: measurement.map { signedDegrees($0.signedHorizontalDeviation) } ?? "—", systemImage: "arrow.left.and.right")
                    MetricChip(title: "الانحراف عن الرأسي", value: measurement.map { signedDegrees($0.signedVerticalDeviation) } ?? "—", systemImage: "arrow.up.and.down")
                    MetricChip(title: "ثقة التتبع", value: confidenceText, systemImage: "scope")
                    Text(model.gravityReliabilityText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var instructionText: String {
        switch mode {
        case .automatic:
            model.target == nil ? "ضع العنصر قرب المنتصف ثم اضغط تحديد." : "تم تثبيت العنصر؛ حرّك الجهاز لمتابعة الميل."
        case .fourPoints:
            model.target == nil ? "اضغط الزوايا الأربع حول الشكل." : "النقاط مثبتة في العالم الحقيقي."
        case .manualLine:
            "اضغط لنقل الخط واسحب دائرة التدوير أو استخدم شريط الزاوية."
        }
    }

    private var confidenceText: String {
        guard let target = model.target else { return mode == .manualLine ? "يدوي" : "—" }
        return String(format: "%.0f%%", target.confidence * 100)
    }

    private func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(
            x: min(max(point.x / size.width, 0.03), 0.97),
            y: min(max(point.y / size.height, 0.08), 0.92)
        )
    }

    private func degrees(_ value: Double) -> String { String(format: "%.1f°", value) }
    private func signedDegrees(_ value: Double) -> String { String(format: "%+.2f°", value) }
}

private struct ReferenceAxesOverlay: View {
    enum Style: Equatable {
        case screenCompass
        case wallAnchor
    }

    let axes: ProjectedReferenceAxes
    let isLevel: Bool
    let style: Style

    var body: some View {
        Canvas { context, _ in
            var horizontal = Path()
            horizontal.move(to: axes.horizontal.start)
            horizontal.addLine(to: axes.horizontal.end)

            var vertical = Path()
            vertical.move(to: axes.vertical.start)
            vertical.addLine(to: axes.vertical.end)

            let horizontalColor: Color = isLevel ? .green : (style == .screenCompass ? .white : .yellow)
            let verticalColor: Color = style == .screenCompass ? .cyan : .mint
            let lineWidth: CGFloat = style == .screenCompass ? 2 : 3
            let dash: [CGFloat] = style == .screenCompass ? [] : [9, 6]

            context.stroke(
                horizontal,
                with: .color(horizontalColor.opacity(style == .screenCompass ? 0.94 : 0.92)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: dash)
            )
            context.stroke(
                vertical,
                with: .color(verticalColor.opacity(style == .screenCompass ? 0.94 : 0.92)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: dash)
            )

            let radius: CGFloat = style == .screenCompass ? 9 : 7
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: axes.origin.x - radius,
                    y: axes.origin.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )),
                with: .color(horizontalColor),
                lineWidth: 1.5
            )
        }
    }
}

private struct TrackedTargetOverlay: View {
    let target: TrackedLevelTarget

    var body: some View {
        ZStack {
            Canvas { context, _ in
                guard target.corners.count == 4 else { return }

                var outline = Path()
                outline.move(to: target.corners[0])
                for point in target.corners.dropFirst() {
                    outline.addLine(to: point)
                }
                outline.closeSubpath()
                context.stroke(outline, with: .color(.green), style: StrokeStyle(lineWidth: 3, lineJoin: .round))

                var horizontal = Path()
                horizontal.move(to: target.horizontalLine.start)
                horizontal.addLine(to: target.horizontalLine.end)
                context.stroke(horizontal, with: .color(.orange), style: StrokeStyle(lineWidth: 5, lineCap: .round))

                var vertical = Path()
                vertical.move(to: target.verticalLine.start)
                vertical.addLine(to: target.verticalLine.end)
                context.stroke(vertical, with: .color(.purple), style: StrokeStyle(lineWidth: 5, lineCap: .round))

                for point in target.corners {
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)),
                        with: .color(.green)
                    )
                }
            }

            angleBadge(
                text: String(format: "%+.1f° أفقي", target.measurement.signedHorizontalDeviation),
                color: target.measurement.isLevel ? .green : .orange
            )
            .position(target.horizontalLine.midpoint)

            angleBadge(
                text: String(format: "%+.1f° رأسي", target.measurement.signedVerticalDeviation),
                color: .purple
            )
            .position(target.verticalLine.midpoint)
        }
    }

    private func angleBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit().bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(color, lineWidth: 1.5))
            .offset(y: -18)
    }
}

private struct DraftCornersOverlay: View {
    let points: [CGPoint]

    var body: some View {
        Canvas { context, _ in
            if let first = points.first {
                var path = Path()
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(.yellow), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            }

            for (index, point) in points.enumerated() {
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22)),
                    with: .color(.yellow)
                )
                context.draw(
                    Text("\(index + 1)").font(.caption2.bold()).foregroundStyle(.black),
                    at: point
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
            let lineLength = hypot(geometry.size.width, geometry.size.height) * 1.45
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
                                angleDegrees = normalizedAxisAngle(Double(atan2(dy, dx)) * 180 / .pi)
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
    let mode: LevelToolMode

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, mode: mode)
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
        context.coordinator.mode = mode
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    @MainActor
    final class Coordinator: NSObject {
        let model: LevelToolViewModel
        weak var arView: ARView?
        var mode: LevelToolMode

        init(model: LevelToolViewModel, mode: LevelToolMode) {
            self.model = model
            self.mode = mode
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView else { return }
            let point = gesture.location(in: arView)
            switch mode {
            case .automatic:
                model.handleAutomaticTap(at: point)
            case .fourPoints:
                model.addFourPointCorner(at: point)
            case .manualLine:
                break
            }
        }
    }
}

import ARKit
import SceneKit
import SwiftUI

internal enum SurfaceClassKind: String, CaseIterable, Identifiable {
    case wall, floor, ceiling, table, seat, window, door, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wall: "جدار"
        case .floor: "أرضية"
        case .ceiling: "سقف"
        case .table: "طاولة"
        case .seat: "مقعد"
        case .window: "نافذة"
        case .door: "باب"
        case .none: "غير مصنف"
        }
    }

    var systemImage: String {
        switch self {
        case .wall: "rectangle.portrait"
        case .floor: "square.split.bottomrightquarter"
        case .ceiling: "rectangle.topthird.inset.filled"
        case .table: "table.furniture"
        case .seat: "chair.lounge"
        case .window: "window.vertical.closed"
        case .door: "door.left.hand.closed"
        case .none: "questionmark.square.dashed"
        }
    }

    var color: Color {
        switch self {
        case .wall: .cyan
        case .floor: .green
        case .ceiling: .indigo
        case .table: .orange
        case .seat: .pink
        case .window: .blue
        case .door: .yellow
        case .none: .gray
        }
    }

    var uiColor: UIColor {
        switch self {
        case .wall: .systemCyan
        case .floor: .systemGreen
        case .ceiling: .systemIndigo
        case .table: .systemOrange
        case .seat: .systemPink
        case .window: .systemBlue
        case .door: .systemYellow
        case .none: .systemGray
        }
    }
}

private enum SurfaceClassificationFilter: String, CaseIterable, Identifiable {
    case all, wall, floor, ceiling, table, seat, window, door, none
    var id: String { rawValue }

    var title: String {
        if self == .all { return "كل الأنواع" }
        return SurfaceClassKind(rawValue: rawValue)?.title ?? rawValue
    }
}

struct SurfaceClassificationView: View {
    private enum Panel { case controls, summary }

    @StateObject private var model = SurfaceClassificationViewModel()
    @State private var filter: SurfaceClassificationFilter = .all
    @State private var showUnknown = false
    @State private var opacity = 0.46
    @State private var wireframe = false
    @State private var panel: Panel?

    var body: some View {
        ZStack {
            SurfaceClassificationARViewContainer(
                model: model,
                filter: filter.rawValue,
                showUnknown: showUnknown,
                opacity: opacity,
                wireframe: wireframe
            )
            .ignoresSafeArea(edges: .bottom)

            VStack {
                HStack {
                    LiveCameraStatusBadge(
                        title: model.classifiedPercentageText,
                        detail: "AR: \(model.trackingState)",
                        systemImage: "square.3.layers.3d"
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
                    LiveCameraSideButton(systemImage: "slider.horizontal.3", accessibilityLabel: "إعدادات التصنيف", isSelected: panel == .controls) { toggle(.controls) }
                    LiveCameraSideButton(systemImage: "chart.bar.xaxis", accessibilityLabel: "ملخص التصنيف", isSelected: panel == .summary) { toggle(.summary) }
                    LiveCameraSideButton(systemImage: "arrow.clockwise", accessibilityLabel: "إعادة المسح") { model.restart() }
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
        .navigationTitle("تصنيف الأسطح")
        .navigationBarTitleDisplayMode(.inline)
        .keepScreenAwakeForLiveTool(id: "classification.live")
        .onDisappear { model.stop() }
        .alert("تعذر تشغيل تصنيف الأسطح", isPresented: Binding(
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
            LiveCameraFloatingPanel(title: "إعدادات التصنيف", systemImage: "slider.horizontal.3", onClose: { self.panel = nil }) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("نوع السطح", selection: $filter) {
                        ForEach(SurfaceClassificationFilter.allCases) { item in Text(item.title).tag(item) }
                    }
                    Toggle("إظهار غير المصنف", isOn: $showUnknown)
                    Toggle("عرض شبكي", isOn: $wireframe)
                    HStack {
                        Text("الشفافية")
                        Slider(value: $opacity, in: 0.15...0.9)
                        Text("\(Int(opacity * 100))%")
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        case .summary:
            LiveCameraFloatingPanel(title: "ملخص التصنيف", systemImage: "chart.bar.xaxis", onClose: { self.panel = nil }) {
                VStack(spacing: 10) {
                    MetricChip(title: "الأجزاء", value: "\(model.anchorCount)", systemImage: "square.stack.3d.up")
                    MetricChip(title: "الوجوه", value: model.totalFaceCount.formatted(.number.notation(.compactName)), systemImage: "triangle")
                    MetricChip(title: "المصنف", value: model.classifiedPercentageText, systemImage: "tag")
                    Divider()
                    ForEach(SurfaceClassKind.allCases) { kind in
                        HStack {
                            Circle().fill(kind.color).frame(width: 9, height: 9)
                            Text(kind.title)
                            Spacer()
                            Text("\(model.classificationCounts[kind.rawValue, default: 0])")
                                .font(.caption.monospacedDigit().bold())
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }
}

private struct SurfaceClassificationARViewContainer: UIViewRepresentable {
    @ObservedObject var model: SurfaceClassificationViewModel
    let filter: String
    let showUnknown: Bool
    let opacity: Double
    let wireframe: Bool

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = false
        view.antialiasingMode = .multisampling2X
        model.attach(to: view)
        applySettings()
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) { applySettings() }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Void) {
        uiView.session.pause()
    }

    private func applySettings() {
        model.updateDisplaySettings(
            filter: filter,
            showUnknown: showUnknown,
            opacity: CGFloat(opacity),
            wireframe: wireframe
        )
    }
}

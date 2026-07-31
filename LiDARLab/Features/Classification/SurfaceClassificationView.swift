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
    @StateObject private var model = SurfaceClassificationViewModel()
    @State private var filter: SurfaceClassificationFilter = .all
    @State private var showUnknown = false
    @State private var opacity = 0.46
    @State private var wireframe = false

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

            VStack(spacing: 12) {
                controls
                Spacer()
                summaryPanel
            }
            .padding(12)
        }
        .background(.black)
        .navigationTitle("تصنيف الأسطح")
        .navigationBarTitleDisplayMode(.inline)
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

    private var controls: some View {
        VStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    filterMenu
                    Toggle("غير المصنف", isOn: $showUnknown)
                        .font(.caption.bold())
                    Toggle("شبكي", isOn: $wireframe)
                        .font(.caption.bold())
                    Spacer(minLength: 4)
                    restartButton
                }
                VStack(spacing: 9) {
                    HStack(spacing: 10) {
                        filterMenu
                        Toggle("غير المصنف", isOn: $showUnknown)
                            .font(.caption.bold())
                        Toggle("شبكي", isOn: $wireframe)
                            .font(.caption.bold())
                    }
                    restartButton.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "circle.lefthalf.filled")
                Slider(value: $opacity, in: 0.15...0.9)
                Text("\(Int(opacity * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 38)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("شفافية الأسطح")
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var filterMenu: some View {
        Menu {
            ForEach(SurfaceClassificationFilter.allCases) { item in
                Button {
                    filter = item
                } label: {
                    if filter == item {
                        Label(item.title, systemImage: "checkmark")
                    } else {
                        Text(item.title)
                    }
                }
            }
        } label: {
            Label(filter.title, systemImage: "line.3.horizontal.decrease.circle")
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var restartButton: some View {
        Button { model.restart() } label: {
            Label("إعادة المسح", systemImage: "arrow.clockwise")
                .font(.caption.bold())
        }
        .buttonStyle(.bordered)
    }

    private var summaryPanel: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                MetricChip(title: "الأجزاء", value: "\(model.anchorCount)", systemImage: "square.stack.3d.up")
                MetricChip(title: "الوجوه", value: model.totalFaceCount.formatted(.number.notation(.compactName)), systemImage: "triangle")
                MetricChip(title: "المصنف", value: model.classifiedPercentageText, systemImage: "tag")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SurfaceClassKind.allCases) { kind in
                        classificationChip(kind)
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    Label("التتبع: \(model.trackingState)", systemImage: "location.viewfinder")
                    Spacer(minLength: 8)
                    Text("وجّه الجهاز ببطء إلى الجدران والأرضية والأثاث")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label("التتبع: \(model.trackingState)", systemImage: "location.viewfinder")
                    Text("وجّه الجهاز ببطء إلى الجدران والأرضية والأثاث")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func classificationChip(_ kind: SurfaceClassKind) -> some View {
        HStack(spacing: 6) {
            Circle().fill(kind.color).frame(width: 9, height: 9)
            Text(kind.title)
            Text("\(model.classificationCounts[kind.rawValue, default: 0])")
                .font(.caption.monospacedDigit().bold())
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
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

import SwiftUI

struct DepthCameraView: View {
    private enum Panel { case controls, stats }

    @StateObject private var model = DepthSessionViewModel(generateHeatmap: true)
    @State private var overlayOpacity = 0.62
    @State private var useSmoothedDepth = true
    @State private var highConfidenceOnly = false
    @State private var panel: Panel?

    private let capabilities = DeviceCapabilities.current

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                DepthARViewContainer(model: model)
                    .ignoresSafeArea(edges: .bottom)

                if let image = model.heatMapImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .opacity(overlayOpacity)
                        .allowsHitTesting(false)
                        .clipped()
                        .ignoresSafeArea(edges: .bottom)
                }

                CrosshairView()
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .allowsHitTesting(false)

                VStack {
                    HStack {
                        LiveCameraStatusBadge(
                            title: format(model.centerDistance),
                            detail: "ثقة: \(model.centerConfidence)",
                            systemImage: "scope"
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
                        LiveCameraSideButton(
                            systemImage: "slider.horizontal.3",
                            accessibilityLabel: "إعدادات العمق",
                            isSelected: panel == .controls
                        ) { toggle(.controls) }
                        LiveCameraSideButton(
                            systemImage: "chart.bar.xaxis",
                            accessibilityLabel: "إحصائيات العمق",
                            isSelected: panel == .stats
                        ) { toggle(.stats) }
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

                VStack {
                    Spacer()
                    LiveCameraBottomBar {
                        Button {
                            model.isFrozen.toggle()
                        } label: {
                            Label(model.isFrozen ? "متابعة" : "تجميد", systemImage: model.isFrozen ? "play.fill" : "pause.fill")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.bottom, 12)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: panel != nil)
        }
        .background(.black)
        .navigationTitle("كاميرا العمق")
        .navigationBarTitleDisplayMode(.inline)
        .keepScreenAwakeForLiveTool(id: "depth.camera")
        .onChange(of: useSmoothedDepth) { _, newValue in model.preferSmoothedDepth = newValue }
        .onChange(of: highConfidenceOnly) { _, newValue in model.showOnlyHighConfidence = newValue }
        .onDisappear { model.stopSession() }
        .alert("تعذر تشغيل الحساس", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "خطأ غير معروف")
        }
    }

    private func toggle(_ newPanel: Panel) {
        panel = panel == newPanel ? nil : newPanel
    }

    @ViewBuilder
    private func panelView(_ panel: Panel) -> some View {
        switch panel {
        case .controls:
            LiveCameraFloatingPanel(title: "إعدادات العمق", systemImage: "slider.horizontal.3", onClose: { self.panel = nil }) {
                VStack(alignment: .leading, spacing: 12) {
                    if capabilities.smoothedDepthSupported {
                        Picker("نوع العمق", selection: $useSmoothedDepth) {
                            Text("خام").tag(false)
                            Text("منعّم").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    Toggle("ثقة مرتفعة فقط", isOn: $highConfidenceOnly)
                    HStack {
                        Image(systemName: "circle.lefthalf.filled")
                        Slider(value: $overlayOpacity, in: 0...1)
                        Text("\(Int(overlayOpacity * 100))%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 38)
                    }
                }
            }
        case .stats:
            LiveCameraFloatingPanel(title: "الإحصائيات", systemImage: "chart.bar.xaxis", onClose: { self.panel = nil }) {
                VStack(spacing: 10) {
                    MetricChip(title: "المركز", value: format(model.centerDistance), systemImage: "scope")
                    MetricChip(title: "الأقرب", value: format(model.minimumDistance), systemImage: "arrow.down.to.line")
                    MetricChip(title: "الأبعد", value: format(model.maximumDistance), systemImage: "arrow.up.to.line")
                    HStack {
                        Label("الثقة عند المركز", systemImage: "checkmark.shield")
                        Spacer()
                        Text(model.centerConfidence)
                            .font(.caption.bold())
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func format(_ value: Float?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f m", value)
    }
}

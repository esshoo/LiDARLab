import SwiftUI

struct DepthCameraView: View {
    @StateObject private var model = DepthSessionViewModel(generateHeatmap: true)
    @State private var overlayOpacity = 0.62
    @State private var useSmoothedDepth = true
    @State private var highConfidenceOnly = false

    private let capabilities = DeviceCapabilities.current

    var body: some View {
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

            VStack(spacing: 12) {
                controls
                Spacer()
                CrosshairView()
                Spacer()
                statistics
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(.black)
        .navigationTitle("كاميرا العمق")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: useSmoothedDepth) { _, newValue in
            model.preferSmoothedDepth = newValue
        }
        .onChange(of: highConfidenceOnly) { _, newValue in
            model.showOnlyHighConfidence = newValue
        }
        .onDisappear {
            model.stopSession()
        }
        .alert("تعذر تشغيل الحساس", isPresented: Binding(
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
            if capabilities.smoothedDepthSupported {
                Picker("نوع العمق", selection: $useSmoothedDepth) {
                    Text("خام").tag(false)
                    Text("منعّم").tag(true)
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 12) {
                Toggle("ثقة مرتفعة فقط", isOn: $highConfidenceOnly)
                    .font(.caption)

                Button {
                    model.isFrozen.toggle()
                } label: {
                    Label(model.isFrozen ? "متابعة" : "تجميد", systemImage: model.isFrozen ? "play.fill" : "pause.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
            }

            HStack {
                Image(systemName: "circle.lefthalf.filled")
                Slider(value: $overlayOpacity, in: 0...1)
                Text("\(Int(overlayOpacity * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 38)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var statistics: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MetricChip(title: "المركز", value: format(model.centerDistance), systemImage: "scope")
                MetricChip(title: "الأقرب", value: format(model.minimumDistance), systemImage: "arrow.down.to.line")
                MetricChip(title: "الأبعد", value: format(model.maximumDistance), systemImage: "arrow.up.to.line")
            }

            HStack {
                Label("الثقة عند المركز: \(model.centerConfidence)", systemImage: "checkmark.shield")
                    .font(.caption.bold())
                Spacer()
                Text("الألوان: قريب ← بعيد")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }

    private func format(_ value: Float?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f m", value)
    }
}

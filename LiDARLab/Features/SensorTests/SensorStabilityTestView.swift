import Combine
import SwiftUI

struct SensorStabilityTestView: View {
    private enum Panel { case settings, results }

    @StateObject private var model = DepthSessionViewModel(generateHeatmap: false)
    @State private var samples: [Double] = []
    @State private var isTesting = false
    @State private var progress: Double = 0
    @State private var testStartDate: Date?
    @State private var selectedDuration: Double = 10
    @State private var panel: Panel?

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                DepthARViewContainer(model: model)
                    .ignoresSafeArea(edges: .bottom)

                CrosshairView()
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .allowsHitTesting(false)

                VStack {
                    HStack {
                        LiveCameraStatusBadge(
                            title: testStatus,
                            detail: currentDistance,
                            systemImage: "waveform.path.ecg",
                            accent: isTesting ? .cyan : .green
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
                        LiveCameraSideButton(systemImage: "slider.horizontal.3", accessibilityLabel: "إعدادات الاختبار", isSelected: panel == .settings) { toggle(.settings) }
                        LiveCameraSideButton(systemImage: "chart.bar.xaxis", accessibilityLabel: "نتائج الاختبار", isSelected: panel == .results, isEnabled: !samples.isEmpty) { toggle(.results) }
                        LiveCameraSideButton(systemImage: "arrow.counterclockwise", accessibilityLabel: "إعادة ضبط", isEnabled: !isTesting && !samples.isEmpty) { resetTest() }
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
                    LiveCameraBottomBar {
                        Button {
                            isTesting ? stopTest() : startTest()
                        } label: {
                            Label(isTesting ? "إيقاف الاختبار" : "بدء الاختبار", systemImage: isTesting ? "stop.fill" : "play.fill")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isTesting ? .red : .cyan)
                    }
                    if isTesting {
                        ProgressView(value: progress)
                            .frame(maxWidth: 260)
                            .padding(.bottom, 6)
                    }
                    Spacer().frame(height: 8)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: panel != nil)
        }
        .background(.black)
        .navigationTitle("اختبار ثبات الحساس")
        .navigationBarTitleDisplayMode(.inline)
        .keepScreenAwakeForLiveTool(id: "sensor.stability")
        .onReceive(timer) { now in collectSample(at: now) }
        .onDisappear {
            isTesting = false
            model.stopSession()
        }
    }

    private func toggle(_ newPanel: Panel) { panel = panel == newPanel ? nil : newPanel }

    @ViewBuilder
    private func panelView(_ panel: Panel) -> some View {
        switch panel {
        case .settings:
            LiveCameraFloatingPanel(title: "إعدادات الاختبار", systemImage: "slider.horizontal.3", onClose: { self.panel = nil }) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("مدة الاختبار", selection: $selectedDuration) {
                        Text("5 ث").tag(5.0)
                        Text("10 ث").tag(10.0)
                        Text("20 ث").tag(20.0)
                    }
                    .pickerStyle(.segmented)
                    .disabled(isTesting)
                    Text("ثبّت الجهاز على نقطة واحدة وحافظ على مؤشر المنتصف فوق سطح ثابت.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .results:
            LiveCameraFloatingPanel(title: "نتائج الاختبار", systemImage: "chart.bar.xaxis", onClose: { self.panel = nil }) {
                VStack(spacing: 10) {
                    MetricChip(title: "المتوسط", value: formatted(mean), systemImage: "equal")
                    MetricChip(title: "أقل قراءة", value: formatted(minimum), systemImage: "arrow.down")
                    MetricChip(title: "أعلى قراءة", value: formatted(maximum), systemImage: "arrow.up")
                    MetricChip(title: "التذبذب", value: formatted(range), systemImage: "arrow.left.and.right")
                    MetricChip(title: "الانحراف σ", value: formatted(standardDeviation), systemImage: "waveform")
                    MetricChip(title: "العينات", value: "\(samples.count)", systemImage: "number")
                }
            }
        }
    }

    private var testStatus: String {
        if isTesting { return "جاري جمع القراءات..." }
        if samples.isEmpty { return "اختبار الثبات" }
        if let standardDeviation {
            if standardDeviation <= 0.005 { return "ثبات ممتاز" }
            if standardDeviation <= 0.015 { return "ثبات جيد" }
            if standardDeviation <= 0.030 { return "تذبذب متوسط" }
            return "تذبذب مرتفع"
        }
        return "اكتمل الاختبار"
    }

    private var currentDistance: String {
        guard let value = model.centerDistance else { return "—" }
        return String(format: "%.3f م", value)
    }

    private var mean: Double? {
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }
    private var minimum: Double? { samples.min() }
    private var maximum: Double? { samples.max() }
    private var range: Double? {
        guard let minimum, let maximum else { return nil }
        return maximum - minimum
    }
    private var standardDeviation: Double? {
        guard let mean, samples.count > 1 else { return nil }
        let variance = samples.reduce(0) { $0 + pow($1 - mean, 2) } / Double(samples.count - 1)
        return sqrt(variance)
    }

    private func startTest() {
        samples.removeAll(keepingCapacity: true)
        progress = 0
        testStartDate = Date()
        isTesting = true
        model.isFrozen = false
    }

    private func stopTest() {
        isTesting = false
        progress = min(progress, 1)
        testStartDate = nil
    }

    private func resetTest() {
        samples = []
        progress = 0
        testStartDate = nil
    }

    private func collectSample(at now: Date) {
        guard isTesting, let start = testStartDate else { return }
        let elapsed = now.timeIntervalSince(start)
        progress = min(max(elapsed / selectedDuration, 0), 1)
        if let distance = model.centerDistance, distance.isFinite, distance > 0 {
            samples.append(Double(distance))
        }
        if elapsed >= selectedDuration {
            isTesting = false
            progress = 1
            testStartDate = nil
        }
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value < 0.1 { return String(format: "%.1f مم", value * 1000) }
        return String(format: "%.3f م", value)
    }
}

import Combine
import SwiftUI

struct SensorStabilityTestView: View {
    @StateObject private var model = DepthSessionViewModel(generateHeatmap: false)
    @State private var samples: [Double] = []
    @State private var isTesting = false
    @State private var progress: Double = 0
    @State private var testStartDate: Date?
    @State private var selectedDuration: Double = 10

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            DepthARViewContainer(model: model)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 12) {
                controls
                Spacer(minLength: 70)
                CrosshairView()
                Spacer(minLength: 70)
                resultsPanel
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .background(.black)
        .navigationTitle("اختبار ثبات الحساس")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(timer) { now in
            collectSample(at: now)
        }
        .onDisappear {
            isTesting = false
            model.stopSession()
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("مدة الاختبار", selection: $selectedDuration) {
                Text("5 ث").tag(5.0)
                Text("10 ث").tag(10.0)
                Text("20 ث").tag(20.0)
            }
            .pickerStyle(.segmented)
            .disabled(isTesting)

            HStack(spacing: 10) {
                Button {
                    isTesting ? stopTest() : startTest()
                } label: {
                    Label(isTesting ? "إيقاف" : "بدء الاختبار", systemImage: isTesting ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    resetTest()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isTesting || samples.isEmpty)
            }

            if isTesting {
                ProgressView(value: progress)
                    .tint(.cyan)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var resultsPanel: some View {
        VStack(spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(testStatus)
                        .font(.headline)
                    Text("ثبّت الجهاز على نقطة واحدة وحافظ على مركز الشاشة فوق سطح ثابت.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text(currentDistance)
                    .font(.title2.monospacedDigit().bold())
                    .minimumScaleFactor(0.7)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 9)], spacing: 9) {
                MetricChip(title: "المتوسط", value: formatted(mean), systemImage: "equal")
                MetricChip(title: "أقل قراءة", value: formatted(minimum), systemImage: "arrow.down")
                MetricChip(title: "أعلى قراءة", value: formatted(maximum), systemImage: "arrow.up")
                MetricChip(title: "التذبذب", value: formatted(range), systemImage: "arrow.left.and.right")
                MetricChip(title: "الانحراف σ", value: formatted(standardDeviation), systemImage: "waveform")
                MetricChip(title: "العينات", value: "\(samples.count)", systemImage: "number")
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var testStatus: String {
        if isTesting {
            return "جاري جمع القراءات..."
        }
        if samples.isEmpty {
            return "اختبار الثبات"
        }
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
        let variance = samples.reduce(0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(samples.count - 1)
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

        if let distance = model.centerDistance,
           distance.isFinite,
           distance > 0 {
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
        if value < 0.1 {
            return String(format: "%.1f مم", value * 1000)
        }
        return String(format: "%.3f م", value)
    }
}

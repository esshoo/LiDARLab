import SwiftUI

struct DistanceMeasureView: View {
    @StateObject private var model = DepthSessionViewModel(generateHeatmap: false)
    @State private var useCentimeters = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                DepthARViewContainer(model: model)
                    .ignoresSafeArea(edges: .bottom)

                // The aiming point is always the geometric center of the camera area.
                CrosshairView()
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .allowsHitTesting(false)

                VStack(spacing: 12) {
                    unitPicker
                    Spacer(minLength: 0)
                    readingPanel
                    actionButtons
                }
                .padding(.horizontal, adaptiveHorizontalPadding(for: geometry.size.width))
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
        }
        .background(.black)
        .navigationTitle("قياس المسافة")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            model.stopSession()
        }
    }

    private var unitPicker: some View {
        Picker("الوحدة", selection: $useCentimeters) {
            Text("متر").tag(false)
            Text("سم").tag(true)
        }
        .pickerStyle(.segmented)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var readingPanel: some View {
        VStack(spacing: 7) {
            Text("المسافة عند مؤشر منتصف الشاشة")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                Text(formattedDistance)
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                Text(formattedDistance)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
            }
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .contentTransition(.numericText())

            Label("مستوى الثقة: \(model.centerConfidence)", systemImage: "checkmark.shield")
                .font(.caption.bold())
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var actionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                freezeButton
                restartButton
            }

            VStack(spacing: 10) {
                freezeButton
                restartButton
            }
        }
    }

    private var freezeButton: some View {
        Button {
            model.isFrozen.toggle()
        } label: {
            Label(
                model.isFrozen ? "متابعة القياس" : "تثبيت القراءة",
                systemImage: model.isFrozen ? "play.fill" : "pause.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    private var restartButton: some View {
        Button {
            model.startSession(resetTracking: true)
        } label: {
            Label("إعادة التتبع", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var formattedDistance: String {
        guard let distance = model.centerDistance else { return "—" }
        if useCentimeters {
            return String(format: "%.1f سم", distance * 100)
        }
        return String(format: "%.3f م", distance)
    }

    private func adaptiveHorizontalPadding(for width: CGFloat) -> CGFloat {
        width >= 900 ? 28 : (width >= 600 ? 20 : 12)
    }
}

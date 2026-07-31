import SwiftUI

struct DistanceMeasureView: View {
    @StateObject private var model = DepthSessionViewModel(generateHeatmap: false)
    @State private var useCentimeters = false

    var body: some View {
        ZStack {
            DepthARViewContainer(model: model)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 18) {
                Picker("الوحدة", selection: $useCentimeters) {
                    Text("متر").tag(false)
                    Text("سم").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))

                Spacer()

                CrosshairView()

                VStack(spacing: 8) {
                    Text("المسافة من مركز الشاشة")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ViewThatFits(in: .horizontal) {
                        Text(formattedDistance)
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                        Text(formattedDistance)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                    }
                    .monospacedDigit()
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .contentTransition(.numericText())

                    Label("مستوى الثقة: \(model.centerConfidence)", systemImage: "checkmark.shield")
                        .font(.caption.bold())
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        freezeButton
                        restartButton
                    }

                    VStack(spacing: 10) {
                        freezeButton
                        restartButton
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(16)
        }
        .background(.black)
        .navigationTitle("قياس المسافة")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            model.stopSession()
        }
    }


    private var freezeButton: some View {
        Button {
            model.isFrozen.toggle()
        } label: {
            Label(model.isFrozen ? "متابعة القياس" : "تثبيت القراءة", systemImage: model.isFrozen ? "play.fill" : "pause.fill")
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
}

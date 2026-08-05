import SwiftUI

struct ComputerBridgeView: View {
    @StateObject private var model = ComputerBridgeViewModel()
    @FocusState private var focusedField: Field?

    private enum Field {
        case ip
        case port
    }

    var body: some View {
        ZStack {
            ComputerBridgeARViewContainer(model: model)
                .ignoresSafeArea(edges: .bottom)

            LinearGradient(
                colors: [.black.opacity(0.62), .clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)

            VStack(spacing: 12) {
                statusPanel
                Spacer(minLength: 90)
                connectionPanel
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .background(.black)
        .navigationTitle("البث إلى الكمبيوتر")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("تم") { focusedField = nil }
            }
        }
        .onDisappear {
            model.stop()
        }
    }

    private var statusPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 10, height: 10)
                Text(model.connectionTitle)
                    .font(.headline)
                Spacer(minLength: 8)
                Text(model.positionText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                MetricChip(title: "Frames", value: "\(model.framesSent)", systemImage: "square.stack.3d.up")
                MetricChip(title: "المتخطاة", value: "\(model.framesSkipped)", systemImage: "forward.frame")
                MetricChip(title: "البيانات", value: model.totalSentText, systemImage: "arrow.up.circle")
                MetricChip(title: "التتبع", value: model.trackingText, systemImage: "location")
                MetricChip(title: "الحرارة", value: model.thermalText, systemImage: "thermometer.medium")
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var connectionPanel: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("IP الكمبيوتر")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("192.168.1.50", text: $model.serverIP)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.numbersAndPunctuation)
                            .focused($focusedField, equals: .ip)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("المنفذ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("8766", text: $model.serverPort)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .port)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 105)
                    }
                }
                .disabled(model.isConnected)

                Picker("معدل الإرسال", selection: $model.targetFPS) {
                    Text("5 FPS").tag(5)
                    Text("10 FPS").tag(10)
                    Text("15 FPS").tag(15)
                    Text("30 FPS").tag(30)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    Button {
                        model.isConnected ? model.disconnect() : model.connect()
                    } label: {
                        Label(
                            model.isConnected ? "قطع الاتصال" : "اتصال",
                            systemImage: model.isConnected ? "wifi.slash" : "wifi"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.connectionState == .connecting)

                    Button {
                        model.toggleStreaming()
                    } label: {
                        Label(
                            model.isStreaming ? "إيقاف الإرسال" : "بدء الإرسال",
                            systemImage: model.isStreaming ? "stop.fill" : "location.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.isConnected)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("آخر رد من الكمبيوتر")
                        .font(.caption.weight(.semibold))
                    Text(model.lastServerMessage)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(3)
                }

                if let error = model.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(13)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: 355)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var connectionColor: Color {
        switch model.connectionState {
        case .connected:
            .green
        case .connecting:
            .yellow
        case .failed:
            .red
        case .disconnected:
            .gray
        }
    }
}

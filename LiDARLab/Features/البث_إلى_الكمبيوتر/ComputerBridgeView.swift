import SwiftUI

struct ComputerBridgeView: View {
    @StateObject private var model = ComputerBridgeViewModel()
    @FocusState private var focusedField: Field?
    @State private var showTransferSettings = true

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
                Spacer(minLength: 60)
                connectionPanel
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .background(.black)
        .navigationTitle("البث والمسح 2D")
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

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], spacing: 8) {
                MetricChip(title: "Pose", value: "\(model.framesSent)", systemImage: "location")
                MetricChip(title: "مسح 2D", value: "\(model.scanFramesSent)", systemImage: "map")
                MetricChip(title: "المتخطاة", value: "\(model.framesSkipped + model.scanFramesSkipped)", systemImage: "forward.frame")
                MetricChip(title: "البيانات", value: model.totalSentText, systemImage: "arrow.up.circle")
                MetricChip(title: "LiDAR", value: model.depthStatusText, systemImage: "sensor")
                MetricChip(title: "التتبع", value: model.trackingText, systemImage: "viewfinder")
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
                        Text("IP المستقبل")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("192.168.0.2", text: $model.serverIP)
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

                Picker("نوع الإرسال", selection: $model.streamMode) {
                    ForEach(ComputerBridgeViewModel.StreamMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.settingsLocked)

                DisclosureGroup("إعدادات نقل البيانات", isExpanded: $showTransferSettings) {
                    VStack(spacing: 10) {
                        HStack {
                            Text("معدل إرسال الموقع")
                            Spacer()
                            Picker("معدل إرسال الموقع", selection: $model.targetFPS) {
                                ForEach([1, 2, 5, 10, 15, 30], id: \.self) { fps in
                                    Text("\(fps) FPS").tag(fps)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        if model.streamMode == .scan2D {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("معدل إرسال المسح 2D")
                                    Text("يمكن إبقاء الموقع سريعًا وتقليل المسح الثقيل")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("معدل المسح", selection: $model.scanFPS) {
                                    ForEach([1, 2, 5, 10, 15, 30], id: \.self) { fps in
                                        Text("\(fps) FPS").tag(fps)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("خطوة أخذ عينات Depth")
                                    Text("رقم أصغر = بيانات أكثر وتفاصيل أعلى")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("خطوة العينات", selection: $model.samplingStride) {
                                    ForEach([2, 4, 6, 8, 12], id: \.self) { stride in
                                        Text("\(stride)").tag(stride)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            Toggle("إرسال Confidence Map", isOn: $model.sendConfidence)

                            HStack {
                                Text("سياسة الحرارة")
                                Spacer()
                                Picker("سياسة الحرارة", selection: $model.thermalPolicy) {
                                    ForEach(ComputerBridgeViewModel.ThermalPolicy.allCases) { policy in
                                        Text(policy.title).tag(policy)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }

                        Label(model.estimatedTransferText, systemImage: "chart.bar.doc.horizontal")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if model.settingsLocked {
                            Label("أوقف الإرسال لتغيير إعدادات النقل.", systemImage: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 8)
                    .disabled(model.settingsLocked)
                }

                if model.streamMode == .scan2D {
                    Label(
                        "الهاتف يرسل Pose وشبكة Depth حسب اختياراتك فقط. التنظيف واستخراج الحوائط يتمان على المستقبل.",
                        systemImage: "square.grid.3x3"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

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
                            systemImage: model.isStreaming ? "stop.fill" : "dot.radiowaves.left.and.right"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.isConnected)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("آخر رد من المستقبل")
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
        .frame(maxHeight: 520)
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

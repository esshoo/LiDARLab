import SwiftUI

struct StableScanView: View {
    @StateObject private var model = StableScanViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showResult = false

    var body: some View {
        ZStack {
            StableARSessionContainer(
                pipeline: model.pipeline,
                mode: model.mode,
                enabled: model.arSessionEnabled,
                generation: model.arSessionGeneration
            )
            .frame(width: 1, height: 1)
            .opacity(0.001)
            .allowsHitTesting(false)

            StableMapView(
                pathSegments: model.preview.pathSegments,
                breakPoints: model.preview.breakPoints,
                coverageCells: model.mode == .scan2D ? model.preview.coverageCells : [],
                processedCells: [],
                currentPose: model.preview.currentPose,
                previewCellSize: model.previewCellSize
            )
            .ignoresSafeArea(edges: .bottom)

            mainOverlay

            if showSettings { settingsOverlay }
            if model.depthAdvisoryVisible { depthAdvisoryOverlay }
            if showResult, let result = model.processingResult {
                StableResultView(result: result) { showResult = false }
                    .zIndex(20)
            }
        }
        .background(.black)
        .navigationTitle("الموقع والمسح الثابت")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.viewDidAppear() }
        .onDisappear { model.viewDidDisappear() }
        .onChange(of: scenePhase) { _, phase in
            model.setApplicationActive(phase == .active)
        }
    }

    private var mainOverlay: some View {
        VStack(spacing: 10) {
            topPanel
            Spacer(minLength: 80)
            bottomPanel
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var topPanel: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                modeButton(.locationOnly, icon: "location.fill")
                modeButton(.scan2D, icon: "map.fill")
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .frame(width: 46, height: 42)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13))
                }
                .disabled(model.settingsLocked)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(model.preview.trackingText == "طبيعي" ? .green : .orange)
                    .frame(width: 9, height: 9)
                Text(model.sessionState.title)
                    .font(.headline)
                Text(model.preview.trackingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.orientationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.orange)
            }

            Text(model.statusMessage)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let error = model.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error).font(.caption)
                    Spacer()
                }
                .foregroundStyle(.red)
            }
        }
        .padding(11)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func modeButton(_ mode: StableScanMode, icon: String) -> some View {
        Button {
            model.mode = mode
        } label: {
            Label(mode.title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    model.mode == mode ? Color.blue : Color.clear,
                    in: RoundedRectangle(cornerRadius: 13)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.settingsLocked)
    }

    private var bottomPanel: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                stat("Pose", "\(model.preview.poseCount)")
                stat("Depth", "\(model.preview.depthCount)")
                stat("فواصل", "\(model.preview.breakPoints.count)")
                stat("الحفظ", model.recordedSizeText)
            }

            Text(model.positionText)
                .font(.caption.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)

            if model.sessionState == .processing {
                ProgressView(value: model.processingProgress) {
                    Text(model.processingProgressText).font(.caption)
                }
            }

            HStack(spacing: 8) {
                switch model.sessionState {
                case .recording, .paused:
                    Button(model.sessionState == .paused ? "استئناف" : "إيقاف مؤقت") {
                        model.pauseOrResume()
                    }
                    .buttonStyle(StableActionButtonStyle(color: .orange))

                    Button("إنهاء وحفظ") {
                        model.endSession()
                    }
                    .buttonStyle(StableActionButtonStyle(color: .red))

                case .finished, .resultReady:
                    Button("معالجة على الجهاز") {
                        model.processSavedSession()
                    }
                    .buttonStyle(StableActionButtonStyle(color: .blue))
                    .disabled(!model.canProcess)

                    if model.processingResult != nil {
                        Button("عرض النتيجة") { showResult = true }
                            .buttonStyle(StableActionButtonStyle(color: .green))
                    }

                    Button("جلسة جديدة") { model.prepareNewSession() }
                        .buttonStyle(StableActionButtonStyle(color: .gray))

                case .processing, .finalizing:
                    Text(model.sessionState.title)
                        .frame(maxWidth: .infinity)
                        .padding(13)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

                default:
                    Button("بدء \(model.mode.title)") {
                        model.requestStart()
                    }
                    .buttonStyle(StableActionButtonStyle(color: .green))
                    .disabled(!model.canStart)
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var settingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("إعدادات Stable Core").font(.title2.bold())
                        Spacer()
                        Button("إغلاق") { showSettings = false }
                            .buttonStyle(.borderedProminent)
                    }

                    settingSection("الطاقة") {
                        Toggle("إبقاء الشاشة مضيئة أثناء الجلسة", isOn: $model.keepScreenAwake)
                    }

                    settingSection("الإرسال الاختياري إلى Windows") {
                        Toggle("إرسال نسخة مباشرة إلى الكمبيوتر", isOn: $model.sendToWindows)
                        TextField("IP الكمبيوتر", text: $model.serverIP)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numbersAndPunctuation)
                        TextField("المنفذ", text: $model.serverPort)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                        HStack {
                            Button("اتصال") { model.connectWindows() }.buttonStyle(.borderedProminent)
                            Button("فصل") { model.disconnectWindows() }.buttonStyle(.bordered)
                            Spacer()
                            Text(model.networkConnected ? "متصل" : "غير متصل")
                        }
                        Text(model.networkStatus).font(.caption).foregroundStyle(.secondary)
                        Text("قائمة الشبكة: \(model.networkQueueText)")
                            .font(.caption.monospacedDigit())
                    }

                    if model.mode == .scan2D {
                        settingSection("مسح 2D") {
                            stepper("Depth FPS", value: $model.depthFPS, range: 1...15)
                            stepper("خطوة أخذ العينات", value: $model.samplingStride, range: 2...12)
                            Toggle("حفظ Confidence", isOn: $model.includeConfidence)
                        }
                    }

                    settingSection("المعاينة فقط") {
                        stepper("تحديث الخريطة FPS", value: $model.previewFPS, range: 2...10)
                        HStack {
                            Text("حجم خلية التغطية")
                            Spacer()
                            Text(String(format: "%.2f م", model.previewCellSize))
                        }
                        Slider(value: $model.previewCellSize, in: 0.08...0.35, step: 0.01)
                        Text("هذه الإعدادات تخص العرض فقط. لا تحذف أو تقلل الملف الخام.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
            }
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
            .padding(12)
        }
        .zIndex(10)
    }

    private var depthAdvisoryOverlay: some View {
        ZStack {
            Color.black.opacity(0.86).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "sensor.tag.radiowaves.forward")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                Text("Depth غير مؤكدة على هذا الجهاز")
                    .font(.title2.bold())
                Text("سيبدأ Stable Location Core ويحفظ Pose كاملة. إن لم يوفر النظام sceneDepth فلن تُسجل حزم Depth، ولن يتم تحويل الوضع تلقائيًا.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("التجربة على أي حال") { model.startDespiteDepthAdvisory() }
                    .buttonStyle(StableActionButtonStyle(color: .orange))
                Button("إلغاء") { model.cancelDepthAdvisory() }
                    .buttonStyle(StableActionButtonStyle(color: .gray))
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(20)
        }
        .zIndex(15)
    }

    private func settingSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
    }

    private func stepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            HStack { Text(title); Spacer(); Text("\(value.wrappedValue)").monospacedDigit() }
        }
    }
}

struct StableActionButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(color.opacity(configuration.isPressed ? 0.62 : 0.9), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
            .contentShape(Rectangle())
    }
}

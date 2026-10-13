import SwiftUI

struct TurntableObjectScanView: View {
    private enum Panel { case info, mode, actions }

    @StateObject private var model = TurntableObjectScanViewModel()
    @StateObject private var torch = SharedTorchController()
    @AppStorage(Color3DScanSettings.Key.turntableCaptureMode) private var captureModeRaw = TurntableCaptureMode.smartAutomatic.rawValue
    @State private var showPreview = false
    @State private var showCancelConfirmation = false
    @State private var panel: Panel?

    private var selectedCaptureMode: Binding<TurntableCaptureMode> {
        Binding(
            get: { TurntableCaptureMode(rawValue: captureModeRaw) ?? .smartAutomatic },
            set: { captureModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Group {
            switch model.phase {
            case .idle: introView
            case .preparingCamera, .ready, .capturing, .readyToReconstruct: cameraView
            case .reconstructing: processingView
            case .completed: completedView
            case .failed: failedView
            }
        }
        .navigationTitle("Turntable")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.phase != .idle && model.phase != .completed && model.phase != .failed {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("إلغاء", role: .destructive) { showCancelConfirmation = true }
                }
            }
        }
        .confirmationDialog("إلغاء مسح Turntable؟", isPresented: $showCancelConfirmation) {
            Button("إلغاء المسح", role: .destructive) { model.cancelAndReset() }
            Button("متابعة", role: .cancel) {}
        }
        .alert("خطأ في المسح", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("حسنًا", role: .cancel) { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "حدث خطأ غير معروف.")
        }
        .sheet(isPresented: $showPreview) {
            if let url = model.modelURL {
                NavigationStack {
                    QuickLookPreview(url: url)
                        .navigationTitle("معاينة النموذج")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("إغلاق") { showPreview = false }
                            }
                        }
                }
            }
        }
        .keepScreenAwakeForLiveTool(
            id: "color3d.turntable",
            active: model.phase != .idle && model.phase != .completed && model.phase != .failed
        )
        .onAppear { torch.refreshAvailability() }
        .onDisappear {
            torch.turnOff()
            if model.phase != .completed && model.phase != .idle {
                model.cancelAndReset()
            }
        }
    }

    private var introView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.system(size: 68, weight: .light))
                    .foregroundStyle(.cyan)
                Text("الكاميرا ثابتة — المجسم يدور")
                    .font(.title2.bold())
                Text("ثبّت الهاتف والخلفية والإضاءة. اختر تلقائي ذكي أو يدوي، ثم لف المجسم نفسه بدل تحريك الكاميرا.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Picker("طريقة الالتقاط", selection: selectedCaptureMode) {
                    ForEach(TurntableCaptureMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(selectedCaptureMode.wrappedValue.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    model.prepare()
                } label: {
                    Label("فتح كاميرا Turntable", systemImage: "camera.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
            .padding()
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }

    private var cameraView: some View {
        ZStack {
            TurntableCameraPreview(session: model.captureSession)
                .ignoresSafeArea(edges: .bottom)

            TurntableFramingGuide()

            VStack {
                HStack {
                    LiveCameraStatusBadge(
                        title: model.phase.title,
                        detail: compactDetail,
                        systemImage: model.isSmartAutomatic ? "sparkles" : "hand.tap"
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
                        systemImage: torch.isOn ? "flashlight.on.fill" : "flashlight.off.fill",
                        accessibilityLabel: "الكشاف",
                        tint: torch.isOn ? .yellow : nil,
                        isEnabled: torch.isAvailable
                    ) {
                        torch.toggle()
                        model.notifyLightingChanged()
                    }
                    LiveCameraSideButton(systemImage: "info.circle", accessibilityLabel: "حالة الالتقاط", isSelected: panel == .info) { toggle(.info) }
                    LiveCameraSideButton(systemImage: "slider.horizontal.3", accessibilityLabel: "طريقة الالتقاط", isSelected: panel == .mode, isEnabled: model.phase == .ready || model.phase == .readyToReconstruct) { toggle(.mode) }
                    LiveCameraSideButton(systemImage: "ellipsis.circle", accessibilityLabel: "إجراءات إضافية", isSelected: panel == .actions) { toggle(.actions) }
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
                bottomBar
                    .padding(.bottom, 12)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: panel != nil)
    }

    private var compactDetail: String {
        switch model.phase {
        case .capturing:
            return "الجولة \(model.passNumber) • \(model.passImageCount) صورة • \(model.smartCaptureState)"
        case .readyToReconstruct:
            return "\(model.capturedImageCount) صورة جاهزة للبناء"
        default:
            return model.statusMessage
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        switch model.phase {
        case .preparingCamera:
            LiveCameraStatusBadge(title: "تهيئة الكاميرا…", systemImage: "hourglass")
        case .ready:
            LiveCameraBottomBar {
                Button {
                    model.startPass()
                } label: {
                    Label(model.isSmartAutomatic ? "بدء الالتقاط الذكي" : "بدء الجولة اليدوية", systemImage: "record.circle")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }
        case .capturing:
            LiveCameraBottomBar {
                Button {
                    model.captureManualPhoto()
                } label: {
                    Image(systemName: "camera.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("التقاط صورة")

                Button {
                    model.stopPass()
                } label: {
                    Label("إيقاف الجولة", systemImage: "stop.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        case .readyToReconstruct:
            LiveCameraBottomBar {
                Button {
                    model.startPass()
                } label: {
                    Image(systemName: "arrow.2.circlepath")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("جولة إضافية")

                Button {
                    model.reconstructNow()
                } label: {
                    Label("بناء النموذج", systemImage: "cube.transparent.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!model.canFinishCapture)
            }
        default:
            EmptyView()
        }
    }

    private func toggle(_ newPanel: Panel) { panel = panel == newPanel ? nil : newPanel }

    @ViewBuilder
    private func panelView(_ panel: Panel) -> some View {
        switch panel {
        case .info:
            LiveCameraFloatingPanel(title: "حالة Turntable", systemImage: "info.circle", onClose: { self.panel = nil }) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.statusMessage).font(.caption)
                    LabeledContent("طريقة الالتقاط", value: model.captureModeTitle)
                    LabeledContent("إجمالي الصور", value: "\(model.capturedImageCount)")
                    LabeledContent("الجولة", value: "\(model.passNumber)")
                    LabeledContent("صور الجولة", value: "\(model.passImageCount) / \(model.targetImagesPerPass)")
                    if model.phase == .capturing {
                        LabeledContent("حالة الذكاء", value: model.smartCaptureState)
                        if model.isSmartAutomatic {
                            LabeledContent("اختلاف المنظر", value: String(format: "%.3f", model.visualChangeScore))
                        }
                    }
                    if model.cameraLocked {
                        Label("التركيز والتعريض وتوازن الأبيض مقفلة", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        case .mode:
            LiveCameraFloatingPanel(title: "طريقة الالتقاط", systemImage: "slider.horizontal.3", onClose: { self.panel = nil }) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("طريقة الالتقاط", selection: selectedCaptureMode) {
                        ForEach(TurntableCaptureMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                    Text(selectedCaptureMode.wrappedValue.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("التغيير يطبق عند بدء الجولة التالية.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        case .actions:
            LiveCameraFloatingPanel(title: "إجراءات", systemImage: "ellipsis.circle", onClose: { self.panel = nil }) {
                VStack(spacing: 10) {
                    if model.phase == .capturing {
                        Button {
                            model.captureManualPhoto()
                        } label: {
                            Label("التقاط صورة الآن", systemImage: "camera.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button {
                            model.stopPass()
                            self.panel = nil
                        } label: {
                            Label("إيقاف الجولة", systemImage: "stop.circle").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    if model.phase == .readyToReconstruct {
                        Button {
                            model.startPass()
                            self.panel = nil
                        } label: {
                            Label("جولة إضافية", systemImage: "arrow.2.circlepath").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView(value: model.reconstructionProgress).frame(maxWidth: 420)
            Image(systemName: "cube.transparent").font(.system(size: 54)).foregroundStyle(.cyan)
            Text("بناء نموذج Turntable").font(.title2.bold())
            Text(model.statusMessage).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("\(Int(model.reconstructionProgress * 100))%")
                .font(.title3.bold().monospacedDigit())
        }
        .padding()
    }

    private var completedView: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(.green)
                    Text("اكتمل نموذج Turntable").font(.title2.bold())
                    Text("استخدم RealityKit \(model.capturedImageCount) صورة من الكاميرا الثابتة.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            if model.invalidSampleCount > 0 || model.skippedSampleCount > 0 {
                Section("فحص الصور") {
                    LabeledContent("صور غير صالحة", value: "\(model.invalidSampleCount)")
                    LabeledContent("صور تم تخطيها", value: "\(model.skippedSampleCount)")
                }
            }
            if let url = model.modelURL {
                Section("النموذج") {
                    Button { showPreview = true } label: { Label("معاينة 3D", systemImage: "arkit") }
                    ShareLink(item: url) { Label("مشاركة USDZ", systemImage: "square.and.arrow.up") }
                }
            }
            Section { Button("مسح مجسم جديد") { model.cancelAndReset() } }
        }
    }

    private var failedView: some View {
        ContentUnavailableView {
            Label("تعذر إكمال Turntable", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(model.statusMessage)
        } actions: {
            Button("العودة") { model.cancelAndReset() }.buttonStyle(.borderedProminent)
        }
    }
}

private struct TurntableFramingGuide: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * 0.72
            let height = proxy.size.height * 0.56
            RoundedRectangle(cornerRadius: 20)
                .stroke(.cyan.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
                .frame(width: width, height: height)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .allowsHitTesting(false)
        }
    }
}

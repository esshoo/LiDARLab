import SwiftUI

struct TurntableObjectScanView: View {
    @StateObject private var model = TurntableObjectScanViewModel()
    @StateObject private var torch = SharedTorchController()
    @AppStorage(Color3DScanSettings.Key.turntableCaptureMode) private var captureModeRaw = TurntableCaptureMode.smartAutomatic.rawValue
    @State private var showPreview = false
    @State private var showCancelConfirmation = false

    private var selectedCaptureMode: Binding<TurntableCaptureMode> {
        Binding(
            get: { TurntableCaptureMode(rawValue: captureModeRaw) ?? .smartAutomatic },
            set: { captureModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                introView
            case .preparingCamera, .ready, .capturing, .readyToReconstruct:
                cameraView
            case .reconstructing:
                processingView
            case .completed:
                completedView
            case .failed:
                failedView
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
        .keepScreenAwakeDuringColor3DScan(model.phase != .idle && model.phase != .completed && model.phase != .failed)
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

                Text("هذا الوضع يتبع طريقة Turntable التي تسمح بها Apple لالتقاط صور Object Capture: ثبّت الهاتف والخلفية والإضاءة، ولف المجسم ببطء أثناء التقاط سلسلة صور متداخلة.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)


                VStack(alignment: .leading, spacing: 8) {
                    Text("طريقة التقاط الصور")
                        .font(.headline)
                    Picker("طريقة الالتقاط", selection: selectedCaptureMode) {
                        ForEach(TurntableCaptureMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(selectedCaptureMode.wrappedValue.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 10) {
                    Label("استخدم حاملًا ثابتًا ولا تحرك الهاتف أثناء الجولة.", systemImage: "camera.fill")
                    Label("استخدم خلفية سادة وإضاءة موزعة بدون انعكاسات قوية.", systemImage: "lightbulb.max.fill")
                    Label("اجعل الجسم يملأ أكبر جزء من الإطار بدون قص أي جزء منه.", systemImage: "viewfinder")
                    Label("بعد دورة كاملة يمكنك قلب الجسم على جانب آخر وبدء جولة إضافية.", systemImage: "arrow.2.circlepath")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

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
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    private var cameraView: some View {
        ZStack {
            TurntableCameraPreview(session: model.captureSession)
                .ignoresSafeArea(edges: .bottom)

            TurntableFramingGuide()

            VStack(spacing: 0) {
                statusOverlay
                Spacer()
                controlsOverlay
            }
        }
    }

    private var statusOverlay: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.phase.title)
                        .font(.headline)
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    torch.toggle()
                    model.notifyLightingChanged()
                } label: {
                    Image(systemName: torch.isOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.title3)
                        .frame(width: 44, height: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(torch.isOn ? .yellow : .gray)
                .disabled(!torch.isAvailable)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(model.capturedImageCount)")
                        .font(.title3.bold().monospacedDigit())
                    Text("إجمالي الصور")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if model.phase == .capturing {
                HStack {
                    Label("الجولة \(model.passNumber)", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Text("\(model.passImageCount) صورة / حد \(model.targetImagesPerPass)")
                        .monospacedDigit()
                }
                .font(.caption)

                Label(model.smartCaptureState, systemImage: model.isSmartAutomatic ? "sparkles" : "hand.tap")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if model.isSmartAutomatic, model.visualChangeScore > 0 {
                    Text(String(format: "اختلاف المنظر: %.2f", model.visualChangeScore))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if model.cameraLocked {
                Label("التركيز والتعريض وتوازن الأبيض مقفلة للجولة", systemImage: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17))
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var controlsOverlay: some View {
        VStack(spacing: 10) {
            switch model.phase {
            case .preparingCamera:
                ProgressView()
                Text("تهيئة الكاميرا…")
                    .font(.caption)

            case .ready:
                Button {
                    model.startPass()
                } label: {
                    Label(model.isSmartAutomatic ? "قفل الكاميرا وبدء الالتقاط الذكي" : "قفل الكاميرا وبدء الجولة اليدوية", systemImage: "record.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)

            case .capturing:
                HStack(spacing: 10) {
                    Button {
                        model.captureManualPhoto()
                    } label: {
                        Label(model.isSmartAutomatic ? "صورة يدويًا" : "التقاط صورة", systemImage: "camera.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        model.stopPass()
                    } label: {
                        Label("إيقاف الجولة", systemImage: "stop.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }

            case .readyToReconstruct:
                Button {
                    model.startPass()
                } label: {
                    Label("جولة إضافية بوضعية مختلفة", systemImage: "arrow.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    model.reconstructNow()
                } label: {
                    Label("بناء النموذج الآن", systemImage: "cube.transparent.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!model.canFinishCapture)

            default:
                EmptyView()
            }
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(12)
    }

    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView(value: model.reconstructionProgress)
                .frame(maxWidth: 420)
            Image(systemName: "cube.transparent")
                .font(.system(size: 54))
                .foregroundStyle(.cyan)
            Text("بناء نموذج Turntable")
                .font(.title2.bold())
            Text(model.statusMessage)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("\(Int(model.reconstructionProgress * 100))%")
                .font(.title3.bold().monospacedDigit())
        }
        .padding()
    }

    private var completedView: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.green)
                    Text("اكتمل نموذج Turntable")
                        .font(.title2.bold())
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
                    Button {
                        showPreview = true
                    } label: {
                        Label("معاينة 3D", systemImage: "arkit")
                    }
                    ShareLink(item: url) {
                        Label("مشاركة USDZ", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section {
                Button("مسح مجسم جديد") { model.cancelAndReset() }
            }
        }
    }

    private var failedView: some View {
        ContentUnavailableView {
            Label("تعذر إكمال Turntable", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(model.statusMessage)
        } actions: {
            Button("العودة") { model.cancelAndReset() }
                .buttonStyle(.borderedProminent)
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

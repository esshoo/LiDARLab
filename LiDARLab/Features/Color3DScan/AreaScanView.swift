import RealityKit
import SwiftUI

struct AreaScanView: View {
    private enum Panel { case info, actions }

    @StateObject private var model = AreaScanViewModel()
    @StateObject private var torch = SharedTorchController()
    @State private var showPointCloud = false
    @State private var showPreview = false
    @State private var showCancelConfirmation = false
    @State private var panel: Panel?

    var body: some View {
        Group {
            if !model.isSupported {
                unsupportedView
            } else {
                content
            }
        }
        .navigationTitle("مسح منطقة ملوّنة")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.phase == .capturing || model.phase == .ready || model.phase == .initializing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("إلغاء", role: .destructive) { showCancelConfirmation = true }
                }
            }
        }
        .confirmationDialog("إلغاء مسح المنطقة؟", isPresented: $showCancelConfirmation) {
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
        .sheet(isPresented: $showPointCloud) {
            if let session = model.captureSession {
                NavigationStack {
                    pointCloudView(session: session)
                        .navigationTitle("تغطية الالتقاط")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("إغلاق") { showPointCloud = false }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showPreview) {
            if let url = model.modelURL {
                NavigationStack {
                    QuickLookPreview(url: url)
                        .ignoresSafeArea(edges: .bottom)
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
            id: "color3d.area",
            active: model.phase != .idle && model.phase != .completed && model.phase != .failed
        )
        .onAppear { torch.refreshAvailability() }
        .onDisappear { torch.turnOff() }
    }

    @ViewBuilder
    private func pointCloudView(session: ObjectCaptureSession) -> some View {
        if #available(iOS 18.0, *) {
            ObjectCapturePointCloudView(session: session).showShotLocations()
        } else {
            ObjectCapturePointCloudView(session: session)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle: startView
        case .initializing, .ready, .capturing, .finishing: captureView
        case .reconstructing: processingView
        case .completed: completedView
        case .failed: failedView
        }
    }

    private var startView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 68, weight: .light))
                    .foregroundStyle(.cyan)
                Text("Apple Area Mode")
                    .font(.title2.bold())
                Text("هذا القسم للمسح البصري الملون فقط. امسح جدارًا أو سطحًا أو منطقة محدودة، ويفضل تقسيم المساحات الكبيرة إلى أجزاء.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 9) {
                    Label("تحرك ببطء وبشكل موازٍ للسطح", systemImage: "figure.walk")
                    Label("حافظ على تداخل واضح بين اللقطات", systemImage: "square.on.square")
                    Label("كرر المرور من ارتفاعات مختلفة", systemImage: "arrow.up.and.down")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

                Button {
                    model.prepareSession()
                } label: {
                    Label("فتح المسح الملون", systemImage: "camera.viewfinder")
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

    private var captureView: some View {
        ZStack {
            if #available(iOS 18.0, *), let session = model.captureSession {
                AppleAreaObjectCaptureView(session: session)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                Color.black
            }

            VStack {
                HStack {
                    LiveCameraStatusBadge(
                        title: model.phase.title,
                        detail: "\(model.shotCount) صورة",
                        systemImage: "square.3.layers.3d"
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
                    ) { torch.toggle() }
                    LiveCameraSideButton(systemImage: "info.circle", accessibilityLabel: "حالة المسح", isSelected: panel == .info) { toggle(.info) }
                    LiveCameraSideButton(systemImage: "ellipsis.circle", accessibilityLabel: "إجراءات إضافية", isSelected: panel == .actions) { toggle(.actions) }
                    if model.captureSession != nil {
                        LiveCameraSideButton(systemImage: "point.3.connected.trianglepath.dotted", accessibilityLabel: "التغطية") { showPointCloud = true }
                    }
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

    @ViewBuilder
    private var bottomBar: some View {
        if model.phase == .initializing {
            LiveCameraStatusBadge(title: "تهيئة Object Capture…", systemImage: "hourglass")
        } else if model.phase == .ready {
            LiveCameraBottomBar {
                Button {
                    model.startAreaCapture()
                } label: {
                    Label("بدء المسح", systemImage: "record.circle")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }
        } else if model.phase == .capturing {
            LiveCameraBottomBar {
                Button {
                    model.requestManualShot()
                } label: {
                    Image(systemName: "camera.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("صورة إضافية")

                Button {
                    model.finishCapture()
                } label: {
                    Label("إنهاء", systemImage: "stop.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!model.canFinishCapture)
            }
        } else if model.phase == .finishing {
            LiveCameraStatusBadge(title: "حفظ بيانات الالتقاط…", systemImage: "hourglass")
        }
    }

    private func toggle(_ newPanel: Panel) { panel = panel == newPanel ? nil : newPanel }

    @ViewBuilder
    private func panelView(_ panel: Panel) -> some View {
        switch panel {
        case .info:
            LiveCameraFloatingPanel(title: "حالة المسح", systemImage: "info.circle", onClose: { self.panel = nil }) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.statusMessage)
                        .font(.caption)
                    LabeledContent("الصور", value: "\(model.shotCount)")
                    LabeledContent("الحد الأدنى للإنهاء", value: "\(model.minimumImagesBeforeFinish)")
                    if let feedback = model.feedbackMessage {
                        Label(feedback, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        case .actions:
            LiveCameraFloatingPanel(title: "إجراءات", systemImage: "ellipsis.circle", onClose: { self.panel = nil }) {
                VStack(spacing: 10) {
                    if model.phase == .capturing {
                        Button {
                            model.requestManualShot()
                        } label: {
                            Label("صورة إضافية", systemImage: "camera.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button {
                            showPointCloud = true
                        } label: {
                            Label("مراجعة التغطية", systemImage: "point.3.connected.trianglepath.dotted").frame(maxWidth: .infinity)
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
            Text("بناء النموذج بواسطة RealityKit").font(.title2.bold())
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
                    Text("اكتمل المسح البصري الملون").font(.title2.bold())
                    Text("النتيجة هي Photogrammetry رسمي من Apple للمنطقة التي تم تصويرها.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            Section("تشخيص إعادة البناء") {
                LabeledContent("صور غير صالحة", value: "\(model.invalidSampleCount)")
                LabeledContent("صور تم تخطيها", value: "\(model.skippedSampleCount)")
                LabeledContent("خفض تلقائي للبيانات", value: model.automaticDownsamplingOccurred ? "نعم" : "لا")
            }
            if let url = model.modelURL {
                Section("النموذج") {
                    Button { showPreview = true } label: { Label("فتح في Quick Look", systemImage: "arkit") }
                    ShareLink(item: url) { Label("مشاركة USDZ", systemImage: "square.and.arrow.up") }
                }
            }
            Section { Button("مسح منطقة جديدة") { model.cancelAndReset() } }
        }
    }

    private var failedView: some View {
        ContentUnavailableView {
            Label("تعذر إكمال Area Mode", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(model.statusMessage)
        } actions: {
            Button("العودة") { model.cancelAndReset() }.buttonStyle(.borderedProminent)
        }
    }

    private var unsupportedView: some View {
        ContentUnavailableView {
            Label("Area Mode غير متاح", systemImage: "iphone.slash")
        } description: {
            Text("Apple Area Mode يحتاج iOS 18 أو أحدث وجهازًا يدعم Object Capture.")
        }
    }
}

@available(iOS 18.0, *)
private struct AppleAreaObjectCaptureView: View {
    let session: ObjectCaptureSession

    var body: some View {
        ObjectCaptureView(session: session)
            .hideObjectReticle()
    }
}

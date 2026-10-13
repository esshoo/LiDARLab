import RealityKit
import SwiftUI

struct GuidedObjectScanView: View {
    private enum Panel { case info, actions }

    @StateObject private var model = ObjectScanViewModel()
    @StateObject private var torch = SharedTorchController()
    @State private var showPointCloud = false
    @State private var showModelPreview = false
    @State private var showCancelConfirmation = false
    @State private var showEarlyFinishConfirmation = false
    @State private var panel: Panel?

    var body: some View {
        Group {
            if !model.isSupported {
                unsupportedView
            } else {
                content
            }
        }
        .navigationTitle("مسح مجسم 3D")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.phase != .idle && model.phase != .completed && model.phase != .failed {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("إلغاء", role: .destructive) { showCancelConfirmation = true }
                }
            }
        }
        .confirmationDialog("إلغاء مسح المجسم؟", isPresented: $showCancelConfirmation) {
            Button("إلغاء المسح", role: .destructive) { model.cancelAndReset() }
            Button("متابعة", role: .cancel) {}
        }
        .confirmationDialog("التغطية ما زالت غير مكتملة", isPresented: $showEarlyFinishConfirmation) {
            Button("إنهاء وبناء النموذج الآن") { model.finishCapture() }
            Button("متابعة المسح", role: .cancel) {}
        } message: {
            Text(model.finishWarningMessage)
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
                        .navigationTitle("الشبكة ونقاط التصوير")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("إغلاق") { showPointCloud = false }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showModelPreview) {
            if let url = model.modelURL {
                NavigationStack {
                    QuickLookPreview(url: url)
                        .navigationTitle("معاينة المجسم")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("إغلاق") { showModelPreview = false }
                            }
                        }
                }
            }
        }
        .keepScreenAwakeForLiveTool(
            id: "color3d.object.guided",
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
        case .aiming: aimingView
        case .preparing, .readyForDetection, .detecting, .capturing, .finishing: officialCaptureView
        case .reconstructing: processingView
        case .completed: completedView
        case .failed: failureView
        }
    }

    private var startView: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(.cyan)
                Text("مسح مجسم باستخدام Object Capture")
                    .font(.title2.bold())
                Text("اختر المجسم باللمس، ضع الهدف في المنتصف، ثم اترك Object Capture يدير الاكتشاف والتغطية.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button {
                    model.startNewScan()
                } label: {
                    Label("فتح الكاميرا واختيار المجسم", systemImage: "camera.viewfinder")
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

    private var aimingView: some View {
        ZStack {
            ObjectScanARViewContainer(model: model)
                .ignoresSafeArea(edges: .bottom)

            VStack {
                HStack {
                    LiveCameraStatusBadge(
                        title: model.targetSelected ? (model.targetCentered ? "الهدف في المنتصف" : "حرّك الهدف للمنتصف") : "المس المجسم",
                        detail: "AR: \(model.trackingState)",
                        systemImage: "scope",
                        accent: model.targetCentered ? .green : .cyan
                    )
                    Spacer()
                }
                .padding(.leading, 12)
                .padding(.top, 10)
                Spacer()
            }

            sideRail

            if let panel {
                HStack {
                    Spacer()
                    panelView(panel).padding(.trailing, 72)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            VStack {
                Spacer()
                aimingBottomBar
                    .padding(.bottom, 12)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: panel != nil)
    }

    @ViewBuilder
    private var aimingBottomBar: some View {
        if !model.cameraReady {
            LiveCameraStatusBadge(title: "تهيئة الكاميرا…", systemImage: "hourglass")
        } else if !model.targetSelected {
            LiveCameraStatusBadge(title: "المس مباشرة على المجسم", detail: "لن يبدأ المسح قبل اختيار الهدف", systemImage: "hand.tap.fill")
        } else {
            LiveCameraBottomBar {
                Button("اختيار من جديد") { model.clearTargetSelection() }
                    .buttonStyle(.bordered)
                Button {
                    model.acceptTargetAndPrepareObjectCapture()
                } label: {
                    Label("اعتماد الهدف", systemImage: "checkmark.scope")
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .disabled(!model.targetCentered)
            }
        }
    }

    private var officialCaptureView: some View {
        ZStack {
            if let session = model.captureSession {
                if model.phase == .capturing && model.scanPassComplete {
                    pointCloudView(session: session)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ObjectCaptureView(session: session)
                        .ignoresSafeArea(edges: .bottom)
                }
            } else {
                Color.black
            }

            VStack {
                HStack {
                    LiveCameraStatusBadge(
                        title: model.phase.title,
                        detail: compactStatusDetail,
                        systemImage: model.scanPassComplete ? "checkmark.circle.fill" : "viewfinder",
                        accent: model.scanPassComplete ? .green : .cyan
                    )
                    Spacer()
                }
                .padding(.leading, 12)
                .padding(.top, 10)
                Spacer()
            }

            sideRail

            if let panel {
                HStack {
                    Spacer()
                    panelView(panel).padding(.trailing, 72)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            VStack {
                Spacer()
                officialBottomBar
                    .padding(.bottom, 12)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: panel != nil)
    }

    private var sideRail: some View {
        HStack {
            Spacer()
            LiveCameraSideRail {
                LiveCameraSideButton(
                    systemImage: torch.isOn ? "flashlight.on.fill" : "flashlight.off.fill",
                    accessibilityLabel: "الكشاف",
                    tint: torch.isOn ? .yellow : nil,
                    isEnabled: torch.isAvailable
                ) { torch.toggle() }
                LiveCameraSideButton(systemImage: "info.circle", accessibilityLabel: "معلومات المسح", isSelected: panel == .info) { toggle(.info) }
                LiveCameraSideButton(systemImage: "ellipsis.circle", accessibilityLabel: "إجراءات إضافية", isSelected: panel == .actions) { toggle(.actions) }
                if model.captureSession != nil {
                    LiveCameraSideButton(systemImage: "point.3.connected.trianglepath.dotted", accessibilityLabel: "مراجعة Point Cloud") { showPointCloud = true }
                }
            }
            .padding(.trailing, 10)
        }
    }

    private var compactStatusDetail: String {
        if model.phase == .capturing {
            return "\(model.shotCount) صورة • جولة \(model.passNumber) • \(model.captureTrackingState)"
        }
        return model.statusMessage
    }

    @ViewBuilder
    private var officialBottomBar: some View {
        switch model.phase {
        case .preparing:
            LiveCameraStatusBadge(title: "تهيئة Object Capture…", systemImage: "hourglass")
        case .readyForDetection:
            LiveCameraBottomBar {
                Button {
                    model.startOfficialDetection()
                } label: {
                    Label("بدء التعرف", systemImage: "viewfinder")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }
        case .detecting:
            LiveCameraBottomBar {
                Button("إعادة التحديد") { model.resetDetection() }
                    .buttonStyle(.bordered)
                Button {
                    model.startCapturing()
                } label: {
                    Label("ابدأ المسح", systemImage: "record.circle")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }
        case .capturing:
            LiveCameraBottomBar {
                Button {
                    model.requestManualShot()
                } label: {
                    Image(systemName: "camera.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("صورة إضافية")

                Button {
                    if model.shouldWarnBeforeFinish { showEarlyFinishConfirmation = true }
                    else { model.finishCapture() }
                } label: {
                    Label("إنهاء", systemImage: "stop.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!model.canFinishCapture)
            }
        case .finishing:
            LiveCameraStatusBadge(title: "حفظ بيانات الالتقاط…", systemImage: "hourglass")
        default:
            EmptyView()
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
                    LabeledContent("الجولة الحالية", value: "\(model.passNumber)")
                    LabeledContent("الجولات المكتملة", value: "\(model.completedPasses) / \(model.recommendedPasses)")
                    if model.phase == .capturing {
                        LabeledContent("تتبع الكاميرا", value: model.captureTrackingState)
                    }
                    if let feedback = model.feedbackMessage {
                        Label(feedback, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if model.targetSelected, model.currentDistanceMeters > 0 {
                        LabeledContent("المسافة", value: String(format: "%.2f م", model.currentDistanceMeters))
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
                        if model.scanPassComplete {
                            Button {
                                model.beginAdditionalPass()
                                self.panel = nil
                            } label: {
                                Label("جولة إضافية", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            Button {
                                model.beginPassAfterFlip()
                                self.panel = nil
                            } label: {
                                Label("جولة بعد قلب المجسم", systemImage: "arrow.2.circlepath").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    if model.targetSelected && model.phase == .aiming {
                        Button("إلغاء اختيار الهدف") {
                            model.clearTargetSelection()
                            self.panel = nil
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
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 70)).foregroundStyle(.green)
                Text("تم إنشاء المجسم").font(.title2.bold())
                if let url = model.modelURL {
                    Button { showModelPreview = true } label: {
                        Label("معاينة 3D", systemImage: "arkit").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    ShareLink(item: url) {
                        Label("مشاركة USDZ", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                if model.invalidSampleCount > 0 || model.skippedSampleCount > 0 {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("تشخيص RealityKit", systemImage: "waveform.path.ecg").font(.headline)
                        Text("صور غير صالحة: \(model.invalidSampleCount)")
                        Text("صور تم تخطيها: \(model.skippedSampleCount)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                Button("مسح مجسم جديد") { model.cancelAndReset() }
            }
            .padding()
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }

    private var failureView: some View {
        ContentUnavailableView {
            Label("تعذر إكمال المسح", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(model.statusMessage)
        } actions: {
            Button("بدء جلسة جديدة") { model.cancelAndReset() }.buttonStyle(.borderedProminent)
        }
    }

    private var unsupportedView: some View {
        ContentUnavailableView {
            Label("Object Capture غير مدعوم", systemImage: "iphone.slash")
        } description: {
            Text("هذا الوضع يحتاج جهازًا يدعم RealityKit Object Capture وPhotogrammetry.")
        }
    }
}

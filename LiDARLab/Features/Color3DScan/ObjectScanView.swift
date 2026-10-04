import RealityKit
import SwiftUI

struct GuidedObjectScanView: View {
    @StateObject private var model = ObjectScanViewModel()
    @StateObject private var torch = SharedTorchController()
    @State private var showPointCloud = false
    @State private var showModelPreview = false
    @State private var showCancelConfirmation = false
    @State private var showEarlyFinishConfirmation = false

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
        .keepScreenAwakeDuringColor3DScan(model.phase != .idle && model.phase != .completed && model.phase != .failed)
        .onAppear { torch.refreshAvailability() }
        .onDisappear { torch.turnOff() }
    }

    @ViewBuilder
    private func pointCloudView(session: ObjectCaptureSession) -> some View {
        if #available(iOS 18.0, *) {
            ObjectCapturePointCloudView(session: session)
                .showShotLocations()
        } else {
            ObjectCapturePointCloudView(session: session)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            startView
        case .aiming:
            aimingView
        case .preparing, .readyForDetection, .detecting, .capturing, .finishing:
            officialCaptureView
        case .reconstructing:
            processingView
        case .completed:
            completedView
        case .failed:
            failureView
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

                Text("اللمس هنا مرحلة توجيه فقط: تختار المجسم، ثم تضعه في منتصف الإطار. بعد ذلك تتولى واجهة Apple اكتشاف حدوده وعرض الـPoint Cloud وCapture Dial أثناء الدوران.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 9) {
                    Label("لف ببطء وحافظ على تداخل واضح بين الزوايا، ولا تعتمد على عدد الصور وحده.", systemImage: "arrow.triangle.2.circlepath")
                    Label("الأجسام الشفافة أو شديدة اللمعان أو عديمة التفاصيل قد تتشوه في Photogrammetry؛ الإضاءة المنتشرة والخلفية البسيطة تساعد كثيرًا.", systemImage: "lightbulb.max")
                    Label("استهدف إكمال Capture Dial ثم راجع Point Cloud قبل الإنهاء؛ 3 جولات من ارتفاعات مختلفة هي الإعداد الموصى به افتراضيًا.", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

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
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    private var aimingView: some View {
        ZStack {
            ObjectScanARViewContainer(model: model)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                aimingStatus
                Spacer()
                aimingControls
            }
        }
    }

    private var aimingStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.phase.title)
                    .font(.headline)
                Spacer()
                SharedTorchToggleButton(controller: torch, compact: true)
                Text(model.trackingState)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.targetSelected {
                HStack {
                    Label(model.targetCentered ? "الهدف في المنتصف" : "حرّك الهدف للمنتصف",
                          systemImage: model.targetCentered ? "scope" : "arrow.up.left.and.arrow.down.right")
                        .foregroundStyle(model.targetCentered ? .green : .orange)
                    Spacer()
                    if model.currentDistanceMeters > 0 {
                        Text(String(format: "%.2f م", model.currentDistanceMeters))
                            .monospacedDigit()
                    }
                }
                .font(.caption)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17))
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private var aimingControls: some View {
        VStack(spacing: 10) {
            if !model.cameraReady {
                ProgressView()
                Text("تهيئة الكاميرا وبيانات العمق…")
                    .font(.caption)
            } else if !model.targetSelected {
                Label("المس مباشرة على المجسم الذي تريد مسحه", systemImage: "hand.tap.fill")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            } else {
                if model.shouldShowPreselectionMesh {
                    Label("الشبكة الملوّنة فوق المشهد هي LiDAR Scene Mesh حقيقية تساعدك على التأكد أن الحساس يقرأ شكل السطح قبل بدء Object Capture.", systemImage: "triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack {
                    Button("اختيار من جديد") { model.clearTargetSelection() }
                        .buttonStyle(.bordered)

                    Button {
                        model.acceptTargetAndPrepareObjectCapture()
                    } label: {
                        Label("اعتماد الهدف", systemImage: "checkmark.scope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(!model.targetCentered)
                }
            }
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(12)
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
                Color.clear
            }

            VStack(spacing: 0) {
                officialStatus
                Spacer()
                officialControls
            }
        }
    }

    private var officialStatus: some View {
        VStack(spacing: 7) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.phase.title)
                        .font(.headline)
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                SharedTorchToggleButton(controller: torch, compact: true)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(model.shotCount)")
                        .font(.title3.bold().monospacedDigit())
                    Text("صورة")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if model.phase == .capturing {
                HStack {
                    Label("الجولة الحالية \(model.passNumber)", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Label("مكتملة \(model.completedPasses)/\(model.recommendedPasses)", systemImage: "checkmark.circle")
                        .foregroundStyle(model.completedPasses >= model.recommendedPasses ? Color.green : Color.secondary)
                }
                .font(.caption)

                HStack {
                    Label(model.captureTrackingState, systemImage: "scope")
                    Spacer()
                    if model.scanPassComplete {
                        Label("راجع Point Cloud", systemImage: "point.3.connected.trianglepath.dotted")
                            .foregroundStyle(.green)
                    } else {
                        Text("أكمل Capture Dial")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }

            if let feedback = model.feedbackMessage {
                Label(feedback, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17))
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var officialControls: some View {
        VStack(spacing: 10) {
            switch model.phase {
            case .preparing:
                ProgressView()
                Text("تهيئة Object Capture الرسمي…")
                    .font(.caption)

            case .readyForDetection:
                Text("تأكد أن المجسم في منتصف الإطار؛ Apple ستكتشف حدوده من المركز.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                Button {
                    model.startOfficialDetection()
                } label: {
                    Label("بدء التعرف على المجسم", systemImage: "viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)

            case .detecting:
                Text("عدّل Bounding Box حتى يحيط بالمجسم فقط. هذه هي مرحلة تحديد الحجم والشكل قبل الالتقاط.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                HStack {
                    Button("إعادة التحديد") { model.resetDetection() }
                        .buttonStyle(.bordered)
                    Button {
                        model.startCapturing()
                    } label: {
                        Label("ابدأ المسح", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                }

            case .capturing:
                HStack(spacing: 8) {
                    Button {
                        model.requestManualShot()
                    } label: {
                        Label("صورة إضافية", systemImage: "camera.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showPointCloud = true
                    } label: {
                        Label("مراجعة الشبكة", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(.bordered)
                }

                if model.scanPassComplete {
                    Text("تمت الجولة الحالية. المعروض الآن هو Point Cloud الفعلي للجلسة مع مواقع الصور؛ لفّ النموذج وتأكد من عدم وجود مناطق ناقصة قبل المتابعة.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 8) {
                        Button("جولة إضافية") { model.beginAdditionalPass() }
                            .buttonStyle(.bordered)
                        Button("جولة بعد قلب المجسم") { model.beginPassAfterFlip() }
                            .buttonStyle(.bordered)
                    }
                    .font(.caption)
                }

                Button {
                    if model.shouldWarnBeforeFinish {
                        showEarlyFinishConfirmation = true
                    } else {
                        model.finishCapture()
                    }
                } label: {
                    Label("إنهاء الآن وبناء النموذج", systemImage: "stop.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!model.canFinishCapture)

                if !model.canFinishCapture {
                    Text("زر الإنهاء يصبح متاحًا بعد \(model.minimumImagesBeforeFinish) صور، لكن جودة الشكل تعتمد أساسًا على اكتمال Capture Dial وPoint Cloud من كل الجهات.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else if model.completedPasses < model.recommendedPasses {
                    Text("يمكنك الإنهاء يدويًا، لكن لديك \(model.completedPasses) من \(model.recommendedPasses) جولات موصى بها. الجولة الإضافية من ارتفاع مختلف تقلل الحواف الناقصة والتشوهات.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

            case .finishing:
                ProgressView()
                Text("حفظ بيانات Object Capture…")
                    .font(.caption)

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
            Text("بناء النموذج بواسطة RealityKit")
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
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(.green)
                Text("تم إنشاء المجسم")
                    .font(.title2.bold())

                if let url = model.modelURL {
                    Button {
                        showModelPreview = true
                    } label: {
                        Label("معاينة 3D", systemImage: "arkit")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)

                    ShareLink(item: url) {
                        Label("مشاركة USDZ", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if model.invalidSampleCount > 0 || model.skippedSampleCount > 0 {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("تشخيص الجودة", systemImage: "waveform.path.ecg")
                            .font(.headline)
                        if model.invalidSampleCount > 0 {
                            Text("• صور غير صالحة: \(model.invalidSampleCount)")
                        }
                        if model.skippedSampleCount > 0 {
                            Text("• صور لم تستخدمها RealityKit: \(model.skippedSampleCount)")
                        }
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
            Button("بدء جلسة جديدة") { model.cancelAndReset() }
                .buttonStyle(.borderedProminent)
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

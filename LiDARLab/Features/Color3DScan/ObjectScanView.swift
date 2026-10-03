import RealityKit
import SwiftUI

struct ObjectScanView: View {
    @StateObject private var model = ObjectScanViewModel()
    @State private var showModelPreview = false
    @State private var showCancelConfirmation = false

    var body: some View {
        Group {
            if !model.isSupported {
                unsupportedView
            } else if model.phase == .idle {
                startView
            } else if model.phase == .reconstructing || model.phase == .finishing {
                processingView
            } else if model.phase == .completed, let modelURL = model.modelURL {
                completedView(modelURL: modelURL)
            } else if let session = model.objectCaptureSession {
                captureView(session: session)
            } else if model.phase == .failed {
                failureView
            } else {
                ProgressView("جاري تجهيز الماسح…")
            }
        }
        .navigationTitle("مسح جسم 3D")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.phase != .idle && model.phase != .completed {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("إلغاء", role: .destructive) {
                        showCancelConfirmation = true
                    }
                }
            }
        }
        .confirmationDialog(
            "إلغاء المسح الحالي؟",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("إلغاء المسح", role: .destructive) {
                model.cancelAndReset()
            }
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
        .sheet(isPresented: $showModelPreview) {
            if let url = model.modelURL {
                NavigationStack {
                    QuickLookPreview(url: url)
                        .navigationTitle("النموذج ثلاثي الأبعاد")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("إغلاق") { showModelPreview = false }
                            }
                        }
                }
            }
        }
        .onDisappear {
            if model.phase == .capturing || model.phase == .detecting || model.phase == .ready {
                model.pauseCapture()
            }
        }
    }

    private var startView: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(.cyan)
                    .padding(.top, 34)

                VStack(spacing: 8) {
                    Text("مسح جسم ثلاثي الأبعاد بالألوان")
                        .font(.title2.bold())
                    Text("ضع تمثالًا أو أداة أو قطعة ثابتة في إضاءة جيدة، ثم تحرّك حولها. التطبيق يلتقط الصور وبيانات العمق ويُنشئ نموذج USDZ ملوّن على الجهاز.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 11) {
                    Label("اترك مساحة للحركة 360° حول الجسم.", systemImage: "arrow.triangle.2.circlepath")
                    Label("تجنب الزجاج والأسطح العاكسة قدر الإمكان.", systemImage: "light.max")
                    Label("لا تحرك الجسم أثناء الجولة إلا عند اختيار جولة بعد القلب.", systemImage: "hand.raised")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

                Button {
                    model.startNewScan()
                } label: {
                    Label("بدء مسح جسم", systemImage: "camera.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    private func captureView(session: ObjectCaptureSession) -> some View {
        ZStack {
            ObjectCaptureView(session: session)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                captureStatusOverlay
                Spacer()
                captureControls
            }
        }
        .onAppear {
            model.resumeCapture()
        }
    }

    private var captureStatusOverlay: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.phase.title)
                    .font(.headline)
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(model.shotCount) صورة")
                    .font(.headline.monospacedDigit())
                if model.maximumShotCount > 0 {
                    Text("حد الجهاز \(model.maximumShotCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var captureControls: some View {
        VStack(spacing: 10) {
            if model.feedbackCount > 0 && model.phase == .capturing {
                Label("يوجد \(model.feedbackCount) تنبيه جودة من نظام Object Capture", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            switch model.phase {
            case .initializing:
                VStack(spacing: 9) {
                    ProgressView("تهيئة الكاميرا وLiDAR…")
                    if model.initializationIsSlow {
                        Text(model.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                        Button("إعادة تهيئة الكاميرا") {
                            model.retryInitialization()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }

            case .ready:
                Button {
                    model.startDetecting()
                } label: {
                    Label("تحديد الجسم", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)

            case .detecting:
                HStack {
                    Button("إعادة التحديد") { model.resetDetection() }
                        .buttonStyle(.bordered)
                    Button {
                        model.startCapturing()
                    } label: {
                        Label("بدء الالتقاط", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                }

            case .capturing:
                if model.scanPassComplete {
                    VStack(spacing: 9) {
                        Text("اكتملت جولة 360°")
                            .font(.headline)
                            .foregroundStyle(.green)

                        HStack {
                            Button("جولة أخرى") { model.beginAdditionalPass() }
                                .buttonStyle(.bordered)

                            if model.objectMayBeFlipped {
                                Button("اقلب الجسم") { model.beginPassAfterFlip() }
                                    .buttonStyle(.bordered)
                            }
                        }

                        Button {
                            model.finishCapture()
                        } label: {
                            Label("إنهاء وبناء النموذج", systemImage: "cube.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                } else {
                    HStack {
                        Button {
                            model.requestManualShot()
                        } label: {
                            Image(systemName: "camera.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.canRequestManualShot)

                        Text("تحرّك ببطء حول الجسم حتى يكتمل مؤشر Apple.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)

                        if model.canFinishCapture {
                            Button("إنهاء") { model.finishCapture() }
                                .buttonStyle(.bordered)
                        }
                    }
                }

            default:
                EmptyView()
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(12)
    }

    private var processingView: some View {
        VStack(spacing: 22) {
            ProgressView(value: model.phase == .reconstructing ? model.reconstructionProgress : nil)
                .progressViewStyle(.linear)
                .frame(maxWidth: 420)

            Image(systemName: model.phase == .reconstructing ? "cube.transparent" : "externaldrive.badge.checkmark")
                .font(.system(size: 54))
                .foregroundStyle(.cyan)

            Text(model.phase.title)
                .font(.title2.bold())

            Text(model.statusMessage)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if model.phase == .reconstructing {
                Text("\(Int(model.reconstructionProgress * 100))%")
                    .font(.title3.monospacedDigit().bold())
            }
        }
        .padding()
    }

    private func completedView(modelURL: URL) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(.green)

                Text("تم إنشاء النموذج الملوّن")
                    .font(.title2.bold())

                Text(modelURL.lastPathComponent)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Button {
                    showModelPreview = true
                } label: {
                    Label("معاينة 3D", systemImage: "arkit")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)

                ShareLink(item: modelURL) {
                    Label("مشاركة ملف USDZ", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button("مسح جسم جديد") {
                    model.cancelAndReset()
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
    }

    private var failureView: some View {
        ContentUnavailableView {
            Label("تعذر إكمال المسح", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(model.statusMessage)
        } actions: {
            Button("بدء جلسة جديدة") {
                model.cancelAndReset()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var unsupportedView: some View {
        ContentUnavailableView {
            Label("Object Capture غير مدعوم", systemImage: "iphone.slash")
        } description: {
            Text("مسح الأجسام الملوّن يحتاج جهازًا يدعم Object Capture وLiDAR. يمكنك استخدام مسح المكان السريع إذا كان Scene Mesh مدعومًا.")
        }
    }
}

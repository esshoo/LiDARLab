import RealityKit
import SwiftUI

struct AreaScanView: View {
    @StateObject private var model = AreaScanViewModel()
    @State private var showPointCloud = false
    @State private var showPreview = false
    @State private var showCancelConfirmation = false

    var body: some View {
        Group {
            if !model.isSupported {
                unsupportedView
            } else {
                content
            }
        }
        .navigationTitle("مسح منطقة بصري 3D")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.phase == .capturing || model.phase == .ready || model.phase == .initializing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("إلغاء", role: .destructive) { showCancelConfirmation = true }
                }
            }
        }
        .confirmationDialog("إلغاء مسح المكان؟", isPresented: $showCancelConfirmation) {
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
                        .navigationTitle("معاينة Apple Quick Look")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("إغلاق") { showPreview = false }
                            }
                        }
                }
            }
        }
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
        case .initializing, .ready, .capturing, .finishing:
            captureView
        case .reconstructing:
            processingView
        case .completed:
            completedView
        case .failed:
            failedView
        }
    }

    private var startView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 68, weight: .light))
                    .foregroundStyle(.cyan)

                Text("Apple Area Mode — منطقة / سطح")
                    .font(.title2.bold())

                Text("هذا الوضع مخصص لمسح منطقة أو سطح بصريًا باستخدام Apple Object Capture Area Mode. لا نستخدمه بعد الآن كبديل لـRoomPlan عند الحاجة إلى غرفة هندسية كاملة.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Label("قسّم الغرفة الكبيرة إلى جدران أو مناطق صغيرة بدل لقطة واحدة ضخمة", systemImage: "square.split.2x2")
                    Label("تحرك ببطء، موازياً للسطح، مع تداخل واضح بين اللقطات", systemImage: "figure.walk")
                    Label("كرر المرور من ارتفاعات مختلفة", systemImage: "arrow.up.and.down")
                    Label("تجنب الإضاءة القاسية والظلال الحادة", systemImage: "sun.max")
                    Label("المعالجة على iPhone تستخدم Reduced detail", systemImage: "iphone")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

                NavigationLink {
                    RoomScanView()
                } label: {
                    Label("غرفة كاملة ودقيقة — RoomPlan", systemImage: "ruler.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    model.prepareSession()
                } label: {
                    Label("مسح منطقة / سطح بصري", systemImage: "camera.viewfinder")
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

    private var captureView: some View {
        ZStack {
            if #available(iOS 18.0, *), let session = model.captureSession {
                AppleAreaObjectCaptureView(session: session)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                Color.clear
            }

            VStack(spacing: 0) {
                statusOverlay
                Spacer()
                controlsOverlay
            }
        }
    }

    private var statusOverlay: some View {
        VStack(spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.phase.title)
                        .font(.headline)
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(model.shotCount)")
                        .font(.title3.bold().monospacedDigit())
                    Text("صورة")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
    private var controlsOverlay: some View {
        VStack(spacing: 10) {
            if model.phase == .initializing {
                ProgressView()
                Text("تهيئة Object Capture…")
                    .font(.caption)
            } else if model.phase == .ready {
                Button {
                    model.startAreaCapture()
                } label: {
                    Label("بدء المسح", systemImage: "record.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            } else if model.phase == .capturing {
                HStack(spacing: 9) {
                    Button {
                        model.requestManualShot()
                    } label: {
                        Label("صورة", systemImage: "camera.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showPointCloud = true
                    } label: {
                        Label("التغطية", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    model.finishCapture()
                } label: {
                    Label("إنهاء وبناء النموذج", systemImage: "stop.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!model.canFinishCapture)

                if !model.canFinishCapture {
                    Text("يمكن الإنهاء بعد \(model.minimumImagesBeforeFinish) صور على الأقل. أنت من يحدد وقت الإنهاء، وليس التطبيق.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else if model.phase == .finishing {
                ProgressView()
                Text("حفظ بيانات الالتقاط…")
                    .font(.caption)
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
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.green)
                    Text("اكتمل المسح البصري للمنطقة")
                        .font(.title2.bold())
                    Text("النتيجة هي Photogrammetry رسمي من Apple. إذا كانت المنطقة أكبر من قدرة المعالجة على الهاتف، احتفظ بصور المصدر لمعالجة أعلى جودة على Mac.")
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
                    Button {
                        showPreview = true
                    } label: {
                        Label("فتح في Quick Look", systemImage: "arkit")
                    }
                    ShareLink(item: url) {
                        Label("مشاركة USDZ", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section {
                Button("مسح مكان جديد") { model.cancelAndReset() }
            }
        }
    }

    private var failedView: some View {
        ContentUnavailableView {
            Label("تعذر إكمال Area Mode", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(model.statusMessage)
        } actions: {
            Button("العودة") { model.cancelAndReset() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var unsupportedView: some View {
        ContentUnavailableView {
            Label("Area Mode غير متاح", systemImage: "iphone.slash")
        } description: {
            Text("Apple Area Mode يحتاج iOS 18 أو أحدث وجهازًا يدعم Object Capture. للمسح الهندسي الكامل للغرفة استخدم RoomPlan المتاح كأداة مستقلة داخل التطبيق.")
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

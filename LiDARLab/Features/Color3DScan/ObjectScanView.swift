import SwiftUI

struct ObjectScanView: View {
    @StateObject private var model = ObjectScanViewModel()
    @State private var showModelPreview = false
    @State private var showCancelConfirmation = false

    var body: some View {
        Group {
            if !model.isSupported {
                unsupportedView
            } else {
                switch model.phase {
                case .idle:
                    startView
                case .selecting, .capturing:
                    scannerView
                case .reconstructing:
                    processingView
                case .completed:
                    completedView
                case .failed:
                    failureView
                }
            }
        }
        .navigationTitle("مسح مجسم 3D")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.phase == .selecting || model.phase == .capturing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("إلغاء", role: .destructive) {
                        showCancelConfirmation = true
                    }
                }
            }
        }
        .confirmationDialog("إلغاء مسح المجسم؟", isPresented: $showCancelConfirmation, titleVisibility: .visible) {
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
        .onDisappear {
            if model.phase == .selecting || model.phase == .capturing {
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
                    Text("مسح مجسم ملوّن باللمس")
                        .font(.title2.bold())
                    Text("المس المجسم نفسه لتثبيت نقطة الهدف، ثم لف حوله. التطبيق يحسب التغطية ويجمع الصور حسب إعدادات كثافة البيانات، وأنت الذي تضغط إنهاء عندما تكون النتيجة كافية.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 11) {
                    Label("الاختيار يتم من نقطة العمق التي تلمسها، وليس من صندوق تلقائي عشوائي.", systemImage: "hand.tap.fill")
                    Label("الحجم الحالي: \(model.objectSizeTitle) — يمكن تغييره من الإعدادات.", systemImage: "arrow.up.left.and.arrow.down.right")
                    Label("لا يوجد انتظار لإنهاء تلقائي؛ زر الإنهاء يظل تحت تحكمك.", systemImage: "stop.circle")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

                Button {
                    model.startNewScan()
                } label: {
                    Label("فتح الكاميرا وتحديد المجسم", systemImage: "camera.viewfinder")
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

    private var scannerView: some View {
        ZStack {
            ObjectScanARViewContainer(model: model)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                statusOverlay
                Spacer()
                controlsOverlay
            }
        }
    }

    private var statusOverlay: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.phase.title)
                        .font(.headline)
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if model.phase == .capturing {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(model.estimatedCompletion * 100))%")
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(.cyan)
                        Text("تقدم تقديري")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if model.phase == .capturing {
                ProgressView(value: model.estimatedCompletion)
                    .progressViewStyle(.linear)

                HStack(spacing: 14) {
                    ObjectMetric(title: "صور", value: "\(model.capturedImageCount)/\(model.targetImageCount)")
                    ObjectMetric(title: "تغطية", value: "\(Int(model.coverageProgress * 100))%")
                    ObjectMetric(title: "مسافة", value: model.currentDistanceMeters > 0 ? String(format: "%.2fم", model.currentDistanceMeters) : "—")
                    ObjectMetric(title: "تتبع", value: model.trackingState)
                }
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
            if model.phase == .selecting {
                if !model.cameraReady {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("جاري تهيئة الكاميرا وبيانات العمق…")
                            .font(.headline)
                        Text("سيصبح اختيار المجسم متاحًا تلقائيًا بمجرد وصول أول إطار AR صالح.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else if model.targetSelected {
                    Label("تم تثبيت الهدف. العلامة السماوية يجب أن تكون على المجسم المطلوب.", systemImage: "scope")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .multilineTextAlignment(.center)

                    HStack {
                        Button("اختيار من جديد") {
                            model.clearTargetSelection()
                        }
                        .buttonStyle(.bordered)

                        Button {
                            model.beginCapture()
                        } label: {
                            Label("ابدأ الالتفاف والمسح", systemImage: "record.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "hand.tap")
                            .font(.title2)
                            .foregroundStyle(.cyan)
                        Text("المس مباشرة على المجسم الذي تريد مسحه")
                            .font(.headline)
                        Text("يستخدم التطبيق Scene Depth لتثبيت نقطة ثلاثية الأبعاد على المكان الذي لمسته. إذا لم توجد قراءة عمق جيدة سيحاول Raycast كحل احتياطي.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            } else if model.phase == .capturing {
                HStack(spacing: 10) {
                    Button {
                        model.captureManualImage()
                    } label: {
                        Label("صورة", systemImage: "camera.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        model.finishCapture()
                    } label: {
                        Label("إنهاء وبناء النموذج", systemImage: "stop.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(!model.canFinishCapture)
                }

                if !model.canFinishCapture {
                    Text("يمكن الإنهاء بعد \(model.minimumImagesBeforeFinish) صور على الأقل. لا يلزم الوصول إلى 100% إذا كانت التغطية التي تريدها كافية.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("زر الإنهاء يدوي دائمًا. نسبة التقدم تقديرية مبنية على عدد الصور + الزوايا التي غطيتها حول الهدف.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(12)
    }

    private var processingView: some View {
        VStack(spacing: 22) {
            ProgressView(value: model.reconstructionProgress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 420)

            Image(systemName: "cube.transparent")
                .font(.system(size: 54))
                .foregroundStyle(.cyan)

            Text("بناء النموذج ثلاثي الأبعاد")
                .font(.title2.bold())

            Text(model.statusMessage)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("\(Int(model.reconstructionProgress * 100))%")
                .font(.title3.monospacedDigit().bold())
        }
        .padding()
    }

    private var completedView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(.green)

                Text("تم إنشاء النموذج الملوّن")
                    .font(.title2.bold())

                if let modelURL = model.modelURL {
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
                }

                Button("مسح مجسم جديد") {
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
            Label("المسح غير مدعوم", systemImage: "iphone.slash")
        } description: {
            Text("هذا الوضع يحتاج ARWorldTracking وجهازًا يدعم Photogrammetry على iPhone. يستخدم Scene Depth عند توفر LiDAR لتحديد الهدف باللمس بدقة أكبر.")
        }
    }
}

private struct ObjectMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

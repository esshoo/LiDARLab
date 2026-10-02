import SwiftUI

struct AreaScanView: View {
    @StateObject private var model = AreaScanViewModel()
    @State private var showPreview = false
    @State private var showCancelConfirmation = false

    var body: some View {
        Group {
            if !model.isSupported {
                unsupportedView
            } else if let mesh = model.completedMesh,
                      let result = model.exportResult,
                      !model.isScanning,
                      !model.isExporting {
                resultView(mesh: mesh, result: result)
            } else {
                scannerView
            }
        }
        .navigationTitle("مسح مكان 3D")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.isScanning {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("إلغاء", role: .destructive) {
                        showCancelConfirmation = true
                    }
                }
            }
        }
        .confirmationDialog(
            "إلغاء مسح المكان؟",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("إلغاء المسح", role: .destructive) { model.cancelScan() }
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
            if let mesh = model.completedMesh {
                NavigationStack {
                    AreaScanPreviewView(mesh: mesh)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle("معاينة Mesh الملوّن")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("إغلاق") { showPreview = false }
                            }
                        }
                }
            }
        }
        .onDisappear {
            if model.isScanning { model.cancelScan() }
        }
    }

    private var scannerView: some View {
        ZStack {
            AreaScanARViewContainer(model: model)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                if model.isScanning {
                    liveStats
                }
                Spacer()

                if model.isExporting {
                    exportOverlay
                } else if model.isScanning {
                    scanningControls
                } else {
                    startControls
                }
            }
        }
    }

    private var liveStats: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                AreaMetric(title: "Mesh", value: "\(model.meshAnchorCount)")
                AreaMetric(title: "Vertices", value: compact(model.vertexCount))
                AreaMetric(title: "Faces", value: compact(model.faceCount))
                AreaMetric(title: "RGB", value: "\(model.capturedFrameCount)")
            }

            HStack {
                Label("التتبع: \(model.trackingState)", systemImage: "location.viewfinder")
                    .font(.caption)
                Spacer()
                Text("LiDAR + RGB")
                    .font(.caption.bold())
                    .foregroundStyle(.cyan)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17))
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private var startControls: some View {
        VStack(spacing: 12) {
            VStack(spacing: 5) {
                Text("مسح غرفة / مكان بالألوان")
                    .font(.headline)
                Text("المسح يجمع Scene Mesh من LiDAR وصور RGB موزعة أثناء الحركة، ثم يسقط اللون على رؤوس الـMesh ويصدر نموذجًا ثلاثي الأبعاد.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                model.startScan()
            } label: {
                Label("بدء المسح الفعلي", systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(12)
    }

    private var scanningControls: some View {
        VStack(spacing: 9) {
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if model.capturedFrameCount < 5 {
                Label("استمر بالحركة لتجميع صور ألوان أكثر", systemImage: "camera.metering.center.weighted")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button {
                model.stopAndBuildModel()
            } label: {
                Label("إنهاء وبناء النموذج الملوّن", systemImage: "cube.transparent.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(model.vertexCount < 100 || model.capturedFrameCount < 2)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(12)
    }

    private var exportOverlay: some View {
        VStack(spacing: 12) {
            ProgressView(value: model.exportProgress)
                .progressViewStyle(.linear)
            Text(model.statusMessage)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("\(Int(model.exportProgress * 100))%")
                .font(.title3.bold().monospacedDigit())
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(12)
    }

    private func resultView(mesh: AreaScanColoredMesh, result: AreaScanExportResult) -> some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("اكتمل النموذج ثلاثي الأبعاد")
                        .font(.title3.bold())
                    Text("تم أخذ الألوان من صور الكاميرا وإسقاطها على Mesh الناتج من LiDAR.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("النموذج") {
                HStack {
                    Text("Vertices")
                    Spacer()
                    Text(mesh.vertexCount.formatted()).monospacedDigit()
                }
                HStack {
                    Text("Faces")
                    Spacer()
                    Text(mesh.faceCount.formatted()).monospacedDigit()
                }
                HStack {
                    Text("صور RGB")
                    Spacer()
                    Text(model.capturedFrameCount.formatted()).monospacedDigit()
                }

                Button {
                    showPreview = true
                } label: {
                    Label("معاينة النموذج داخل التطبيق", systemImage: "rotate.3d")
                }
            }

            Section("ملفات 3D") {
                ShareLink(item: result.plyURL) {
                    AreaExportRow(
                        title: "PLY ملوّن",
                        detail: "Mesh + Vertex RGB — الملف الأساسي الملوّن",
                        systemImage: "cube.fill"
                    )
                }

                ShareLink(item: result.objURL) {
                    AreaExportRow(
                        title: "OBJ",
                        detail: "هندسة + ألوان رؤوس موسعة",
                        systemImage: "shippingbox.fill"
                    )
                }

                if let usdzURL = result.usdzURL {
                    ShareLink(item: usdzURL) {
                        AreaExportRow(
                            title: "USDZ",
                            detail: "نسخة Apple عند نجاح تصدير SceneKit",
                            systemImage: "arkit"
                        )
                    }
                }

                ShareLink(item: result.manifestURL) {
                    AreaExportRow(
                        title: "scan.json",
                        detail: "Camera poses + intrinsics + معلومات الجلسة",
                        systemImage: "doc.text"
                    )
                }
            }

            Section {
                Button("بدء مسح مكان جديد") {
                    model.resetForNewScan()
                }
            }
        }
    }

    private var unsupportedView: some View {
        ContentUnavailableView {
            Label("Scene Mesh غير مدعوم", systemImage: "iphone.slash")
        } description: {
            Text("مسح الغرفة ثلاثي الأبعاد يحتاج جهاز iPhone أو iPad يدعم LiDAR وARKit Scene Reconstruction.")
        }
    }

    private func compact(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName))
    }
}

private struct AreaMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AreaExportRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.cyan)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

import SwiftUI

struct RoomScanView: View {
    @StateObject private var model = RoomScanViewModel()
    @State private var showingShareSheet = false
    @State private var showingResetConfirmation = false
    @State private var shareItems: [Any] = []

    var body: some View {
        ZStack {
            RoomCaptureViewContainer(model: model)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 12) {
                statusPanel
                Spacer(minLength: 10)
                controls
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(.black)
        .navigationTitle("مسح متعدد الغرف")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.stopWithoutProcessing() }
        .sheet(isPresented: $showingShareSheet) {
            ActivityView(items: shareItems)
        }
        .alert("حذف جلسة المسح الحالية؟", isPresented: $showingResetConfirmation) {
            Button("حذف وبدء جديد", role: .destructive) {
                model.resetBuilding()
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("سيتم حذف الغرف الموجودة في ذاكرة الجلسة الحالية. ملفات JSON التي حُفظت بالفعل ستظل داخل مجلد Rooms.")
        }
        .alert("تعذر إكمال العملية", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "خطأ غير معروف")
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: stateIcon)
                    .foregroundStyle(stateColor)
                Text(model.statusMessage)
                    .font(.caption.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if model.isProcessing {
                    ProgressView()
                }
            }

            if model.isScanning {
                Label(
                    "الغرفة \(model.activeRoomNumber): لا تعبر الباب قبل إنهاء الغرفة.",
                    systemImage: "door.left.hand.closed"
                )
                .font(.caption)
                .foregroundStyle(.yellow)
            }

            if model.roomCount > 0 {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                    MetricChip(title: "غرف مثبتة", value: "\(model.roomCount)", systemImage: "square.grid.2x2")
                    MetricChip(title: "كل الجدران", value: "\(model.totalWallCount)", systemImage: "rectangle.split.3x1")
                    MetricChip(title: "كل الأبواب", value: "\(model.totalDoorCount)", systemImage: "door.left.hand.open")
                    MetricChip(title: "كل النوافذ", value: "\(model.totalWindowCount)", systemImage: "window.vertical.closed")
                }
            }

            if model.capturedRoom != nil {
                Divider()
                Text("آخر غرفة مثبتة")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                    MetricChip(title: "جدران", value: "\(model.wallCount)", systemImage: "rectangle.split.3x1")
                    MetricChip(title: "أبواب", value: "\(model.doorCount)", systemImage: "door.left.hand.open")
                    MetricChip(title: "فتحات", value: "\(model.openingCount)", systemImage: "rectangle.dashed")
                    MetricChip(title: "عناصر", value: "\(model.objectCount)", systemImage: "chair.lounge")
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            primaryControls

            if model.capturedRoom != nil, !model.isScanning, !model.isProcessing {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { roomExportControls }
                    VStack(spacing: 10) { roomExportControls }
                }
            }

            if model.capturedStructure != nil, !model.isProcessing {
                Button {
                    model.exportMergedStructure()
                } label: {
                    Label("تصدير المبنى المجمّع", systemImage: "building.2.crop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if let export = model.latestExport {
                Button {
                    shareItems = export.shareItems
                    showingShareSheet = true
                } label: {
                    Label("مشاركة JSON وUSDZ", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text(export.folderURL.lastPathComponent)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let folder = model.buildingFolderURL {
                Text("الحفظ التلقائي: \(folder.lastPathComponent)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var primaryControls: some View {
        if model.isScanning {
            Button {
                model.finishCurrentRoom()
            } label: {
                Label("إنهاء وتثبيت الغرفة \(model.activeRoomNumber)", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else if model.isProcessing {
            Button {} label: {
                Label("جارٍ المعالجة…", systemImage: "gearshape.2.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(true)
        } else if model.roomCount == 0 {
            Button {
                model.startBuildingScan()
            } label: {
                Label("بدء مسح المبنى", systemImage: "viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else if !model.isBuildingFinished {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { continuationControls }
                VStack(spacing: 10) { continuationControls }
            }

            Button(role: .destructive) {
                showingResetConfirmation = true
            } label: {
                Label("إلغاء الجلسة وبدء جديد", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else {
            Button {
                showingResetConfirmation = true
            } label: {
                Label("بدء مبنى جديد", systemImage: "plus.rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var continuationControls: some View {
        Button {
            model.startNextRoomScan()
        } label: {
            Label("مسح الغرفة \(model.nextRoomNumber)", systemImage: "plus.viewfinder")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

        Button {
            model.finishBuilding()
        } label: {
            Label("إنهاء المبنى", systemImage: "checkmark.seal.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    @ViewBuilder
    private var roomExportControls: some View {
        Button {
            model.exportLatestRoomParametric()
        } label: {
            Label("آخر غرفة Parametric", systemImage: "cube")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button {
            model.exportLatestRoomMesh()
        } label: {
            Label("آخر غرفة Mesh", systemImage: "triangle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var stateIcon: String {
        if model.isProcessing { return "gearshape.2.fill" }
        if model.isBuildingFinished { return "checkmark.seal.fill" }
        if model.roomCount > 0 { return "square.grid.2x2.fill" }
        if model.isScanning { return "record.circle" }
        return "building.2"
    }

    private var stateColor: Color {
        if model.isBuildingFinished { return .green }
        if model.roomCount > 0 { return .cyan }
        if model.isScanning { return .red }
        return .cyan
    }
}

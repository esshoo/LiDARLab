import SwiftUI

struct RoomScanView: View {
    @StateObject private var model = RoomScanViewModel()
    @State private var showingShareSheet = false
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
        .navigationTitle("مسح الغرفة")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.stopWithoutProcessing() }
        .sheet(isPresented: $showingShareSheet) {
            ActivityView(items: shareItems)
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

            if model.capturedRoom != nil {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                    MetricChip(title: "جدران", value: "\(model.wallCount)", systemImage: "rectangle.split.3x1")
                    MetricChip(title: "أبواب", value: "\(model.doorCount)", systemImage: "door.left.hand.open")
                    MetricChip(title: "نوافذ", value: "\(model.windowCount)", systemImage: "window.vertical.closed")
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
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { primaryControls }
                VStack(spacing: 10) { primaryControls }
            }

            if model.capturedRoom != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { exportControls }
                    VStack(spacing: 10) { exportControls }
                }
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
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var primaryControls: some View {
        if model.isScanning {
            Button {
                model.stopScan()
            } label: {
                Label("إنهاء ومعالجة", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            Button {
                model.startScan()
            } label: {
                Label(model.capturedRoom == nil ? "بدء المسح" : "مسح جديد", systemImage: "viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isProcessing)
        }
    }

    @ViewBuilder
    private var exportControls: some View {
        Button {
            model.exportParametric()
        } label: {
            Label("USDZ بارامتري", systemImage: "cube")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button {
            model.exportMesh()
        } label: {
            Label("USDZ Mesh", systemImage: "triangle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var stateIcon: String {
        if model.isProcessing { return "gearshape.2.fill" }
        if model.capturedRoom != nil { return "checkmark.circle.fill" }
        if model.isScanning { return "record.circle" }
        return "house.lodge"
    }

    private var stateColor: Color {
        if model.capturedRoom != nil { return .green }
        if model.isScanning { return .red }
        return .cyan
    }
}

import SwiftUI

struct RoomScanView: View {
    @StateObject private var model = RoomScanViewModel()
    @State private var showingShareSheet = false
    @State private var showingResetConfirmation = false
    @State private var showingThicknessSetup = false
    @State private var showingWallEditor = false
    @State private var shareItems: [Any] = []
    @State private var setupThicknessCentimeters = 15.0
    @State private var setupMode: RoomThicknessSetupMode = .building

    var body: some View {
        ZStack {
            RoomCaptureViewContainer(model: model)
                .ignoresSafeArea(edges: .bottom)

            if model.isPaused {
                pausedCameraOverlay
            }

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
        .sheet(isPresented: $showingThicknessSetup) {
            RoomThicknessSetupSheet(
                mode: setupMode,
                roomNumber: setupMode == .building ? 1 : model.nextRoomNumber,
                buildingDefaultCentimeters: model.buildingDefaultWallThicknessCentimeters,
                thicknessCentimeters: $setupThicknessCentimeters
            ) {
                showingThicknessSetup = false
                switch setupMode {
                case .building:
                    model.startBuildingScan(
                        defaultWallThicknessCentimeters: setupThicknessCentimeters
                    )
                case .nextRoom:
                    model.startNextRoomScan(
                        defaultWallThicknessCentimeters: setupThicknessCentimeters
                    )
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingWallEditor) {
            NavigationStack {
                RoomWallThicknessEditor(
                    model: model,
                    roomIndex: model.roomCount
                )
            }
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
                VStack(alignment: .leading, spacing: 5) {
                    Label(
                        "الغرفة \(model.activeRoomNumber): لا تعبر الباب قبل إنهاء الغرفة.",
                        systemImage: "door.left.hand.closed"
                    )
                    Label(
                        "الحائط المشترك سيأخذ نفس السماكة المسجلة للغرفة السابقة.",
                        systemImage: "link"
                    )
                }
                .font(.caption)
                .foregroundStyle(.yellow)
            }

            if model.isPaused {
                VStack(alignment: .leading, spacing: 5) {
                    Label(
                        "الغرفة \(model.activeRoomNumber) متوقفة مؤقتًا، والكاميرا والتتبع متوقفان.",
                        systemImage: "pause.circle.fill"
                    )
                    Label(
                        "الأجزاء المحفوظة: \(model.activeRoomFragmentCount). الاستكمال متاح ما دامت شاشة التطبيق الحالية مفتوحة.",
                        systemImage: "square.stack.3d.up.fill"
                    )
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if model.roomCount > 0 {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                    MetricChip(title: "غرف مثبتة", value: "\(model.roomCount)", systemImage: "square.grid.2x2")
                    MetricChip(title: "أجزاء محفوظة", value: "\(model.totalFragmentCount)", systemImage: "square.stack.3d.up")
                    MetricChip(title: "حوائط فعلية", value: "\(model.physicalWallCount)", systemImage: "rectangle.split.3x1")
                    MetricChip(title: "حوائط مشتركة", value: "\(model.sharedPhysicalWallCount)", systemImage: "link")
                    MetricChip(title: "كل الأبواب", value: "\(model.totalDoorCount)", systemImage: "door.left.hand.open")
                }

                Text("سماكة المبنى الافتراضية: \(centimetersText(model.buildingDefaultWallThicknessCentimeters)) سم")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if model.capturedRoom != nil {
                Divider()
                Text("آخر غرفة مثبتة")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                    MetricChip(title: "جدران", value: "\(model.wallCount)", systemImage: "rectangle.split.3x1")
                    MetricChip(title: "مشتركة", value: "\(model.latestRoomSharedFaceCount)", systemImage: "link")
                    MetricChip(title: "أبواب", value: "\(model.doorCount)", systemImage: "door.left.hand.open")
                    MetricChip(title: "فتحات", value: "\(model.openingCount)", systemImage: "rectangle.dashed")
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            primaryControls

            if model.capturedRoom != nil, !model.isScanning, !model.isPaused, !model.isProcessing {
                Button {
                    showingWallEditor = true
                } label: {
                    Label("مراجعة سماكات حوائط الغرفة الأخيرة", systemImage: "ruler")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

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
                    Label("مشاركة التصدير وخصائص الحوائط", systemImage: "square.and.arrow.up")
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
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { activeScanControls }
                VStack(spacing: 10) { activeScanControls }
            }
        } else if model.isPaused {
            VStack(spacing: 10) {
                Button {
                    model.resumePausedRoom()
                } label: {
                    Label("استكمال الغرفة \(model.activeRoomNumber)", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    model.finishPausedRoom()
                } label: {
                    Label("اعتماد الأجزاء وإنهاء الغرفة", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Text("لا تغلق التطبيق في هذه المرحلة؛ الاستكمال بعد إغلاق التطبيق سيُضاف في المرحلة التالية.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
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
                presentThicknessSetup(.building)
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
    private var activeScanControls: some View {
        Button {
            model.pauseCurrentRoom()
        } label: {
            Label("توقف مؤقت", systemImage: "pause.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)

        Button {
            model.finishCurrentRoom()
        } label: {
            Label("إنهاء وتثبيت الغرفة \(model.activeRoomNumber)", systemImage: "stop.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    @ViewBuilder
    private var continuationControls: some View {
        Button {
            presentThicknessSetup(.nextRoom)
        } label: {
            Label("إعداد ومسح الغرفة \(model.nextRoomNumber)", systemImage: "plus.viewfinder")
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

    private var pausedCameraOverlay: some View {
        ZStack {
            Color.black
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 14) {
                Image(systemName: "camera.slash.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.orange)
                Text("الكاميرا متوقفة مؤقتًا")
                    .font(.title3.bold())
                Text("تم حفظ الجزء الحالي من الغرفة. عند الاستكمال، ابدأ من نفس الموضع ووجّه الهاتف إلى حائط أو باب سبق مسحه.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .padding(.bottom, 40)
        }
    }

    private var stateIcon: String {
        if model.isProcessing { return "gearshape.2.fill" }
        if model.isBuildingFinished { return "checkmark.seal.fill" }
        if model.isPaused { return "pause.circle.fill" }
        if model.isScanning { return "record.circle" }
        if model.roomCount > 0 { return "square.grid.2x2.fill" }
        return "building.2"
    }

    private var stateColor: Color {
        if model.isBuildingFinished { return .green }
        if model.isPaused { return .orange }
        if model.isScanning { return .red }
        if model.roomCount > 0 { return .cyan }
        return .cyan
    }

    private func presentThicknessSetup(_ mode: RoomThicknessSetupMode) {
        setupMode = mode
        setupThicknessCentimeters = mode == .building
            ? 15.0
            : model.recommendedNextRoomThicknessCentimeters
        showingThicknessSetup = true
    }

    private func centimetersText(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}

private enum RoomThicknessSetupMode {
    case building
    case nextRoom
}

private struct RoomThicknessSetupSheet: View {
    let mode: RoomThicknessSetupMode
    let roomNumber: Int
    let buildingDefaultCentimeters: Double
    @Binding var thicknessCentimeters: Double
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let presets: [Double] = [10, 15, 20, 25, 30, 35]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: mode == .building ? "building.2" : "ruler")
                            .font(.system(size: 34))
                            .foregroundStyle(.cyan)

                        Text(title)
                            .font(.headline)

                        Text(explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("السماكة الافتراضية") {
                    HStack {
                        Text("السماكة")
                        Spacer()
                        Text("\(centimetersText(thicknessCentimeters)) سم")
                            .font(.title3.bold())
                            .monospacedDigit()
                    }

                    Stepper(
                        "تغيير السماكة بمقدار 1 سم",
                        value: $thicknessCentimeters,
                        in: 5...60,
                        step: 1
                    )

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 8)], spacing: 8) {
                        ForEach(presets, id: \.self) { preset in
                            Button {
                                thicknessCentimeters = preset
                            } label: {
                                Text("\(Int(preset)) سم")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(abs(thicknessCentimeters - preset) < 0.1 ? .cyan : nil)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("منطق الحائط المشترك") {
                    Label(
                        "هذه القيمة تُطبق على الحوائط الجديدة في الغرفة فقط.",
                        systemImage: "square.dashed"
                    )
                    Label(
                        "إذا تعرف التطبيق على وجه الحائط المقابل في غرفة سابقة، يستخدم سجل حائط واحد ونفس السماكة للغرفتين.",
                        systemImage: "link"
                    )
                    if mode == .nextRoom {
                        Label(
                            "افتراضي المبنى الحالي: \(centimetersText(buildingDefaultCentimeters)) سم",
                            systemImage: "building.2"
                        )
                    }
                }
            }
            .navigationTitle(mode == .building ? "إعداد المبنى" : "إعداد الغرفة \(roomNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("تأكيد وبدء") { onConfirm() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var title: String {
        mode == .building
            ? "حدد السماكة الأساسية قبل بدء المبنى"
            : "أكد سماكة الحوائط الجديدة للغرفة \(roomNumber)"
    }

    private var explanation: String {
        mode == .building
            ? "سيستخدم التطبيق هذه القيمة كبداية، ويمكن تعديل أي حائط لاحقًا دون تغيير هندسة RoomPlan الأصلية."
            : "يمكن أن تختلف هذه الغرفة عن السابقة. الحوائط المشتركة لا تتكرر؛ بل ترث سماكة الحائط المسجل من الجهة الأخرى."
    }

    private func centimetersText(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}

private struct RoomWallThicknessEditor: View {
    @ObservedObject var model: RoomScanViewModel
    let roomIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var bulkThicknessCentimeters = 15.0

    var body: some View {
        List {
            Section {
                Label(
                    "تعديل الحائط المشترك هنا يغيّر نفس السجل في كل الغرف المرتبطة به.",
                    systemImage: "link"
                )
                .font(.caption)

                Label(
                    "السماكة بيانات خاصة بالتطبيق ولا تعيد كتابة أسطح RoomPlan الأصلية.",
                    systemImage: "lock.shield"
                )
                .font(.caption)
            }

            Section("تطبيق سريع على الحوائط غير المشتركة") {
                Stepper(
                    "\(centimetersText(bulkThicknessCentimeters)) سم",
                    value: $bulkThicknessCentimeters,
                    in: 5...60,
                    step: 1
                )
                Button("تطبيق على الحوائط غير المشتركة فقط") {
                    model.applyThicknessToUnsharedWalls(
                        roomIndex: roomIndex,
                        centimeters: bulkThicknessCentimeters
                    )
                }
            }

            Section("حوائط الغرفة \(roomIndex)") {
                ForEach(model.wallItems(for: roomIndex)) { item in
                    RoomWallThicknessRow(model: model, item: item)
                }
            }
        }
        .navigationTitle("سماكات الحوائط")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("تم") { dismiss() }
            }
        }
        .onAppear {
            bulkThicknessCentimeters = model.recommendedNextRoomThicknessCentimeters
        }
    }

    private func centimetersText(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}

private struct RoomWallThicknessRow: View {
    @ObservedObject var model: RoomScanViewModel
    let item: RoomWallDisplayItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("الحائط \(item.wallNumber)", systemImage: item.isShared ? "link" : "rectangle")
                    .font(.headline)
                Spacer()
                Text(item.isShared ? "مشترك" : "خاص بالغرفة")
                    .font(.caption2.bold())
                    .foregroundStyle(item.isShared ? .green : .secondary)
            }

            Stepper(
                value: thicknessBinding,
                in: 5...60,
                step: 1
            ) {
                HStack {
                    Text("السماكة")
                    Spacer()
                    Text("\(centimetersText(currentItem.thicknessCentimeters)) سم")
                        .font(.headline)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 8) {
                Text(currentItem.source.arabicTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let confidence = currentItem.matchConfidence {
                    Text("تطابق \(Int((confidence * 100).rounded()))٪")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let separation = currentItem.faceSeparationCentimeters {
                    Text("فاصل \(centimetersText(separation)) سم")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var currentItem: RoomWallDisplayItem {
        model.wallItems(for: item.roomIndex).first(where: { $0.id == item.id }) ?? item
    }

    private var thicknessBinding: Binding<Double> {
        Binding(
            get: { currentItem.thicknessCentimeters },
            set: { newValue in
                model.updateWallThickness(
                    buildingWallID: item.buildingWallID,
                    centimeters: newValue
                )
            }
        )
    }

    private func centimetersText(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}

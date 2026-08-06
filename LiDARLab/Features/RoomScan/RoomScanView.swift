import SwiftUI

struct RoomScanView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = RoomScanViewModel()
    @StateObject private var torch = SharedTorchController()
    @State private var showingShareSheet = false
    @State private var showingResetConfirmation = false
    @State private var showingThicknessSetup = false
    @State private var showingWallEditor = false
    @State private var showingReviewCenter = false
    @State private var shareItems: [Any] = []
    @State private var setupThicknessCentimeters = 15.0
    @State private var setupMode: RoomThicknessSetupMode = .building

    var body: some View {
        ZStack {
            RoomCaptureViewContainer(model: model)
                .ignoresSafeArea()

            if model.isPaused && !model.isRelocalizing && !model.requiresRelocalization {
                pausedCameraOverlay
            }

            if model.isRelocalizing || model.requiresRelocalization {
                relocalizationOverlay
            }

            if model.isScanning {
                activeCaptureHUD
            } else {
                VStack(spacing: 12) {
                    statusPanel
                    Spacer(minLength: 10)
                    controls
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(.black)
        .navigationTitle("مسح متعدد الغرف")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.isScanning || model.isProcessing || model.isRelocalizing)
        .toolbar(model.isScanning ? .hidden : .visible, for: .navigationBar)
        .onAppear {
            torch.refreshAvailability()
            model.handleAppBecameActive()
        }
        .onDisappear {
            torch.turnOff()
            model.suspendForNavigation()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.handleAppBecameActive()
            case .inactive, .background:
                torch.turnOff()
                model.handleAppBecameInactive()
            @unknown default:
                break
            }
        }
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
        .sheet(isPresented: $showingReviewCenter) {
            RoomScanProjectReviewView(model: model)
        }
        .onChange(of: model.pendingRoomRevision?.id) { _, revisionID in
            if revisionID != nil { showingReviewCenter = true }
        }
        .onChange(of: model.pendingRoomCorrection?.id) { _, correctionID in
            if correctionID != nil { showingReviewCenter = true }
        }
        .sheet(item: Binding(
            get: { model.recoverableProject },
            set: { value in
                if value == nil { model.dismissRecoverySuggestion() }
            }
        )) { project in
            RoomScanRecoverySheet(
                project: project,
                onRestore: { model.restoreRecoverableProject() },
                onDismiss: { model.dismissRecoverySuggestion() }
            )
            .presentationDetents([.medium, .large])
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

    /// Minimal full-screen capture interface. Project summaries, exports and
    /// review controls stay hidden until the active RoomPlan session finishes.
    private var activeCaptureHUD: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: model.isRoomRescanActive
                      ? "arrow.triangle.2.circlepath.camera"
                      : (model.isRoomCorrectionScanActive ? "plus.viewfinder" : "viewfinder"))
                    .foregroundStyle(.cyan)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activeCaptureTitle)
                        .font(.subheadline.bold())
                    Text(model.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                SharedTorchButton(controller: torch, compact: true)

                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("مسح")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

            Spacer(minLength: 0)

            VStack(spacing: 9) {
                Text(activeCaptureInstruction)
                    .font(.caption.bold())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { activeScanControls }
                    VStack(spacing: 10) { activeScanControls }
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private var activeCaptureTitle: String {
        if model.isRoomRescanActive {
            return "إعادة مسح الغرفة \(model.activeRoomNumber)"
        }
        if model.isRoomCorrectionScanActive {
            return "استكمال الغرفة \(model.activeRoomNumber)"
        }
        return "مسح الغرفة \(model.activeRoomNumber)"
    }

    private var activeCaptureInstruction: String {
        if model.isRoomRescanActive {
            return "امسح الغرفة كاملة، ثم أنهِ المسح للمقارنة مع النسخة الأصلية."
        }
        if model.isRoomCorrectionScanActive {
            return "ركّز على الجزء الناقص فقط وحافظ على ظهور جزء سبق مسحه."
        }
        return "تحرّك ببطء حول الغرفة، ولا تعبر الباب قبل تثبيت هذه الغرفة."
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
                    if model.isRoomRescanActive {
                        Label("إعادة مسح الغرفة \(model.activeRoomNumber): النسخة الأصلية لن تتغير قبل الاعتماد.", systemImage: "arrow.triangle.2.circlepath.camera")
                    } else if model.isRoomCorrectionScanActive {
                        Label("امسح الجزء الناقص فقط من الغرفة \(model.activeRoomNumber)، ثم أنهِه للمراجعة.", systemImage: "plus.viewfinder")
                    } else {
                        Label("الغرفة \(model.activeRoomNumber): لا تعبر الباب قبل إنهاء الغرفة.", systemImage: "door.left.hand.closed")
                        Label("الحائط المشترك سيأخذ نفس السماكة المسجلة للغرفة السابقة.", systemImage: "link")
                    }
                }
                .font(.caption)
                .foregroundStyle(.yellow)
            }

            if model.isRelocalizing || model.requiresRelocalization {
                VStack(alignment: .leading, spacing: 5) {
                    Label(
                        model.relocalizationMessage,
                        systemImage: model.isRelocalizing ? "location.magnifyingglass" : "exclamationmark.triangle.fill"
                    )
                    if !model.relocalizationTrackingStatus.isEmpty {
                        Label(model.relocalizationTrackingStatus, systemImage: "wave.3.right")
                    }
                }
                .font(.caption)
                .foregroundStyle(model.isRelocalizing ? .yellow : .orange)
            }

            if model.isPaused {
                VStack(alignment: .leading, spacing: 5) {
                    Label(
                        "الغرفة \(model.activeRoomNumber) متوقفة مؤقتًا، والكاميرا والتتبع متوقفان.",
                        systemImage: "pause.circle.fill"
                    )
                    Label(
                        model.hasSavedWorldMapCheckpoint
                            ? "الأجزاء المحفوظة: \(model.activeRoomFragmentCount). خريطة المكان محفوظة للاستكمال بعد إغلاق التطبيق."
                            : "الأجزاء المحفوظة: \(model.activeRoomFragmentCount). خريطة المكان غير متاحة بعد.",
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

            if model.roomCount > 0, !model.isScanning, !model.isPaused, !model.isRelocalizing, !model.requiresRelocalization {
                Button {
                    showingReviewCenter = true
                } label: {
                    Label(
                        model.pendingRoomRevision == nil && model.pendingRoomCorrection == nil
                            ? "فتح مركز المراجعة 2D و3D"
                            : "مراجعة نتيجة المسح الجديدة",
                        systemImage: model.pendingRoomRevision == nil && model.pendingRoomCorrection == nil
                            ? "square.3.layers.3d"
                            : "exclamationmark.arrow.triangle.2.circlepath"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.pendingRoomRevision == nil && model.pendingRoomCorrection == nil ? .cyan : .orange)
            }

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
        if model.isRelocalizing {
            VStack(spacing: 10) {
                Button {} label: {
                    Label("جارٍ مطابقة المكان المحفوظ…", systemImage: "location.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)

                Button(role: .cancel) {
                    model.cancelRelocalization()
                } label: {
                    Label("إيقاف محاولة المطابقة", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        } else if model.requiresRelocalization {
            VStack(spacing: 10) {
                if model.canRetryRelocalization {
                    Button {
                        model.retryRelocalization()
                    } label: {
                        Label("إعادة محاولة مطابقة المكان", systemImage: "arrow.clockwise.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                if model.isPaused && model.activeRoomFragmentCount > 0 {
                    Button {
                        model.finishPausedRoom()
                    } label: {
                        Label("اعتماد الأجزاء دون استكمال مكاني", systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if !model.isPaused && model.roomCount > 0 {
                    Button {
                        model.finishBuilding()
                    } label: {
                        Label("إنهاء المبنى بالبيانات المحفوظة", systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button(role: .destructive) {
                    model.closeRecoveredProject()
                } label: {
                    Label("إغلاق المشروع المحفوظ", systemImage: "xmark.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        } else if model.isScanning {
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

                Text(model.hasSavedWorldMapCheckpoint
                     ? "تم حفظ خريطة المكان. يمكنك إغلاق التطبيق، ثم اختيار استكمال المشروع عند العودة."
                     : "لم تُحفظ خريطة مكان موثوقة بعد؛ استكمال الجلسة الحالية هو الخيار الأكثر أمانًا.")
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

            Button {
                model.discoverRecoverableProject()
            } label: {
                Label("البحث عن مشروع غير مكتمل", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                model.openLatestCompletedProjectForReview()
            } label: {
                Label("فتح أحدث مشروع مكتمل", systemImage: "folder.badge.gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
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
        if model.isRoomCorrectionScanActive {
            Button(role: .cancel) {
                model.cancelRoomCorrectionScan()
            } label: {
                Label("إلغاء الجزء", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                model.finishCurrentRoom()
            } label: {
                Label("إنهاء الجزء للمراجعة", systemImage: "plus.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .controlSize(.large)
        } else if model.isRoomRescanActive {
            Button(role: .cancel) {
                model.cancelRoomRescan()
            } label: {
                Label("إلغاء إعادة المسح", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                model.finishCurrentRoom()
            } label: {
                Label("إنهاء للمقارنة", systemImage: "arrow.triangle.2.circlepath.camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
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

    private var relocalizationOverlay: some View {
        VStack {
            Spacer(minLength: 150)

            VStack(spacing: 12) {
                if let image = model.referenceSnapshotImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 300, maxHeight: 180)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(alignment: .bottom) {
                            Text("الصورة المرجعية لآخر موضع محفوظ")
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(8)
                        }
                } else {
                    Image(systemName: "location.viewfinder")
                        .font(.system(size: 44))
                        .foregroundStyle(.yellow)
                }

                Text(model.relocalizationMessage)
                    .font(.caption.bold())
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 310)

                if !model.relocalizationTrackingStatus.isEmpty {
                    Text(model.relocalizationTrackingStatus)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 18)

            Spacer(minLength: 220)
        }
        .allowsHitTesting(false)
    }

    private var stateIcon: String {
        if model.isRelocalizing { return "location.magnifyingglass" }
        if model.requiresRelocalization { return "exclamationmark.triangle.fill" }
        if model.isProcessing { return "gearshape.2.fill" }
        if model.isBuildingFinished { return "checkmark.seal.fill" }
        if model.isPaused { return "pause.circle.fill" }
        if model.isScanning { return "record.circle" }
        if model.roomCount > 0 { return "square.grid.2x2.fill" }
        return "building.2"
    }

    private var stateColor: Color {
        if model.isRelocalizing { return .yellow }
        if model.requiresRelocalization { return .orange }
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

struct RoomWallThicknessEditor: View {
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

private struct RoomScanRecoverySheet: View {
    let project: RecoverableRoomScanProject
    let onRestore: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: project.hasWorldMap ? "location.fill.viewfinder" : "externaldrive.badge.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundStyle(project.hasWorldMap ? .cyan : .orange)

                Text("تم العثور على مشروع مسح غير مكتمل")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 10) {
                    Label("غرف مثبتة: \(project.completedRoomCount)", systemImage: "square.grid.2x2")
                    Label("أجزاء محفوظة: \(project.totalFragmentCount)", systemImage: "square.stack.3d.up")
                    if project.activeRoomNumber > 0 {
                        Label("الغرفة الحالية: \(project.activeRoomNumber)", systemImage: "door.left.hand.closed")
                    }
                    Label(
                        project.hasWorldMap
                            ? "توجد خريطة مكان للاستكمال بعد مطابقة الكاميرا."
                            : "لا توجد خريطة مكان؛ سيفتح المشروع للمراجعة فقط.",
                        systemImage: project.hasWorldMap ? "checkmark.icloud" : "exclamationmark.icloud"
                    )
                    Label(
                        project.updatedAt.formatted(date: .abbreviated, time: .shortened),
                        systemImage: "clock"
                    )
                }
                .font(.callout)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                Button {
                    onRestore()
                    dismiss()
                } label: {
                    Label("تحميل واستكمال المشروع", systemImage: "arrow.clockwise.icloud.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    onDismiss()
                    dismiss()
                } label: {
                    Text("ليس الآن")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
            .navigationTitle("استعادة جلسة المسح")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

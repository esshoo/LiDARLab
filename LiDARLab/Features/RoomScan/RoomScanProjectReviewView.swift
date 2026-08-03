import RoomPlan
import SwiftUI
import simd

struct RoomScanProjectReviewView: View {
    @ObservedObject var model: RoomScanViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: ReviewTab = .plan2D
    @State private var selectedRoomIndex: Int?
    @State private var selectedWall: RoomWallSelection?
    @State private var showingWallEditor = false
    @State private var showingOpeningsManager = false
    @State private var showingGeometryEditor = false
    @State private var showingLevelsEditor = false
    @State private var showingRoomTransformEditor = false
    @State private var previewURL: URL?
    @State private var exportSharePayload: ProjectExportSharePayload?
    @State private var rescanConfirmationRoom: Int?
    @State private var correctionConfirmationRoom: Int?

    private enum ReviewTab: String, CaseIterable, Identifiable {
        case plan2D = "2D"
        case preview3D = "3D"
        case issues = "المشكلات"
        case rooms = "الغرف"
        case export = "تصدير"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("طريقة العرض", selection: $selectedTab) {
                    ForEach(ReviewTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if let pending = model.pendingRoomRevision {
                    pendingRevisionCard(pending)
                        .padding(.horizontal)
                }

                if let pending = model.pendingRoomCorrection {
                    pendingCorrectionCard(pending)
                        .padding(.horizontal)
                }

                Group {
                    switch selectedTab {
                    case .plan2D:
                        planView
                    case .preview3D:
                        previewView
                    case .issues:
                        issuesView
                    case .rooms:
                        roomListView
                    case .export:
                        exportView
                    }
                }
            }
            .navigationTitle("مراجعة مشروع المسح")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
            .sheet(isPresented: $showingWallEditor) {
                if let selectedRoomIndex {
                    NavigationStack {
                        RoomWallThicknessEditor(model: model, roomIndex: selectedRoomIndex)
                    }
                }
            }
            .sheet(isPresented: $showingOpeningsManager) {
                if let selectedRoomIndex {
                    NavigationStack {
                        RoomOpeningsManagerView(
                            model: model,
                            roomIndex: selectedRoomIndex,
                            initialSelection: selectedWall
                        )
                    }
                }
            }
            .sheet(isPresented: $showingGeometryEditor) {
                if let selectedWall {
                    NavigationStack {
                        RoomWallGeometryEditorView(model: model, selection: selectedWall)
                    }
                }
            }
            .sheet(isPresented: $showingLevelsEditor) {
                if let selectedRoomIndex {
                    NavigationStack {
                        RoomLevelsEditorView(model: model, roomIndex: selectedRoomIndex)
                    }
                }
            }
            .sheet(isPresented: $showingRoomTransformEditor) {
                if let selectedRoomIndex {
                    NavigationStack {
                        RoomRigidTransformEditorView(model: model, roomIndex: selectedRoomIndex)
                    }
                }
            }
            .sheet(
                item: Binding(
                    get: { previewURL.map(PreviewItem.init) },
                    set: { if $0 == nil { previewURL = nil } }
                )
            ) { item in
                ReviewQuickLookContainer(url: item.url) {
                    previewURL = nil
                }
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $exportSharePayload) { payload in
                ActivityView(items: payload.items)
            }
            .confirmationDialog(
                "إعادة مسح الغرفة؟",
                isPresented: Binding(
                    get: { rescanConfirmationRoom != nil },
                    set: { if !$0 { rescanConfirmationRoom = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let roomIndex = rescanConfirmationRoom {
                    Button("بدء إعادة مسح الغرفة \(roomIndex)") {
                        rescanConfirmationRoom = nil
                        model.beginRoomRescan(roomIndex: roomIndex)
                        dismiss()
                    }
                }
                Button("إلغاء", role: .cancel) { rescanConfirmationRoom = nil }
            } message: {
                Text("ستظل النسخة الحالية محفوظة، ولن تُستبدل إلا بعد اعتماد النتيجة الجديدة.")
            }
            .confirmationDialog(
                "إضافة جزء ناقص؟",
                isPresented: Binding(
                    get: { correctionConfirmationRoom != nil },
                    set: { if !$0 { correctionConfirmationRoom = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let roomIndex = correctionConfirmationRoom {
                    Button("مسح الجزء الناقص للغرفة \(roomIndex)") {
                        correctionConfirmationRoom = nil
                        model.beginMissingAreaScan(roomIndex: roomIndex)
                        dismiss()
                    }
                }
                Button("إلغاء", role: .cancel) { correctionConfirmationRoom = nil }
            } message: {
                Text("امسح المنطقة المفقودة فقط. ستُحفظ كطبقة مكملة ولن تستبدل الغرفة الأصلية.")
            }
            .onAppear {
                model.ensureAllRoomLevelProfiles()
                model.ensureAllRoomRigidTransforms()
                model.refreshProjectReviewIssues()
                if selectedRoomIndex == nil {
                    selectedRoomIndex = model.roomReviewSummaries.first?.roomIndex
                }
            }
            .onChange(of: selectedRoomIndex) { _, newValue in
                if selectedWall?.roomIndex != newValue {
                    selectedWall = nil
                }
            }
        }
    }

    private var planView: some View {
        VStack(spacing: 10) {
            RoomPlan2DCanvas(
                rooms: model.capturedRooms,
                corrections: model.acceptedRoomCorrections,
                wallAssignments: model.roomWallAssignments,
                manualOpenings: model.manualOpeningOverlays,
                suppressedSurfaceIdentifiers: model.suppressedSurfaceIdentifiers,
                geometryOverrides: model.wallGeometryOverrides,
                roomTransforms: model.roomRigidTransforms,
                levelProfiles: model.roomLevelProfiles,
                ceilingZones: model.ceilingZoneRecords,
                issueWallIdentifiers: model.issueWallIdentifiers,
                selectedRoomIndex: $selectedRoomIndex,
                selectedWall: $selectedWall
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.quaternary)
            }
            .padding(.horizontal)

            if let roomIndex = selectedRoomIndex,
               let summary = model.roomReviewSummaries.first(where: { $0.roomIndex == roomIndex }) {
                selectedRoomCard(summary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
    }

    private var previewView: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("نموذج المشروع التفاعلي", systemImage: "cube.transparent")
                        .font(.headline)
                    Text("يعرض سماكات الحوائط، مناسيب الأرضيات، مناطق السقف، الأجزاء المكملة، والعناصر اليدوية.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                RoomScanProject3DView(
                    rooms: model.capturedRooms,
                    mergedRooms: model.capturedStructure?.rooms ?? [],
                    corrections: model.acceptedRoomCorrections,
                    wallAssignments: model.roomWallAssignments,
                    wallRecords: model.buildingWallRecords,
                    manualOpenings: model.manualOpeningRecords,
                    suppressedSurfaceIdentifiers: model.suppressedSurfaceIdentifiers,
                    geometryOverrides: model.wallGeometryOverrides,
                    roomTransforms: model.roomRigidTransforms,
                    levelProfiles: model.roomLevelProfiles,
                    ceilingZones: model.ceilingZoneRecords,
                    issueWallIdentifiers: model.issueWallIdentifiers
                )
                .frame(height: 380)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18).stroke(.quaternary)
                }
                .padding(.horizontal)

                Text("اسحب للدوران، قرّب بإصبعين، واضغط مرتين للتركيز.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider().padding(.horizontal)

                Label("ملف RoomPlan الأصلي عبر Apple Quick Look", systemImage: "arkit")
                    .font(.headline)

                Button {
                    previewURL = model.prepareReviewUSDZ(roomIndex: nil)
                } label: {
                    Label("عرض المبنى الأصلي ثلاثي الأبعاد", systemImage: "building.2.crop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)

                Picker(
                    "الغرفة",
                    selection: Binding(
                        get: { selectedRoomIndex ?? model.roomReviewSummaries.first?.roomIndex ?? 1 },
                        set: { selectedRoomIndex = $0 }
                    )
                ) {
                    ForEach(model.roomReviewSummaries) { room in
                        Text("الغرفة \(room.roomIndex)").tag(room.roomIndex)
                    }
                }
                .pickerStyle(.menu)

                if let selectedRoomIndex {
                    Button {
                        previewURL = model.prepareReviewUSDZ(roomIndex: selectedRoomIndex)
                    } label: {
                        Label("عرض ملف الغرفة \(selectedRoomIndex) الأصلي", systemImage: "cube")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding(.horizontal)
                }

                Text("Quick Look يعرض ملف RoomPlan الخام. التعديلات اليدوية تظهر في نموذج المشروع التفاعلي أعلاه وتظل محفوظة في طبقة مستقلة.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }

    private var issuesView: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    issueMetric(title: "مهم", value: model.criticalProjectIssueCount, color: .red)
                    issueMetric(title: "مراجعة", value: model.warningProjectIssueCount, color: .orange)
                    issueMetric(title: "معلومات", value: model.informationalProjectIssueCount, color: .blue)
                }
                .padding(.vertical, 6)

                Button {
                    model.refreshProjectReviewIssues()
                } label: {
                    Label("إعادة فحص المشروع", systemImage: "arrow.clockwise")
                }
            } header: {
                Text("الفحص الهندسي")
            } footer: {
                Text("الفحص لا يغيّر RoomPlan تلقائيًا. كل نتيجة تقودك إلى الغرفة أو الحائط لمراجعتها يدويًا.")
            }

            ForEach(ProjectReviewIssueSeverity.allCases.reversed(), id: \.self) { severity in
                let items = model.projectReviewIssues.filter { $0.severity == severity }
                if !items.isEmpty {
                    Section(severity.arabicTitle) {
                        ForEach(items) { issue in
                            Button {
                                navigate(to: issue)
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack(alignment: .top) {
                                        Image(systemName: severity.systemImage)
                                            .foregroundStyle(issueColor(severity))
                                        Text(issue.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if let roomIndex = issue.roomIndex {
                                            Text("غرفة \(roomIndex)")
                                                .font(.caption2.bold())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(issue.details)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Label(issue.suggestedAction, systemImage: "wrench.and.screwdriver")
                                        .font(.caption2)
                                        .foregroundStyle(.primary)
                                }
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if model.projectReviewIssues.isEmpty {
                ContentUnavailableView(
                    "لا توجد تعارضات ظاهرة",
                    systemImage: "checkmark.seal.fill",
                    description: Text("لم يكتشف الفحص الحالي مشكلات هندسية في البيانات المتاحة.")
                )
            }
        }
    }

    private func issueMetric(title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.title2.bold()).foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func issueColor(_ severity: ProjectReviewIssueSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .information: return .blue
        }
    }

    private func navigate(to issue: ProjectReviewIssue) {
        if let roomIndex = issue.roomIndex {
            selectedRoomIndex = roomIndex
        }
        if let roomIndex = issue.roomIndex, let wallIdentifier = issue.wallIdentifier {
            selectedWall = model.wallSelection(roomIndex: roomIndex, wallIdentifier: wallIdentifier)
        } else {
            selectedWall = nil
        }
        selectedTab = .plan2D
    }

    private var roomListView: some View {
        List {
            Section("ملخص المشروع") {
                LabeledContent("عدد الغرف", value: "\(model.roomCount)")
                LabeledContent("الحوائط الفعلية", value: "\(model.physicalWallCount)")
                LabeledContent("الحوائط المشتركة", value: "\(model.sharedPhysicalWallCount)")
                LabeledContent("إعادات المسح", value: "\(model.roomRevisionRecords.count)")
                LabeledContent("الأجزاء المكملة", value: "\(model.acceptedRoomCorrections.count)")
                LabeledContent("العناصر اليدوية", value: "\(model.manualOpeningRecords.count)")
                LabeledContent("تعارضات مهمة", value: "\(model.criticalProjectIssueCount)")
                LabeledContent("تحتاج مراجعة", value: "\(model.warningProjectIssueCount)")
            }

            Section("الغرف") {
                ForEach(model.roomReviewSummaries) { summary in
                    Button {
                        selectedRoomIndex = summary.roomIndex
                        selectedTab = .plan2D
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("الغرفة \(summary.roomIndex)", systemImage: "square.dashed.inset.filled")
                                    .font(.headline)
                                Spacer()
                                if summary.correctionCount > 0 {
                                    Text("+\(summary.correctionCount) جزء")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.purple.opacity(0.16), in: Capsule())
                                }
                            }
                            Text("\(summary.metrics.wallCount) حائط • \(summary.metrics.doorCount) باب • \(summary.metrics.windowCount) نافذة • \(summary.sharedWallCount) مشترك")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if model.isBuildingFinished {
                            Button {
                                correctionConfirmationRoom = summary.roomIndex
                            } label: {
                                Label("جزء ناقص", systemImage: "plus.viewfinder")
                            }
                            .tint(.purple)

                            Button {
                                rescanConfirmationRoom = summary.roomIndex
                            } label: {
                                Label("إعادة المسح", systemImage: "viewfinder")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }

            if !model.roomRevisionRecords.isEmpty {
                Section("سجل إعادة المسح") {
                    ForEach(model.roomRevisionRecords.sorted(by: { $0.createdAt > $1.createdAt })) { revision in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("الغرفة \(revision.roomIndex) — مراجعة \(revision.revisionNumber)")
                                    .font(.headline)
                                Text(revision.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(revision.decision.arabicTitle)
                                .font(.caption2.bold())
                        }
                    }
                }
            }

            if !model.roomCorrectionRecords.isEmpty {
                Section("سجل الأجزاء المكملة") {
                    ForEach(model.roomCorrectionRecords.sorted(by: { $0.createdAt > $1.createdAt })) { correction in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("الغرفة \(correction.roomIndex) — جزء \(correction.correctionNumber)")
                                    .font(.headline)
                                Text("\(correction.metrics.wallCount) حائط • \(correction.metrics.doorCount) باب")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(correction.decision.arabicTitle)
                                .font(.caption2.bold())
                        }
                    }
                }
            }
        }
    }

    private var exportView: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("حزمة المشروع المعدل", systemImage: "square.and.arrow.up.on.square")
                        .font(.title3.bold())
                    Text("يتم التصدير من النموذج بعد تطبيق سماكات الحوائط، التصحيحات الهندسية، الأبواب اليدوية، مناسيب الأرضيات ومناطق الأسقف. ملفات RoomPlan الأصلية لا تتغير.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        exportFormatChip("PDF", icon: "doc.richtext")
                        exportFormatChip("PNG", icon: "photo")
                        exportFormatChip("JSON", icon: "curlybraces")
                        exportFormatChip("CSV", icon: "tablecells")
                        exportFormatChip("DXF", icon: "ruler")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))

                Button {
                    model.exportReviewedProjectPackage()
                } label: {
                    HStack {
                        if model.isCreatingProjectExport {
                            ProgressView().tint(.white)
                        }
                        Label(
                            model.isCreatingProjectExport ? "جارٍ إنشاء الملفات…" : "إنشاء حزمة التصدير النهائية",
                            systemImage: "shippingbox.and.arrow.backward"
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isCreatingProjectExport || model.roomCount == 0)

                if let package = model.latestProjectExportPackage {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("تم إنشاء الحزمة", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text(package.folderURL.lastPathComponent)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)

                        exportFileRow(title: "المخطط PDF", url: package.pdfURL, icon: "doc.richtext")
                        exportFileRow(title: "صورة المخطط PNG", url: package.pngURL, icon: "photo")
                        exportFileRow(title: "نموذج المشروع JSON", url: package.jsonURL, icon: "curlybraces")
                        exportFileRow(title: "مخطط CAD بصيغة DXF", url: package.dxfURL, icon: "ruler")
                        exportFileRow(title: "جداول CSV", url: package.csvURLs.first, icon: "tablecells")

                        HStack(spacing: 10) {
                            Button {
                                previewURL = package.pdfURL
                            } label: {
                                Label("معاينة PDF", systemImage: "eye")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                exportSharePayload = ProjectExportSharePayload(items: package.shareItems)
                            } label: {
                                Label("مشاركة الكل", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(16)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("محتوى التصدير", systemImage: "info.circle")
                        .font(.headline)
                    Text("• PDF متعدد الصفحات: المخطط، ملخص الغرف والحوائط، وقائمة المشكلات.")
                    Text("• PNG عالي الدقة للمخطط ثنائي الأبعاد.")
                    Text("• JSON يحفظ النموذج المعدل والعلاقات بين الغرف والحوائط.")
                    Text("• CSV منفصل للغرف والحوائط والفتحات والأسقف والمشكلات.")
                    Text("• DXF بوحدة المتر وطبقات مستقلة لبرامج CAD.")
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            }
            .padding()
        }
    }

    private func exportFormatChip(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
    }

    private func exportFileRow(title: String, url: URL?, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            if let url {
                Button {
                    exportSharePayload = ProjectExportSharePayload(items: [url])
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
            }
        }
        .font(.subheadline)
    }

    private func selectedRoomCard(_ summary: RoomReviewSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("الغرفة \(summary.roomIndex)")
                    .font(.headline)
                Spacer()
                if let selectedWall {
                    Text("الحائط \(selectedWall.wallNumber)")
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                } else {
                    Text("اضغط على حائط لتحريره")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let profile = model.roomLevelProfile(for: summary.roomIndex) {
                HStack(spacing: 12) {
                    Label("أرضية \(Int((profile.floorElevationMeters * 100).rounded())) سم", systemImage: "arrow.up.and.down")
                    Label("سقف \(Int((profile.finishedCeilingHeightMeters * 100).rounded())) سم", systemImage: "rectangle.tophalf.inset.filled")
                    if !model.ceilingZones(for: summary.roomIndex).isEmpty {
                        Text("\(model.ceilingZones(for: summary.roomIndex).count) مناطق")
                            .foregroundStyle(.indigo)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            if let transform = model.roomRigidTransform(for: summary.roomIndex), !transform.isIdentity {
                HStack(spacing: 10) {
                    Label("X \(Int((transform.translationXMeters * 100).rounded())) سم", systemImage: "arrow.left.and.right")
                    Label("Z \(Int((transform.translationZMeters * 100).rounded())) سم", systemImage: "arrow.up.and.down")
                    Label("\(Int(transform.rotationDegrees.rounded()))°", systemImage: "rotate.right")
                    if transform.isLocked {
                        Image(systemName: "lock.fill")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.purple)
            }

            HStack(spacing: 8) {
                Button {
                    showingWallEditor = true
                } label: {
                    Label("السماكة", systemImage: "ruler")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showingGeometryEditor = true
                } label: {
                    Label("الهندسة", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(selectedWall == nil)

                Button {
                    showingOpeningsManager = true
                } label: {
                    Label("الفتحات", systemImage: "door.left.hand.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
            .font(.caption)

            HStack(spacing: 8) {
                Button {
                    showingRoomTransformEditor = true
                } label: {
                    Label("الموضع", systemImage: "move.3d")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)

                Button {
                    showingLevelsEditor = true
                } label: {
                    Label("المناسيب", systemImage: "square.3.layers.3d.down.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button {
                    correctionConfirmationRoom = summary.roomIndex
                } label: {
                    Label("جزء ناقص", systemImage: "plus.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(!model.isBuildingFinished)

                Button {
                    rescanConfirmationRoom = summary.roomIndex
                } label: {
                    Label("إعادة", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(!model.isBuildingFinished)
            }
            .font(.caption)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func pendingRevisionCard(_ pending: PendingRoomRevision) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("نتيجة جديدة للغرفة \(pending.record.roomIndex)", systemImage: "arrow.triangle.2.circlepath.camera")
                .font(.headline)

            HStack(spacing: 12) {
                comparisonColumn(title: "الحالية", metrics: pending.record.originalMetrics)
                Image(systemName: "arrow.left.and.right").foregroundStyle(.secondary)
                comparisonColumn(title: "الجديدة", metrics: pending.record.candidateMetrics)
            }

            HStack(spacing: 10) {
                Button(role: .destructive) {
                    model.rejectPendingRoomRevision()
                } label: {
                    Label("رفض الجديدة", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    model.acceptPendingRoomRevision()
                } label: {
                    Label("اعتماد الجديدة", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    private func pendingCorrectionCard(_ pending: PendingRoomCorrection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("جزء ناقص جديد للغرفة \(pending.record.roomIndex)", systemImage: "plus.viewfinder")
                .font(.headline)
            Text("\(pending.record.metrics.wallCount) حائط • \(pending.record.metrics.doorCount) باب • \(pending.record.metrics.openingCount) فتحة")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(role: .destructive) {
                    model.rejectPendingRoomCorrection()
                } label: {
                    Label("رفض الجزء", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    model.acceptPendingRoomCorrection()
                } label: {
                    Label("إضافته للمشروع", systemImage: "plus.square.on.square").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
        }
        .padding(12)
        .background(.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    private func comparisonColumn(title: String, metrics: RoomRevisionMetrics) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold())
            Text("حوائط: \(metrics.wallCount)")
            Text("أبواب: \(metrics.doorCount)")
            Text("نوافذ: \(metrics.windowCount)")
            Text("فتحات: \(metrics.openingCount)")
        }
        .font(.caption2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReviewQuickLookContainer: View {
    let url: URL
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("تم", action: onDone)
                    .fontWeight(.semibold)
                Spacer()
                Text("نموذج RoomPlan الأصلي")
                    .font(.headline)
                Spacer()
                // Balances the leading Done button so the title stays centered.
                Text("تم")
                    .fontWeight(.semibold)
                    .hidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial)

            QuickLookPreview(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.black)
    }
}

private struct PreviewItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct ProjectExportSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct RoomPlan2DCanvas: View {
    let rooms: [CapturedRoom]
    let corrections: [AcceptedRoomCorrectionLayer]
    let wallAssignments: [RoomWallAssignment]
    let manualOpenings: [ProjectOpeningOverlay]
    let suppressedSurfaceIdentifiers: Set<UUID>
    let geometryOverrides: [WallGeometryOverrideRecord]
    let roomTransforms: [RoomRigidTransformRecord]
    let levelProfiles: [RoomLevelProfileRecord]
    let ceilingZones: [CeilingZoneRecord]
    let issueWallIdentifiers: Set<UUID>
    @Binding var selectedRoomIndex: Int?
    @Binding var selectedWall: RoomWallSelection?

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var committedPan: CGSize = .zero

    private var snapshot: FloorPlanSnapshot {
        FloorPlanSnapshot(
            rooms: rooms,
            corrections: corrections,
            wallAssignments: wallAssignments,
            manualOpenings: manualOpenings,
            suppressedSurfaceIdentifiers: suppressedSurfaceIdentifiers,
            geometryOverrides: geometryOverrides,
            roomTransforms: roomTransforms,
            levelProfiles: levelProfiles,
            ceilingZones: ceilingZones
        )
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                drawGrid(context: &context, size: size)
                drawPlan(context: &context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(
                MagnificationGesture()
                    .onChanged { value in zoom = min(max(committedZoom * value, 0.45), 8) }
                    .onEnded { _ in committedZoom = zoom }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        pan = CGSize(
                            width: committedPan.width + value.translation.width,
                            height: committedPan.height + value.translation.height
                        )
                    }
                    .onEnded { _ in committedPan = pan }
            )
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    if let hit = nearestWall(to: value.location, size: proxy.size) {
                        selectedRoomIndex = hit.roomIndex
                        selectedWall = hit.selection
                    }
                }
            )
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("اسحب للتحريك • كبّر بإصبعين", systemImage: "hand.draw")
                    Label("اضغط على حائط لاختياره", systemImage: "cursorarrow.click")
                    Label("البني = أرضية RoomPlan • النيلي = منطقة سقف", systemImage: "square.3.layers.3d.down.right")
                    Label("البنفسجي = جزء مكمل • الأحمر/السماوي = يدوي", systemImage: "paintpalette")
                    Label("الحائط الأحمر المتقطع = يحتاج مراجعة", systemImage: "exclamationmark.triangle")
                }
                .font(.caption2)
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(10)
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    withAnimation {
                        zoom = 1
                        committedZoom = 1
                        pan = .zero
                        committedPan = .zero
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.down.right.magnifyingglass").padding(10)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .padding(10)
            }
        }
        .frame(minHeight: 330)
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 32
        var path = Path()
        var x: CGFloat = pan.width.truncatingRemainder(dividingBy: spacing)
        while x < size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        var y: CGFloat = pan.height.truncatingRemainder(dividingBy: spacing)
        while y < size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        context.stroke(path, with: .color(.secondary.opacity(0.10)), lineWidth: 0.5)
    }

    private func drawPlan(context: inout GraphicsContext, size: CGSize) {
        guard !snapshot.segments.isEmpty else {
            var resolvedEmpty = context.resolve(Text("لا توجد غرف مثبتة لعرضها").font(.headline))
            resolvedEmpty.shading = .color(Color.secondary)
            context.draw(resolvedEmpty, at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }

        for floor in snapshot.floorPolygons where floor.points.count >= 3 {
            var path = Path()
            path.move(to: screenPoint(for: floor.points[0], size: size))
            for point in floor.points.dropFirst() {
                path.addLine(to: screenPoint(for: point, size: size))
            }
            path.closeSubpath()
            let selected = floor.roomIndex == selectedRoomIndex
            context.fill(path, with: .color(Color.brown.opacity(selected ? 0.18 : 0.08)))
            context.stroke(
                path,
                with: .color(Color.brown.opacity(selected ? 0.55 : 0.25)),
                style: StrokeStyle(lineWidth: selected ? 1.6 : 1, dash: [5, 4])
            )
        }

        for zone in snapshot.ceilingZoneShapes {
            let corners = zone.corners.map { screenPoint(for: $0, size: size) }
            guard corners.count == 4 else { continue }
            var path = Path()
            path.move(to: corners[0])
            for point in corners.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
            context.fill(path, with: .color(Color.indigo.opacity(0.10)))
            context.stroke(
                path,
                with: .color(Color.indigo.opacity(0.75)),
                style: StrokeStyle(lineWidth: 2, dash: [6, 4])
            )
            var resolvedZone = context.resolve(Text(zone.title).font(.caption2.bold()))
            resolvedZone.shading = .color(Color.indigo)
            context.draw(resolvedZone, at: screenPoint(for: zone.center, size: size))
        }

        for segment in snapshot.segments {
            let start = screenPoint(for: segment.start, size: size)
            let end = screenPoint(for: segment.end, size: size)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)

            let selected = segment.wallIdentifier == selectedWall?.wallIdentifier
                && segment.roomIndex == selectedWall?.roomIndex
            let color: Color
            let width: CGFloat
            var stroke = StrokeStyle(lineWidth: 3, lineCap: .round)

            switch segment.kind {
            case .wall:
                if segment.source == .correction {
                    color = .purple
                    width = 3
                    stroke.dash = [7, 5]
                } else if let wallIdentifier = segment.wallIdentifier,
                          issueWallIdentifiers.contains(wallIdentifier),
                          !selected {
                    color = .red
                    width = 4
                    stroke.dash = [8, 4]
                } else {
                    color = selected ? .cyan : .primary
                    width = selected ? 6 : 3
                }
            case .door:
                color = segment.source == .manual ? .red : .orange
                width = segment.source == .manual ? 7 : 5
            case .window:
                color = segment.source == .manual ? .cyan : .blue
                width = 5
            case .opening:
                color = segment.source == .manual ? .teal : .green
                width = 5
            }
            stroke.lineWidth = width
            context.stroke(path, with: .color(color), style: stroke)
        }

        for label in snapshot.labels {
            let point = screenPoint(for: label.position, size: size)
            let selected = label.roomIndex == selectedRoomIndex
            var resolvedLabel = context.resolve(
                Text("غرفة \(label.roomIndex)\n\(label.levelText)")
                    .font(.caption.bold())
            )
            resolvedLabel.shading = .color(selected ? Color.cyan : Color.primary)
            context.draw(resolvedLabel, at: point, anchor: .center)
        }
    }

    private func nearestWall(to point: CGPoint, size: CGSize) -> (roomIndex: Int, selection: RoomWallSelection?)? {
        var best: (segment: FloorPlanSnapshot.Segment, distance: CGFloat)?
        for segment in snapshot.segments where segment.kind == .wall && segment.source == .roomPlan {
            let start = screenPoint(for: segment.start, size: size)
            let end = screenPoint(for: segment.end, size: size)
            let distance = distanceFromPoint(point, toSegmentFrom: start, to: end)
            if best == nil || distance < best!.distance {
                best = (segment, distance)
            }
        }
        guard let best, best.distance <= 30 else { return nil }
        return (best.segment.roomIndex, best.segment.selection)
    }

    private func screenPoint(for world: SIMD2<Float>, size: CGSize) -> CGPoint {
        let bounds = snapshot.bounds
        let width = max(CGFloat(bounds.maxX - bounds.minX), 0.5)
        let height = max(CGFloat(bounds.maxY - bounds.minY), 0.5)
        let baseScale = min((size.width - 50) / width, (size.height - 50) / height)
        let centerX = CGFloat(bounds.minX + bounds.maxX) / 2
        let centerY = CGFloat(bounds.minY + bounds.maxY) / 2
        return CGPoint(
            x: size.width / 2 + (CGFloat(world.x) - centerX) * baseScale * zoom + pan.width,
            y: size.height / 2 - (CGFloat(world.y) - centerY) * baseScale * zoom + pan.height
        )
    }

    private func distanceFromPoint(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.0001 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }
}

private struct FloorPlanSnapshot {
    enum SegmentKind: Equatable { case wall, door, window, opening }
    enum SegmentSource: Equatable { case roomPlan, correction, manual }

    struct Segment: Identifiable {
        let id: String
        let roomIndex: Int
        let kind: SegmentKind
        let source: SegmentSource
        let start: SIMD2<Float>
        let end: SIMD2<Float>
        let wallIdentifier: UUID?
        let buildingWallID: UUID?
        let selection: RoomWallSelection?
    }

    struct Label {
        let roomIndex: Int
        let position: SIMD2<Float>
        let levelText: String
    }

    struct FloorPolygon: Identifiable {
        let id: String
        let roomIndex: Int
        let points: [SIMD2<Float>]
    }

    struct CeilingZoneShape: Identifiable {
        let id: UUID
        let roomIndex: Int
        let title: String
        let center: SIMD2<Float>
        let corners: [SIMD2<Float>]
    }

    struct Bounds {
        var minX: Float
        var minY: Float
        var maxX: Float
        var maxY: Float
    }

    let segments: [Segment]
    let labels: [Label]
    let floorPolygons: [FloorPolygon]
    let ceilingZoneShapes: [CeilingZoneShape]
    let bounds: Bounds

    init(
        rooms: [CapturedRoom],
        corrections: [AcceptedRoomCorrectionLayer],
        wallAssignments: [RoomWallAssignment],
        manualOpenings: [ProjectOpeningOverlay],
        suppressedSurfaceIdentifiers: Set<UUID>,
        geometryOverrides: [WallGeometryOverrideRecord],
        roomTransforms: [RoomRigidTransformRecord],
        levelProfiles: [RoomLevelProfileRecord],
        ceilingZones: [CeilingZoneRecord]
    ) {
        var newSegments: [Segment] = []
        var newLabels: [Label] = []
        var newFloorPolygons: [FloorPolygon] = []
        var newCeilingZoneShapes: [CeilingZoneShape] = []
        let profileByRoom = Dictionary(uniqueKeysWithValues: levelProfiles.map { ($0.roomIndex, $0) })
        let transformByRoom = Dictionary(uniqueKeysWithValues: roomTransforms.map { ($0.roomIndex, $0) })
        var assignmentByKey: [WallKey: RoomWallAssignment] = [:]
        for assignment in wallAssignments {
            let key = WallKey(roomIndex: assignment.roomIndex, wallIdentifier: assignment.wallIdentifier)
            if assignmentByKey[key] == nil {
                assignmentByKey[key] = assignment
            }
        }
        let overrideByAssignment = Dictionary(
            uniqueKeysWithValues: geometryOverrides.map { ($0.assignmentID, $0) }
        )

        func transformed(_ point: SIMD2<Float>, roomIndex: Int) -> SIMD2<Float> {
            transformByRoom[roomIndex]?.applying(toPoint: point) ?? point
        }

        func appendRoom(_ room: CapturedRoom, roomIndex: Int, source: SegmentSource, addLabel: Bool) {
            var wallCenters: [SIMD2<Float>] = []

            func append(_ surfaces: [CapturedRoom.Surface], kind: SegmentKind) {
                for surface in surfaces where !suppressedSurfaceIdentifiers.contains(surface.identifier) {
                    let parentAssignment = surface.parentIdentifier.flatMap {
                        assignmentByKey[WallKey(roomIndex: roomIndex, wallIdentifier: $0)]
                    }
                    let assignment = kind == .wall
                        ? assignmentByKey[WallKey(roomIndex: roomIndex, wallIdentifier: surface.identifier)]
                        : nil
                    let center: SIMD2<Float>
                    let tangent: SIMD2<Float>
                    let halfWidth: Float
                    if let assignment {
                        let geometry = EffectiveWallGeometry(
                            base: assignment.geometry,
                            adjustment: overrideByAssignment[assignment.id],
                            roomTransform: transformByRoom[roomIndex]
                        )
                        center = geometry.center2D
                        tangent = geometry.tangent2D
                        halfWidth = geometry.widthMeters / 2
                    } else {
                        let transform = surface.transform
                        let rawCenter = SIMD2<Float>(transform.columns.3.x, transform.columns.3.z)
                        center = transformByRoom[roomIndex]?.applying(toPoint: rawCenter) ?? rawCenter
                        var rawTangent = SIMD2<Float>(transform.columns.0.x, transform.columns.0.z)
                        let tangentLength = simd_length(rawTangent)
                        rawTangent = tangentLength > 0.0001 ? rawTangent / tangentLength : SIMD2<Float>(1, 0)
                        tangent = transformByRoom[roomIndex]?.applying(toDirection: rawTangent) ?? rawTangent
                        halfWidth = max(surface.dimensions.x, 0.05) / 2
                    }
                    let selection = assignment.map {
                        RoomWallSelection(
                            assignmentID: $0.id,
                            roomIndex: $0.roomIndex,
                            wallNumber: $0.wallNumber,
                            wallIdentifier: $0.wallIdentifier,
                            buildingWallID: $0.buildingWallID,
                            geometry: $0.geometry
                        )
                    }
                    newSegments.append(
                        Segment(
                            id: "\(roomIndex)-\(source)-\(kind)-\(surface.identifier.uuidString)",
                            roomIndex: roomIndex,
                            kind: kind,
                            source: source,
                            start: center - tangent * halfWidth,
                            end: center + tangent * halfWidth,
                            wallIdentifier: kind == .wall ? surface.identifier : nil,
                            buildingWallID: assignment?.buildingWallID ?? parentAssignment?.buildingWallID,
                            selection: selection
                        )
                    )
                    if kind == .wall { wallCenters.append(center) }
                }
            }

            append(room.walls, kind: .wall)
            append(room.doors, kind: .door)
            append(room.windows, kind: .window)
            append(room.openings, kind: .opening)

            if addLabel, !wallCenters.isEmpty {
                let sum = wallCenters.reduce(SIMD2<Float>(repeating: 0), +)
                let profile = profileByRoom[roomIndex]
                let floorCM = Int(((profile?.floorElevationMeters ?? 0) * 100).rounded())
                let ceilingCM = Int(((profile?.finishedCeilingHeightMeters ?? 0) * 100).rounded())
                newLabels.append(
                    Label(
                        roomIndex: roomIndex,
                        position: sum / Float(wallCenters.count),
                        levelText: "أرضية \(floorCM) سم • سقف \(ceilingCM) سم"
                    )
                )
            }
        }

        for (offset, room) in rooms.enumerated() {
            let roomIndex = offset + 1
            appendRoom(room, roomIndex: roomIndex, source: .roomPlan, addLabel: true)
            if room.floors.isEmpty {
                let seed = RoomLevelGeometrySeed.make(room: room)
                let angle = Float(seed.rotationDegrees * .pi / 180)
                let axis = SIMD2<Float>(cos(angle), sin(angle))
                let normal = SIMD2<Float>(-axis.y, axis.x)
                let center = SIMD2<Float>(Float(seed.centerX), Float(seed.centerZ))
                let halfWidth = Float(seed.widthMeters / 2)
                let halfDepth = Float(seed.depthMeters / 2)
                newFloorPolygons.append(
                    FloorPolygon(
                        id: "fallback-floor-\(roomIndex)",
                        roomIndex: roomIndex,
                        points: [
                            center - axis * halfWidth - normal * halfDepth,
                            center + axis * halfWidth - normal * halfDepth,
                            center + axis * halfWidth + normal * halfDepth,
                            center - axis * halfWidth + normal * halfDepth
                        ].map { transformed($0, roomIndex: roomIndex) }
                    )
                )
            } else {
                for floor in room.floors {
                    newFloorPolygons.append(
                        FloorPolygon(
                            id: floor.identifier.uuidString,
                            roomIndex: roomIndex,
                            points: RoomLevelGeometrySeed.floorFootprint(surface: floor)
                                .map { transformed($0, roomIndex: roomIndex) }
                        )
                    )
                }
            }
        }
        for correction in corrections {
            appendRoom(correction.room, roomIndex: correction.roomIndex, source: .correction, addLabel: false)
        }
        for opening in manualOpenings {
            let kind: SegmentKind
            switch opening.kind {
            case .door: kind = .door
            case .opening: kind = .opening
            case .window: kind = .window
            }
            newSegments.append(
                Segment(
                    id: "manual-\(opening.id.uuidString)",
                    roomIndex: opening.roomIndex,
                    kind: kind,
                    source: .manual,
                    start: opening.start,
                    end: opening.end,
                    wallIdentifier: nil,
                    buildingWallID: opening.buildingWallID,
                    selection: nil
                )
            )
        }

        for zone in ceilingZones {
            let angle = Float(zone.rotationDegrees * .pi / 180)
            let axis = SIMD2<Float>(cos(angle), sin(angle))
            let normal = SIMD2<Float>(-axis.y, axis.x)
            let center = SIMD2<Float>(Float(zone.centerX), Float(zone.centerZ))
            let halfWidth = Float(zone.widthMeters / 2)
            let halfDepth = Float(zone.depthMeters / 2)
            newCeilingZoneShapes.append(
                CeilingZoneShape(
                    id: zone.id,
                    roomIndex: zone.roomIndex,
                    title: "\(zone.name.isEmpty ? zone.kind.arabicTitle : zone.name) • \(Int((zone.heightAboveFloorMeters * 100).rounded())) سم",
                    center: transformed(center, roomIndex: zone.roomIndex),
                    corners: [
                        center - axis * halfWidth - normal * halfDepth,
                        center + axis * halfWidth - normal * halfDepth,
                        center + axis * halfWidth + normal * halfDepth,
                        center - axis * halfWidth + normal * halfDepth
                    ].map { transformed($0, roomIndex: zone.roomIndex) }
                )
            )
        }

        newSegments = Self.splitWallsAroundOpenings(newSegments)
        segments = newSegments
        labels = newLabels
        floorPolygons = newFloorPolygons
        ceilingZoneShapes = newCeilingZoneShapes

        let allPoints = newSegments.flatMap { [$0.start, $0.end] }
            + newFloorPolygons.flatMap(\.points)
            + newCeilingZoneShapes.flatMap(\.corners)
        if let first = allPoints.first {
            var minX = first.x
            var maxX = first.x
            var minY = first.y
            var maxY = first.y
            for point in allPoints.dropFirst() {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            bounds = Bounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
        } else {
            bounds = Bounds(minX: -1, minY: -1, maxX: 1, maxY: 1)
        }
    }

    private static func splitWallsAroundOpenings(_ segments: [Segment]) -> [Segment] {
        let openingSegments = segments.filter {
            $0.kind != .wall && $0.buildingWallID != nil
        }
        let openingsByWall = Dictionary(grouping: openingSegments, by: { $0.buildingWallID! })
        var result = segments.filter { $0.kind != .wall }

        for wall in segments where wall.kind == .wall {
            guard wall.source == .roomPlan,
                  let buildingWallID = wall.buildingWallID,
                  let openings = openingsByWall[buildingWallID],
                  !openings.isEmpty else {
                result.append(wall)
                continue
            }
            let vector = wall.end - wall.start
            let length = simd_length(vector)
            guard length > 0.001 else { continue }
            let axis = vector / length
            var gaps: [(Float, Float)] = []
            for opening in openings {
                let a = simd_dot(opening.start - wall.start, axis)
                let b = simd_dot(opening.end - wall.start, axis)
                let lower = max(min(a, b), 0)
                let upper = min(max(a, b), length)
                if upper - lower > 0.01 { gaps.append((lower, upper)) }
            }
            gaps.sort { $0.0 < $1.0 }
            var merged: [(Float, Float)] = []
            for gap in gaps {
                if let last = merged.last, gap.0 <= last.1 + 0.01 {
                    merged[merged.count - 1] = (last.0, max(last.1, gap.1))
                } else {
                    merged.append(gap)
                }
            }
            var cursor: Float = 0
            var pieceIndex = 0
            for gap in merged {
                if gap.0 - cursor > 0.02 {
                    result.append(
                        Segment(
                            id: "\(wall.id)-piece-\(pieceIndex)",
                            roomIndex: wall.roomIndex,
                            kind: wall.kind,
                            source: wall.source,
                            start: wall.start + axis * cursor,
                            end: wall.start + axis * gap.0,
                            wallIdentifier: wall.wallIdentifier,
                            buildingWallID: wall.buildingWallID,
                            selection: wall.selection
                        )
                    )
                    pieceIndex += 1
                }
                cursor = max(cursor, gap.1)
            }
            if length - cursor > 0.02 {
                result.append(
                    Segment(
                        id: "\(wall.id)-piece-\(pieceIndex)",
                        roomIndex: wall.roomIndex,
                        kind: wall.kind,
                        source: wall.source,
                        start: wall.start + axis * cursor,
                        end: wall.end,
                        wallIdentifier: wall.wallIdentifier,
                        buildingWallID: wall.buildingWallID,
                        selection: wall.selection
                    )
                )
            }
        }
        return result
    }

    private struct WallKey: Hashable {
        let roomIndex: Int
        let wallIdentifier: UUID
    }
}

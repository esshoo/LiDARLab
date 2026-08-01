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
    @State private var previewURL: URL?
    @State private var rescanConfirmationRoom: Int?
    @State private var correctionConfirmationRoom: Int?

    private enum ReviewTab: String, CaseIterable, Identifiable {
        case plan2D = "2D"
        case preview3D = "3D"
        case issues = "المشكلات"
        case rooms = "الغرف"

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
            .sheet(
                item: Binding(
                    get: { previewURL.map(PreviewItem.init) },
                    set: { if $0 == nil { previewURL = nil } }
                )
            ) { item in
                QuickLookPreview(url: item.url)
                    .ignoresSafeArea()
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
                    Text("يعرض سماكات الحوائط، الأجزاء المكملة، العناصر اليدوية، والعناصر التي أخفيتها من نتيجة RoomPlan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                RoomScanProject3DView(
                    rooms: model.capturedRooms,
                    corrections: model.acceptedRoomCorrections,
                    wallAssignments: model.roomWallAssignments,
                    wallRecords: model.buildingWallRecords,
                    manualOpenings: model.resolvedManualOpeningRecords,
                    suppressedSurfaceIdentifiers: model.suppressedSurfaceIdentifiers,
                    geometryOverrides: model.wallGeometryOverrides,
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
                    correctionConfirmationRoom = summary.roomIndex
                } label: {
                    Label("إضافة جزء ناقص", systemImage: "plus.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(!model.isBuildingFinished)

                Button {
                    rescanConfirmationRoom = summary.roomIndex
                } label: {
                    Label("إعادة الغرفة", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(!model.isBuildingFinished)
            }
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

private struct PreviewItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct RoomPlan2DCanvas: View {
    let rooms: [CapturedRoom]
    let corrections: [AcceptedRoomCorrectionLayer]
    let wallAssignments: [RoomWallAssignment]
    let manualOpenings: [ProjectOpeningOverlay]
    let suppressedSurfaceIdentifiers: Set<UUID>
    let geometryOverrides: [WallGeometryOverrideRecord]
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
            geometryOverrides: geometryOverrides
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
            context.draw(
                Text("لا توجد غرف مثبتة لعرضها").font(.headline).foregroundStyle(.secondary),
                at: CGPoint(x: size.width / 2, y: size.height / 2)
            )
            return
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
            context.draw(
                Text("غرفة \(label.roomIndex)")
                    .font(.caption.bold())
                    .foregroundStyle(selected ? Color.cyan : Color.primary),
                at: point
            )
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
        let selection: RoomWallSelection?
    }

    struct Label {
        let roomIndex: Int
        let position: SIMD2<Float>
    }

    struct Bounds {
        var minX: Float
        var minY: Float
        var maxX: Float
        var maxY: Float
    }

    let segments: [Segment]
    let labels: [Label]
    let bounds: Bounds

    init(
        rooms: [CapturedRoom],
        corrections: [AcceptedRoomCorrectionLayer],
        wallAssignments: [RoomWallAssignment],
        manualOpenings: [ProjectOpeningOverlay],
        suppressedSurfaceIdentifiers: Set<UUID>,
        geometryOverrides: [WallGeometryOverrideRecord]
    ) {
        var newSegments: [Segment] = []
        var newLabels: [Label] = []
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

        func appendRoom(_ room: CapturedRoom, roomIndex: Int, source: SegmentSource, addLabel: Bool) {
            var wallCenters: [SIMD2<Float>] = []

            func append(_ surfaces: [CapturedRoom.Surface], kind: SegmentKind) {
                for surface in surfaces where !suppressedSurfaceIdentifiers.contains(surface.identifier) {
                    let assignment = kind == .wall
                        ? assignmentByKey[WallKey(roomIndex: roomIndex, wallIdentifier: surface.identifier)]
                        : nil
                    let center: SIMD2<Float>
                    let tangent: SIMD2<Float>
                    let halfWidth: Float
                    if let assignment {
                        let geometry = EffectiveWallGeometry(
                            base: assignment.geometry,
                            adjustment: overrideByAssignment[assignment.id]
                        )
                        center = geometry.center2D
                        tangent = geometry.tangent2D
                        halfWidth = geometry.widthMeters / 2
                    } else {
                        let transform = surface.transform
                        center = SIMD2<Float>(transform.columns.3.x, transform.columns.3.z)
                        var rawTangent = SIMD2<Float>(transform.columns.0.x, transform.columns.0.z)
                        let tangentLength = simd_length(rawTangent)
                        rawTangent = tangentLength > 0.0001 ? rawTangent / tangentLength : SIMD2<Float>(1, 0)
                        tangent = rawTangent
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
                newLabels.append(Label(roomIndex: roomIndex, position: sum / Float(wallCenters.count)))
            }
        }

        for (offset, room) in rooms.enumerated() {
            appendRoom(room, roomIndex: offset + 1, source: .roomPlan, addLabel: true)
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
                    selection: nil
                )
            )
        }

        segments = newSegments
        labels = newLabels

        if let first = newSegments.first {
            var minX = min(first.start.x, first.end.x)
            var maxX = max(first.start.x, first.end.x)
            var minY = min(first.start.y, first.end.y)
            var maxY = max(first.start.y, first.end.y)
            for segment in newSegments.dropFirst() {
                minX = min(minX, min(segment.start.x, segment.end.x))
                maxX = max(maxX, max(segment.start.x, segment.end.x))
                minY = min(minY, min(segment.start.y, segment.end.y))
                maxY = max(maxY, max(segment.start.y, segment.end.y))
            }
            bounds = Bounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
        } else {
            bounds = Bounds(minX: -1, minY: -1, maxX: 1, maxY: 1)
        }
    }

    private struct WallKey: Hashable {
        let roomIndex: Int
        let wallIdentifier: UUID
    }
}

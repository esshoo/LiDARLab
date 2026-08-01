import RoomPlan
import SwiftUI
import simd

struct RoomScanProjectReviewView: View {
  @ObservedObject var model: RoomScanViewModel

  @Environment(\.dismiss) private var dismiss
  @State private var selectedTab: ReviewTab = .plan2D
  @State private var selectedRoomIndex: Int?
  @State private var showingWallEditor = false
  @State private var previewURL: URL?
  @State private var rescanConfirmationRoom: Int?

  private enum ReviewTab: String, CaseIterable, Identifiable {
    case plan2D = "2D"
    case preview3D = "3D"
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

        Group {
          switch selectedTab {
          case .plan2D:
            planView
          case .preview3D:
            previewView
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
        Button("إلغاء", role: .cancel) {
          rescanConfirmationRoom = nil
        }
      } message: {
        Text(
          "ستظل النسخة الحالية محفوظة. لن تُستبدل إلا بعد مقارنة النتيجة الجديدة واعتمادها يدويًا.")
      }
      .onAppear {
        if selectedRoomIndex == nil {
          selectedRoomIndex = model.roomReviewSummaries.first?.roomIndex
        }
      }
    }
  }

  private var planView: some View {
    VStack(spacing: 10) {
      RoomPlan2DCanvas(
        rooms: model.capturedRooms,
        selectedRoomIndex: $selectedRoomIndex
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
        let summary = model.roomReviewSummaries.first(where: { $0.roomIndex == roomIndex })
      {
        selectedRoomCard(summary)
          .padding(.horizontal)
          .padding(.bottom, 8)
      }
    }
  }

  private var previewView: some View {
    ScrollView {
      VStack(spacing: 16) {
        Image(systemName: "cube.transparent")
          .font(.system(size: 54))
          .foregroundStyle(.cyan)
          .padding(.top, 22)

        Text("عرض Apple Quick Look")
          .font(.title3.bold())

        Text(
          "يستخدم التطبيق تصدير RoomPlan الأصلي بصيغة USDZ، ثم يفتحه في عارض Apple للتدوير والتكبير والمعاينة بالواقع المعزز."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)

        Button {
          previewURL = model.prepareReviewUSDZ(roomIndex: nil)
        } label: {
          Label("عرض المبنى ثلاثي الأبعاد", systemImage: "building.2.crop.circle")
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
            Label("عرض الغرفة \(selectedRoomIndex) فقط", systemImage: "cube")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .controlSize(.large)
          .padding(.horizontal)
        }

        Text(
          "التحرير الهندسي ليس جزءًا من Quick Look؛ لذلك تُنفذ تعديلات السماكة وإعادة المسح داخل طبقة المشروع الخاصة بالتطبيق، مع إبقاء بيانات RoomPlan الأصلية محفوظة."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding()
      }
    }
  }

  private var roomListView: some View {
    List {
      Section("ملخص المشروع") {
        LabeledContent("عدد الغرف", value: "\(model.roomCount)")
        LabeledContent("الحوائط الفعلية", value: "\(model.physicalWallCount)")
        LabeledContent("الحوائط المشتركة", value: "\(model.sharedPhysicalWallCount)")
        LabeledContent("مراجعات المسح", value: "\(model.roomRevisionRecords.count)")
      }

      Section("الغرف") {
        ForEach(model.roomReviewSummaries) { summary in
          Button {
            selectedRoomIndex = summary.roomIndex
          } label: {
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Label("الغرفة \(summary.roomIndex)", systemImage: "square.dashed.inset.filled")
                  .font(.headline)
                Spacer()
                if summary.revisionCount > 0 {
                  Text("\(summary.revisionCount) مراجعة")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                }
              }

              Text(
                "\(summary.metrics.wallCount) حائط • \(summary.metrics.doorCount) باب • \(summary.metrics.windowCount) نافذة • \(summary.sharedWallCount) مشترك"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
          }
          .buttonStyle(.plain)
          .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if model.isBuildingFinished {
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
        Section("سجل المراجعات") {
          ForEach(model.roomRevisionRecords.sorted(by: { $0.createdAt > $1.createdAt })) {
            revision in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text("الغرفة \(revision.roomIndex) — مراجعة \(revision.revisionNumber)")
                  .font(.headline)
                Spacer()
                Text(revision.decision.arabicTitle)
                  .font(.caption2.bold())
                  .foregroundStyle(
                    revision.decision == .accepted
                      ? .green : revision.decision == .rejected ? .red : .orange)
              }
              Text(revision.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
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
        Text("\(summary.metrics.wallCount) حائط")
          .font(.caption.bold())
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 8) {
        Button {
          showingWallEditor = true
        } label: {
          Label("السماكات", systemImage: "ruler")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button {
          previewURL = model.prepareReviewUSDZ(roomIndex: summary.roomIndex)
        } label: {
          Label("عرض 3D", systemImage: "cube")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button {
          rescanConfirmationRoom = summary.roomIndex
        } label: {
          Label("إعادة المسح", systemImage: "viewfinder")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(!model.isBuildingFinished)
      }
    }
    .padding(12)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private func pendingRevisionCard(_ pending: PendingRoomRevision) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(
        "نتيجة جديدة للغرفة \(pending.record.roomIndex)",
        systemImage: "arrow.triangle.2.circlepath.camera"
      )
      .font(.headline)

      HStack(spacing: 12) {
        comparisonColumn(title: "الحالية", metrics: pending.record.originalMetrics)
        Image(systemName: "arrow.left.and.right")
          .foregroundStyle(.secondary)
        comparisonColumn(title: "الجديدة", metrics: pending.record.candidateMetrics)
      }

      HStack(spacing: 10) {
        Button(role: .destructive) {
          model.rejectPendingRoomRevision()
        } label: {
          Label("رفض الجديدة", systemImage: "xmark")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button {
          model.acceptPendingRoomRevision()
        } label: {
          Label("اعتماد الجديدة", systemImage: "checkmark.seal.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(12)
    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(.orange.opacity(0.45))
    }
  }

  private func comparisonColumn(title: String, metrics: RoomRevisionMetrics) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption.bold())
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
  @Binding var selectedRoomIndex: Int?

  @State private var zoom: CGFloat = 1
  @State private var committedZoom: CGFloat = 1
  @State private var pan: CGSize = .zero
  @State private var committedPan: CGSize = .zero

  private var snapshot: FloorPlanSnapshot {
    FloorPlanSnapshot(rooms: rooms)
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
          .onChanged { value in
            zoom = min(max(committedZoom * value, 0.45), 8)
          }
          .onEnded { _ in
            committedZoom = zoom
          }
      )
      .simultaneousGesture(
        DragGesture(minimumDistance: 8)
          .onChanged { value in
            pan = CGSize(
              width: committedPan.width + value.translation.width,
              height: committedPan.height + value.translation.height
            )
          }
          .onEnded { _ in
            committedPan = pan
          }
      )
      .simultaneousGesture(
        SpatialTapGesture()
          .onEnded { value in
            selectedRoomIndex = nearestRoom(to: value.location, size: proxy.size)
          }
      )
      .overlay(alignment: .topLeading) {
        VStack(alignment: .leading, spacing: 4) {
          Label("اسحب للتحريك • كبّر بإصبعين", systemImage: "hand.draw")
          Label("اضغط على حائط لاختيار الغرفة", systemImage: "cursorarrow.click")
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
          Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
            .padding(10)
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

      let selected = segment.roomIndex == selectedRoomIndex
      let style: Color
      let width: CGFloat
      switch segment.kind {
      case .wall:
        style = selected ? .cyan : .primary
        width = selected ? 5 : 3
      case .door:
        style = .orange
        width = 5
      case .window:
        style = .blue
        width = 4
      case .opening:
        style = .green
        width = 4
      }
      context.stroke(
        path, with: .color(style), style: StrokeStyle(lineWidth: width, lineCap: .round))
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

  private func nearestRoom(to point: CGPoint, size: CGSize) -> Int? {
    var best: (room: Int, distance: CGFloat)?
    for segment in snapshot.segments where segment.kind == .wall {
      let start = screenPoint(for: segment.start, size: size)
      let end = screenPoint(for: segment.end, size: size)
      let distance = distanceFromPoint(point, toSegmentFrom: start, to: end)
      if best == nil || distance < best!.distance {
        best = (segment.roomIndex, distance)
      }
    }
    guard let best, best.distance <= 28 else { return selectedRoomIndex }
    return best.room
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

  private func distanceFromPoint(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint)
    -> CGFloat
  {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0.0001 else {
      return hypot(point.x - start.x, point.y - start.y)
    }
    let t = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
    let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
    return hypot(point.x - projection.x, point.y - projection.y)
  }
}

private struct FloorPlanSnapshot {
  enum SegmentKind: Equatable {
    case wall
    case door
    case window
    case opening
  }

  struct Segment: Identifiable {
    let id: String
    let roomIndex: Int
    let kind: SegmentKind
    let start: SIMD2<Float>
    let end: SIMD2<Float>
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

  init(rooms: [CapturedRoom]) {
    var newSegments: [Segment] = []
    var newLabels: [Label] = []

    for (offset, room) in rooms.enumerated() {
      let roomIndex = offset + 1
      var wallCenters: [SIMD2<Float>] = []

      func append(_ surfaces: [CapturedRoom.Surface], kind: SegmentKind) {
        for surface in surfaces {
          let transform = surface.transform
          let center = SIMD2<Float>(transform.columns.3.x, transform.columns.3.z)
          var tangent = SIMD2<Float>(transform.columns.0.x, transform.columns.0.z)
          let tangentLength = simd_length(tangent)
          tangent = tangentLength > 0.0001 ? tangent / tangentLength : SIMD2<Float>(1, 0)
          let halfWidth = max(surface.dimensions.x, 0.05) / 2
          let start = center - tangent * halfWidth
          let end = center + tangent * halfWidth
          newSegments.append(
            Segment(
              id: "\(roomIndex)-\(kind)-\(surface.identifier.uuidString)",
              roomIndex: roomIndex,
              kind: kind,
              start: start,
              end: end
            )
          )
          if kind == .wall {
            wallCenters.append(center)
          }
        }
      }

      append(room.walls, kind: .wall)
      append(room.doors, kind: .door)
      append(room.windows, kind: .window)
      append(room.openings, kind: .opening)

      if !wallCenters.isEmpty {
        let sum = wallCenters.reduce(SIMD2<Float>(repeating: 0), +)
        newLabels.append(Label(roomIndex: roomIndex, position: sum / Float(wallCenters.count)))
      }
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
}

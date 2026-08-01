import SwiftUI

struct RoomOpeningsManagerView: View {
    @ObservedObject var model: RoomScanViewModel
    let roomIndex: Int
    let initialSelection: RoomWallSelection?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedAssignmentID: UUID?
    @State private var editorRequest: ManualOpeningEditorRequest?

    init(
        model: RoomScanViewModel,
        roomIndex: Int,
        initialSelection: RoomWallSelection? = nil
    ) {
        self.model = model
        self.roomIndex = roomIndex
        self.initialSelection = initialSelection
        _selectedAssignmentID = State(initialValue: initialSelection?.assignmentID)
    }

    private var wallSelections: [RoomWallSelection] {
        model.wallSelections(for: roomIndex)
    }

    private var selectedWall: RoomWallSelection? {
        if let selectedAssignmentID,
           let selection = wallSelections.first(where: { $0.assignmentID == selectedAssignmentID }) {
            return selection
        }
        return initialSelection ?? wallSelections.first
    }

    var body: some View {
        List {
            Section("إضافة عنصر يدوي") {
                if wallSelections.isEmpty {
                    ContentUnavailableView(
                        "لا توجد حوائط قابلة للتحرير",
                        systemImage: "rectangle.slash",
                        description: Text("أعد مسح الغرفة أو راجع بيانات الحوائط أولًا.")
                    )
                } else {
                    Picker(
                        "الحائط",
                        selection: Binding(
                            get: { selectedWall?.assignmentID ?? wallSelections[0].assignmentID },
                            set: { selectedAssignmentID = $0 }
                        )
                    ) {
                        ForEach(wallSelections) { selection in
                            Text("الحائط \(selection.wallNumber)")
                                .tag(selection.assignmentID)
                        }
                    }

                    Button {
                        if let selectedWall {
                            editorRequest = ManualOpeningEditorRequest(
                                selection: selectedWall,
                                existing: nil
                            )
                        }
                    } label: {
                        Label("إضافة باب أو فتحة أو نافذة", systemImage: "plus.rectangle.on.rectangle")
                    }
                    .disabled(selectedWall == nil)
                }
            }

            Section("العناصر اليدوية المشتركة") {
                let records = model.manualOpenings(for: roomIndex)
                if records.isEmpty {
                    Text("لم تتم إضافة عناصر يدوية لهذه الغرفة.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(records) { record in
                        Button {
                            guard let selection = model.wallSelection(
                                roomIndex: record.sourceRoomIndex,
                                wallIdentifier: record.sourceWallIdentifier
                            ) else { return }
                            editorRequest = ManualOpeningEditorRequest(
                                selection: selection,
                                existing: record
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: record.kind.systemImage)
                                    .foregroundStyle(.cyan)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.kind.arabicTitle)
                                        .font(.headline)
                                    Text(
                                        "العرض \(centimeters(record.widthMeters)) سم • الارتفاع \(centimeters(record.heightMeters)) سم"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    if let connected = record.connectsRoomIndex {
                                        Text("يربط الغرفة \(record.sourceRoomIndex) بالغرفة \(connected)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.left")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                model.deleteManualOpening(id: record.id)
                            } label: {
                                Label("حذف", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section("نتائج RoomPlan المكتشفة") {
                let items = model.detectedOpeningItems(for: roomIndex)
                if items.isEmpty {
                    Text("لم يكتشف RoomPlan أبوابًا أو فتحات أو نوافذ في هذه الغرفة.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        Toggle(
                            isOn: Binding(
                                get: { !item.isSuppressed },
                                set: { visible in
                                    model.setDetectedSurfaceSuppressed(item, suppressed: !visible)
                                }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.kind.arabicTitle)
                                    .font(.headline)
                                Text(
                                    "\(centimeters(Double(item.widthMeters))) × \(centimeters(Double(item.heightMeters))) سم"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if let parent = item.parentWallIdentifier,
                                   let wall = model.wallSelection(roomIndex: roomIndex, wallIdentifier: parent) {
                                    Text("على الحائط \(wall.wallNumber)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Text(
                    "الإخفاء والتعديل اليدوي يؤثران في مخطط المشروع ومعاينة SceneKit، بينما يبقى ملف RoomPlan الأصلي محفوظًا دون تعديل."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("أبواب وفتحات الغرفة \(roomIndex)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("تم") { dismiss() }
            }
        }
        .sheet(item: $editorRequest) { request in
            NavigationStack {
                ManualOpeningEditorSheet(
                    model: model,
                    selection: request.selection,
                    existing: request.existing
                )
            }
        }
        .onAppear {
            if selectedAssignmentID == nil {
                selectedAssignmentID = initialSelection?.assignmentID ?? wallSelections.first?.assignmentID
            }
        }
    }

    private func centimeters(_ meters: Double) -> String {
        String(format: "%.0f", meters * 100)
    }
}

private struct ManualOpeningEditorRequest: Identifiable {
    let id = UUID()
    let selection: RoomWallSelection
    let existing: ManualOpeningRecord?
}

private struct ManualOpeningEditorSheet: View {
    @ObservedObject var model: RoomScanViewModel
    let selection: RoomWallSelection
    let existing: ManualOpeningRecord?

    @Environment(\.dismiss) private var dismiss
    @State private var kind: ManualOpeningKind
    @State private var positionPercent: Double
    @State private var widthCentimeters: Double
    @State private var heightCentimeters: Double
    @State private var sillHeightCentimeters: Double
    @State private var connectedRoomIndex: Int

    init(
        model: RoomScanViewModel,
        selection: RoomWallSelection,
        existing: ManualOpeningRecord?
    ) {
        self.model = model
        self.selection = selection
        self.existing = existing
        _kind = State(initialValue: existing?.kind ?? .door)
        _positionPercent = State(initialValue: (existing?.positionRatio ?? 0.5) * 100)
        _widthCentimeters = State(initialValue: (existing?.widthMeters ?? 0.90) * 100)
        _heightCentimeters = State(initialValue: (existing?.heightMeters ?? 2.10) * 100)
        _sillHeightCentimeters = State(initialValue: (existing?.sillHeightMeters ?? 0.90) * 100)
        _connectedRoomIndex = State(initialValue: existing?.connectsRoomIndex ?? 0)
    }

    var body: some View {
        Form {
            Section("نوع العنصر") {
                Picker("النوع", selection: $kind) {
                    ForEach(ManualOpeningKind.allCases) { item in
                        Label(item.arabicTitle, systemImage: item.systemImage)
                            .tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("الموقع على الحائط \(selection.wallNumber)") {
                Slider(value: $positionPercent, in: 0...100, step: 1)
                LabeledContent("الموضع من بداية الحائط", value: "\(Int(positionPercent))٪")
                Text("الموضع محفوظ في إحداثيات المبنى، لذلك يظهر العنصر نفسه على الحائط المشترك بين الغرف.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("الأبعاد") {
                measurementField("العرض", value: $widthCentimeters, range: 20...500)
                measurementField("الارتفاع", value: $heightCentimeters, range: 20...400)
                if kind == .window {
                    measurementField("ارتفاع جلسة النافذة", value: $sillHeightCentimeters, range: 0...300)
                }
            }

            Section("الربط بين الغرف") {
                Picker("الغرفة الأخرى", selection: $connectedRoomIndex) {
                    Text("غير محدد").tag(0)
                    ForEach(1...max(model.roomCount, 1), id: \.self) { room in
                        if room != selection.roomIndex {
                            Text("الغرفة \(room)").tag(room)
                        }
                    }
                }
                Text("عند اختيار غرفة أخرى، يُعامل الباب أو الفتحة كعنصر مشترك واحد بين الغرفتين.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(existing == nil ? "إضافة عنصر" : "تعديل العنصر")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("إلغاء") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("حفظ") {
                    model.saveManualOpening(
                        existingID: existing?.id,
                        selection: selection,
                        kind: kind,
                        positionPercent: positionPercent,
                        widthCentimeters: widthCentimeters,
                        heightCentimeters: heightCentimeters,
                        sillHeightCentimeters: kind == .window ? sillHeightCentimeters : 0,
                        connectsRoomIndex: connectedRoomIndex == 0 ? nil : connectedRoomIndex
                    )
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }

    private func measurementField(
        _ title: String,
        value: Binding<Double>,
        range _: ClosedRange<Double>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text("سم")
                .foregroundStyle(.secondary)
        }
    }
}

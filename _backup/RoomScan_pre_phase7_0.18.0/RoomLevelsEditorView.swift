import SwiftUI

struct RoomLevelsEditorView: View {
    @ObservedObject var model: RoomScanViewModel
    let roomIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var floorElevationCentimeters: Double = 0
    @State private var structuralCeilingCentimeters: Double = 270
    @State private var finishedCeilingCentimeters: Double = 270
    @State private var story: Int = 0
    @State private var zoneEditor: CeilingZoneEditorRequest?
    @State private var showResetConfirmation = false

    private var profile: RoomLevelProfileRecord? {
        model.roomLevelProfile(for: roomIndex)
    }

    private var zones: [CeilingZoneRecord] {
        model.ceilingZones(for: roomIndex)
    }

    var body: some View {
        Form {
            Section {
                Stepper("الدور أو الطابق: \(story)", value: $story, in: -10...100)
                signedMeasurementField("منسوب الأرضية", value: $floorElevationCentimeters)
                measurementField("ارتفاع السقف الإنشائي", value: $structuralCeilingCentimeters, range: 20...2_000)
                measurementField("ارتفاع التشطيب الافتراضي", value: $finishedCeilingCentimeters, range: 20...2_000)
            } header: {
                Text("مناسيب الغرفة \(roomIndex)")
            } footer: {
                Text("يستخدم التطبيق أرضيات RoomPlan كقيمة أولية عند توفرها، ثم يحفظ تصحيحاتك في طبقة مستقلة دون تغيير CapturedRoom الأصلي.")
            }

            Section {
                if zones.isEmpty {
                    ContentUnavailableView(
                        "لا توجد مناطق سقف",
                        systemImage: "rectangle.dashed",
                        description: Text("أضف منطقة جبس أو كمرة عندما يختلف الارتفاع داخل الغرفة.")
                    )
                } else {
                    ForEach(zones) { zone in
                        Button {
                            zoneEditor = CeilingZoneEditorRequest(zone: zone)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: zone.kind.systemImage)
                                    .foregroundStyle(.indigo)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(zone.name.isEmpty ? zone.kind.arabicTitle : zone.name)
                                        .font(.headline)
                                    Text("\(centimeters(zone.widthMeters)) × \(centimeters(zone.depthMeters)) سم • ارتفاع \(centimeters(zone.heightAboveFloorMeters)) سم")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.left")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                model.deleteCeilingZone(id: zone.id)
                            } label: {
                                Label("حذف", systemImage: "trash")
                            }
                        }
                    }
                }

                Button {
                    zoneEditor = CeilingZoneEditorRequest(zone: model.suggestedCeilingZone(for: roomIndex))
                } label: {
                    Label("إضافة منطقة سقف", systemImage: "plus.rectangle.on.rectangle")
                }
            } header: {
                Text("مناطق السقف المستعار والكمـرات")
            } footer: {
                Text("كل منطقة لها موضع وأبعاد وارتفاع مستقل، وتظهر في مخطط 2D وعرض SceneKit ثلاثي الأبعاد.")
            }

            Section {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("إعادة المناسيب إلى اقتراح RoomPlan", systemImage: "arrow.uturn.backward.circle")
                }
            }
        }
        .navigationTitle("الأرضية والسقف")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("إلغاء") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("حفظ") {
                    model.saveRoomLevelProfile(
                        roomIndex: roomIndex,
                        story: story,
                        floorElevationCentimeters: floorElevationCentimeters,
                        structuralCeilingCentimeters: structuralCeilingCentimeters,
                        finishedCeilingCentimeters: finishedCeilingCentimeters
                    )
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .sheet(item: $zoneEditor) { request in
            NavigationStack {
                CeilingZoneEditorView(model: model, zone: request.zone)
            }
        }
        .onAppear { reloadProfile() }
        .confirmationDialog(
            "استعادة اقتراح RoomPlan؟",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("استعادة المناسيب وحذف المناطق", role: .destructive) {
                model.resetRoomLevelProfile(roomIndex: roomIndex, deleteZones: true)
                reloadProfile()
            }
            Button("استعادة المناسيب فقط", role: .destructive) {
                model.resetRoomLevelProfile(roomIndex: roomIndex, deleteZones: false)
                reloadProfile()
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("سيعود منسوب الأرضية وارتفاع السقف إلى القيم المستنتجة من بيانات RoomPlan المحفوظة.")
        }
    }

    private func reloadProfile() {
        model.ensureRoomLevelProfile(for: roomIndex)
        guard let profile = model.roomLevelProfile(for: roomIndex) else { return }
        story = profile.story
        floorElevationCentimeters = profile.floorElevationMeters * 100
        structuralCeilingCentimeters = profile.structuralCeilingHeightMeters * 100
        finishedCeilingCentimeters = profile.finishedCeilingHeightMeters * 100
    }

    private func measurementField(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("سم", value: value, format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 105)
                .onChange(of: value.wrappedValue) { _, newValue in
                    value.wrappedValue = min(max(newValue, range.lowerBound), range.upperBound)
                }
            Text("سم").foregroundStyle(.secondary)
        }
    }

    private func signedMeasurementField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(1)))
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(width: 105)
            Text("سم").foregroundStyle(.secondary)
        }
    }

    private func centimeters(_ meters: Double) -> String {
        String(format: "%.0f", meters * 100)
    }
}

private struct CeilingZoneEditorRequest: Identifiable {
    let zone: CeilingZoneRecord
    var id: UUID { zone.id }
}

private struct CeilingZoneEditorView: View {
    @ObservedObject var model: RoomScanViewModel
    let zone: CeilingZoneRecord

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kind: CeilingZoneKind
    @State private var centerXCentimeters: Double
    @State private var centerZCentimeters: Double
    @State private var widthCentimeters: Double
    @State private var depthCentimeters: Double
    @State private var rotationDegrees: Double
    @State private var heightCentimeters: Double

    init(model: RoomScanViewModel, zone: CeilingZoneRecord) {
        self.model = model
        self.zone = zone
        _name = State(initialValue: zone.name)
        _kind = State(initialValue: zone.kind)
        _centerXCentimeters = State(initialValue: zone.centerX * 100)
        _centerZCentimeters = State(initialValue: zone.centerZ * 100)
        _widthCentimeters = State(initialValue: zone.widthMeters * 100)
        _depthCentimeters = State(initialValue: zone.depthMeters * 100)
        _rotationDegrees = State(initialValue: zone.rotationDegrees)
        _heightCentimeters = State(initialValue: zone.heightAboveFloorMeters * 100)
    }

    var body: some View {
        Form {
            Section("المنطقة") {
                TextField("اسم اختياري", text: $name)
                Picker("النوع", selection: $kind) {
                    ForEach(CeilingZoneKind.allCases) { item in
                        Label(item.arabicTitle, systemImage: item.systemImage).tag(item)
                    }
                }
            }

            Section("الأبعاد والارتفاع") {
                measurementField("العرض", value: $widthCentimeters, range: 20...5_000)
                measurementField("العمق", value: $depthCentimeters, range: 20...5_000)
                measurementField("الارتفاع فوق الأرضية", value: $heightCentimeters, range: 20...2_000)
            }

            Section {
                signedMeasurementField("المركز X", value: $centerXCentimeters)
                signedMeasurementField("المركز Z", value: $centerZCentimeters)
                HStack {
                    Text("الدوران")
                    Spacer()
                    TextField("0", value: $rotationDegrees, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("°").foregroundStyle(.secondary)
                }
            } header: {
                Text("الموقع داخل إحداثيات المشروع")
            } footer: {
                Text("القيم X وZ بالسنتيمتر داخل نظام الإحداثيات المشترك للمبنى. الاقتراح الأولي مأخوذ من أكبر أرضية اكتشفها RoomPlan للغرفة.")
            }
        }
        .navigationTitle(zone.name.isEmpty ? "منطقة سقف" : zone.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("إلغاء") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("حفظ") {
                    var updated = zone
                    updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.kind = kind
                    updated.centerX = centerXCentimeters / 100
                    updated.centerZ = centerZCentimeters / 100
                    updated.widthMeters = min(max(widthCentimeters / 100, 0.20), 50)
                    updated.depthMeters = min(max(depthCentimeters / 100, 0.20), 50)
                    updated.rotationDegrees = min(max(rotationDegrees, -180), 180)
                    updated.heightAboveFloorMeters = min(max(heightCentimeters / 100, 0.20), 20)
                    updated.updatedAt = Date()
                    model.saveCeilingZone(updated)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }

    private func measurementField(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("سم", value: value, format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 105)
                .onChange(of: value.wrappedValue) { _, newValue in
                    value.wrappedValue = min(max(newValue, range.lowerBound), range.upperBound)
                }
            Text("سم").foregroundStyle(.secondary)
        }
    }

    private func signedMeasurementField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(1)))
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(width: 105)
            Text("سم").foregroundStyle(.secondary)
        }
    }
}

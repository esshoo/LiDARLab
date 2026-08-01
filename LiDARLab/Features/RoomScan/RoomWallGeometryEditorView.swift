import SwiftUI

struct RoomWallGeometryEditorView: View {
    @ObservedObject var model: RoomScanViewModel
    let selection: RoomWallSelection

    @Environment(\.dismiss) private var dismiss
    @State private var lengthCentimeters: Double
    @State private var heightCentimeters: Double
    @State private var centerOffsetAlongCentimeters: Double
    @State private var centerOffsetNormalCentimeters: Double
    @State private var rotationDegrees: Double
    @State private var applyHorizontalToSharedWall: Bool
    @State private var applyHeightToSharedWall = false
    @State private var showResetConfirmation = false

    init(model: RoomScanViewModel, selection: RoomWallSelection) {
        self.model = model
        self.selection = selection
        _lengthCentimeters = State(initialValue: Double(selection.geometry.widthMeters) * 100)
        _heightCentimeters = State(initialValue: Double(selection.geometry.heightMeters) * 100)
        _centerOffsetAlongCentimeters = State(initialValue: 0)
        _centerOffsetNormalCentimeters = State(initialValue: 0)
        _rotationDegrees = State(initialValue: 0)
        _applyHorizontalToSharedWall = State(initialValue: false)
    }

    private var isShared: Bool {
        Set(
            model.roomWallAssignments
                .filter { $0.buildingWallID == selection.buildingWallID }
                .map(\.roomIndex)
        ).count > 1
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("الغرفة", value: "\(selection.roomIndex)")
                LabeledContent("الحائط", value: "\(selection.wallNumber)")
                LabeledContent("الحالة", value: isShared ? "حائط مشترك" : "حائط مستقل")
            } header: {
                Text("العنصر المحدد")
            } footer: {
                Text("التعديلات تُحفظ في طبقة مستقلة، ولا تغيّر CapturedRoom أو JSON الأصلي الخاص بـ RoomPlan.")
            }

            Section("الأبعاد") {
                measurementField("طول الحائط", value: $lengthCentimeters, range: 20...10_000)
                measurementField("ارتفاع وجه الحائط", value: $heightCentimeters, range: 20...2_000)
            }

            Section {
                signedMeasurementField("تحريك بطول الحائط", value: $centerOffsetAlongCentimeters)
                signedMeasurementField("تحريك عمودي على الحائط", value: $centerOffsetNormalCentimeters)
                HStack {
                    Text("الدوران")
                    Spacer()
                    TextField("0", value: $rotationDegrees, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("°").foregroundStyle(.secondary)
                }
                Button {
                    rotationDegrees = model.suggestedBuildingSnapRotationDegrees(for: selection)
                } label: {
                    Label("تثبيت على أقرب اتجاه رئيسي للمبنى", systemImage: "angle")
                }
            } header: {
                Text("الموقع والاتجاه")
            } footer: {
                Text("التحريك والدوران محسوبان نسبة إلى وجه الحائط الأصلي الذي قرأه RoomPlan.")
            }

            if isShared {
                Section("الحائط المشترك") {
                    Toggle("طبّق الطول والموقع والاتجاه على الوجه المقابل", isOn: $applyHorizontalToSharedWall)
                    Toggle("طبّق الارتفاع على الوجه المقابل أيضًا", isOn: $applyHeightToSharedWall)
                        .disabled(!applyHorizontalToSharedWall)
                    Text("اترك تطبيق الارتفاع مغلقًا عندما يكون لكل غرفة سقف مستعار بارتفاع مختلف.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("استعادة هندسة RoomPlan الأصلية", systemImage: "arrow.uturn.backward.circle")
                }
            }
        }
        .navigationTitle("تحرير هندسة الحائط")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("إلغاء") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("حفظ") {
                    model.saveWallGeometryOverride(
                        selection: selection,
                        lengthCentimeters: lengthCentimeters,
                        heightCentimeters: heightCentimeters,
                        centerOffsetAlongCentimeters: centerOffsetAlongCentimeters,
                        centerOffsetNormalCentimeters: centerOffsetNormalCentimeters,
                        rotationDegrees: rotationDegrees,
                        applyHorizontalToSharedWall: applyHorizontalToSharedWall,
                        applyHeightToSharedWall: applyHeightToSharedWall
                    )
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            if let existing = model.geometryOverride(for: selection.assignmentID) {
                lengthCentimeters = existing.widthMeters * 100
                heightCentimeters = existing.heightMeters * 100
                centerOffsetAlongCentimeters = existing.centerOffsetAlongMeters * 100
                centerOffsetNormalCentimeters = existing.centerOffsetNormalMeters * 100
                rotationDegrees = existing.rotationDegrees
            }
            applyHorizontalToSharedWall = isShared
        }
        .confirmationDialog(
            "استعادة الهندسة الأصلية؟",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("هذا الوجه فقط", role: .destructive) {
                model.resetWallGeometryOverride(selection: selection, includeSharedFaces: false)
                dismiss()
            }
            if isShared {
                Button("كل أوجه الحائط المشترك", role: .destructive) {
                    model.resetWallGeometryOverride(selection: selection, includeSharedFaces: true)
                    dismiss()
                }
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("سيتم حذف التصحيح اليدوي والعودة إلى موضع وأبعاد RoomPlan المحفوظة.")
        }
    }

    private func measurementField(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("سم", value: value, format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
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
                .frame(width: 100)
            Text("سم").foregroundStyle(.secondary)
        }
    }
}

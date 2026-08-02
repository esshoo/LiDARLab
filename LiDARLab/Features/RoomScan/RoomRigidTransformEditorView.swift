import SwiftUI

struct RoomRigidTransformEditorView: View {
    @ObservedObject var model: RoomScanViewModel
    let roomIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var translationXCentimeters = 0.0
    @State private var translationZCentimeters = 0.0
    @State private var rotationDegrees = 0.0
    @State private var isLocked = false
    @State private var alignmentSuggestion: RoomAlignmentSuggestion?

    var body: some View {
        Form {
            Section("تحريك الغرفة ككتلة واحدة") {
                numericField("الإزاحة يمين/يسار", value: $translationXCentimeters, suffix: "سم")
                numericField("الإزاحة أمام/خلف", value: $translationZCentimeters, suffix: "سم")
                numericField("الدوران الأفقي", value: $rotationDegrees, suffix: "°")

                Toggle("قفل موضع الغرفة", isOn: $isLocked)
                Text("التعديل يحرك الحوائط والأرضية والسقف والأبواب والأجزاء المكملة معًا، ولا يغيّر ملفات RoomPlan الأصلية.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("أدوات المحاذاة") {
                Button {
                    rotationDegrees = (rotationDegrees / 90).rounded() * 90
                } label: {
                    Label("تثبيت الدوران على أقرب 90°", systemImage: "rotate.right")
                }
                .disabled(isLocked)

                Button {
                    alignmentSuggestion = model.suggestedRoomAlignment(roomIndex: roomIndex)
                    if let suggestion = alignmentSuggestion {
                        translationXCentimeters = suggestion.translationXCentimeters
                        translationZCentimeters = suggestion.translationZCentimeters
                        rotationDegrees = suggestion.rotationDegrees
                    }
                } label: {
                    Label("محاذاة بأقوى حائط مشترك", systemImage: "square.on.square.intersection.dashed")
                }
                .disabled(isLocked)

                if let suggestion = alignmentSuggestion {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("اقتراح الربط مع الغرفة \(suggestion.targetRoomIndex)")
                            .font(.subheadline.bold())
                        Text("سيُستخدم الحائط المشترك \(suggestion.buildingWallID.uuidString.prefix(8)).")
                        if let confidence = suggestion.confidence {
                            Text("ثقة المطابقة: \(Int((confidence * 100).rounded()))٪")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(role: .destructive) {
                    model.resetRoomRigidTransform(roomIndex: roomIndex)
                    loadCurrentValues()
                    alignmentSuggestion = nil
                } label: {
                    Label("استعادة موضع RoomPlan الأصلي", systemImage: "arrow.uturn.backward")
                }
            }
        }
        .navigationTitle("موضع الغرفة \(roomIndex)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("إلغاء") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("حفظ") {
                    model.saveRoomRigidTransform(
                        roomIndex: roomIndex,
                        translationXCentimeters: translationXCentimeters,
                        translationZCentimeters: translationZCentimeters,
                        rotationDegrees: rotationDegrees,
                        isLocked: isLocked
                    )
                    dismiss()
                }
            }
        }
        .onAppear {
            model.ensureRoomRigidTransform(for: roomIndex)
            loadCurrentValues()
        }
    }

    private func numericField(_ title: String, value: Binding<Double>, suffix: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
                .disabled(isLocked)
            Text(suffix)
                .foregroundStyle(.secondary)
        }
    }

    private func loadCurrentValues() {
        guard let record = model.roomRigidTransform(for: roomIndex) else { return }
        translationXCentimeters = record.translationXMeters * 100
        translationZCentimeters = record.translationZMeters * 100
        rotationDegrees = record.rotationDegrees
        isLocked = record.isLocked
    }
}

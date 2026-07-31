import SwiftUI

struct ComingSoonView: View {
    let feature: LiDARFeature

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: feature.systemImage)
                    .font(.system(size: 58, weight: .medium))
                    .foregroundStyle(.orange)
                    .frame(width: 112, height: 112)
                    .background(Color.orange.opacity(0.12), in: Circle())

                VStack(spacing: 8) {
                    Text(feature.title)
                        .font(.title2.bold())
                    Text("هذه الوظيفة موجودة في خطة التطبيق وستُضاف في إصدار لاحق.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                if !feature.plannedCapabilities.isEmpty {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("المخطط لهذه الوظيفة")
                            .font(.headline)

                        ForEach(feature.plannedCapabilities, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(.orange)
                                Text(item)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(18)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                }
            }
            .padding(24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(feature.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct UnsupportedFeatureView: View {
    let feature: LiDARFeature

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 58))
                .foregroundStyle(.red)

            Text("الوظيفة غير مدعومة على هذا الجهاز")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("تحتاج \(feature.title) إلى قدرات LiDAR أو ARKit غير متاحة على الجهاز الحالي.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .navigationTitle(feature.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

struct FeatureGridCard: View {
    let feature: LiDARFeature
    let capabilities: DeviceCapabilities

    private var isSupported: Bool {
        feature.isSupported(by: capabilities)
    }

    private var status: (String, StatusPill.Kind) {
        if feature.phase == .comingSoon {
            return ("قريبًا", .comingSoon)
        }
        if !isSupported {
            return ("غير مدعوم", .unsupported)
        }
        return ("جاهز", .ready)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: feature.systemImage)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(feature.phase == .ready ? .cyan : .secondary)
                    .frame(width: 46, height: 46)
                    .background(Color.cyan.opacity(feature.phase == .ready ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 14))

                Spacer(minLength: 4)
                StatusPill(text: status.0, kind: status.1)
            }

            Text(feature.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Text(feature.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

struct FeatureListRow: View {
    let feature: LiDARFeature
    let capabilities: DeviceCapabilities

    private var status: (String, StatusPill.Kind) {
        if feature.phase == .comingSoon {
            return ("قريبًا", .comingSoon)
        }
        if !feature.isSupported(by: capabilities) {
            return ("غير مدعوم", .unsupported)
        }
        return ("جاهز", .ready)
    }

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: feature.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(feature.phase == .ready ? .cyan : .secondary)
                .frame(width: 46, height: 46)
                .background(Color.cyan.opacity(feature.phase == .ready ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(feature.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 9) {
                StatusPill(text: status.0, kind: status.1)
                Image(systemName: "chevron.left")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

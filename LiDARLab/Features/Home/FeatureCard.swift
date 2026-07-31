import SwiftUI

struct FeatureGridCard: View {
    let feature: LiDARFeature
    let capabilities: DeviceCapabilities

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 6) {
                featureIcon
                Spacer(minLength: 2)
                StatusPill(text: status.0, kind: status.1)
            }

            Text(feature.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(feature.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: dynamicTypeSize.isAccessibilitySize ? 214 : 168,
            alignment: .topLeading
        )
        .padding(13)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var featureIcon: some View {
        Image(systemName: feature.systemImage)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(feature.phase == .ready ? .cyan : .secondary)
            .frame(width: 44, height: 44)
            .background(
                Color.cyan.opacity(feature.phase == .ready ? 0.14 : 0.06),
                in: RoundedRectangle(cornerRadius: 13)
            )
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
        ViewThatFits(in: .horizontal) {
            wideLayout
            compactLayout
        }
        .padding(13)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var wideLayout: some View {
        HStack(spacing: 13) {
            featureIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(feature.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            StatusPill(text: status.0, kind: status.1)
            Image(systemName: "chevron.left")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                featureIcon
                Text(feature.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                StatusPill(text: status.0, kind: status.1)
            }

            HStack(alignment: .bottom, spacing: 8) {
                Text(feature.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: "chevron.left")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var featureIcon: some View {
        Image(systemName: feature.systemImage)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(feature.phase == .ready ? .cyan : .secondary)
            .frame(width: 44, height: 44)
            .background(
                Color.cyan.opacity(feature.phase == .ready ? 0.14 : 0.06),
                in: RoundedRectangle(cornerRadius: 13)
            )
    }
}

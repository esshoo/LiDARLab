import SwiftUI

struct HomeView: View {
    private enum LayoutMode: String {
        case grid
        case list
    }

    @AppStorage("homeLayoutMode") private var layoutModeRawValue = LayoutMode.grid.rawValue
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let capabilities = DeviceCapabilities.current

    private var layoutMode: Binding<LayoutMode> {
        Binding(
            get: { LayoutMode(rawValue: layoutModeRawValue) ?? .grid },
            set: { layoutModeRawValue = $0.rawValue }
        )
    }

    private var pagePadding: CGFloat {
        horizontalSizeClass == .regular ? 24 : 12
    }

    private var cardMinimumWidth: CGFloat {
        if dynamicTypeSize.isAccessibilitySize { return 260 }
        return horizontalSizeClass == .regular ? 210 : 138
    }

    private var cardMaximumWidth: CGFloat {
        horizontalSizeClass == .regular ? 280 : 230
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    layoutPicker
                    featureCollection
                }
                .frame(maxWidth: 1180)
                .padding(.horizontal, pagePadding)
                .padding(.bottom, 34)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("LiDAR Lab")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: LiDARFeature.self) { feature in
                FeatureRouterView(feature: feature)
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                headerIcon
                headerText
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    headerIcon
                    Text("مختبر عام لقدرات LiDAR")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                headerDetails
            }
        }
        .padding(horizontalSizeClass == .regular ? 18 : 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var headerIcon: some View {
        ZStack {
            Circle()
                .fill(capabilities.lidarAvailable ? Color.cyan.opacity(0.17) : Color.red.opacity(0.14))
                .frame(width: 58, height: 58)
            Image(systemName: capabilities.lidarAvailable ? "sensor.tag.radiowaves.forward.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(capabilities.lidarAvailable ? .cyan : .red)
        }
        .accessibilityHidden(true)
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("مختبر عام لقدرات LiDAR")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            headerDetails
        }
    }

    private var headerDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(capabilities.deviceSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(capabilities.systemDescription)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var layoutPicker: some View {
        Picker("طريقة العرض", selection: layoutMode) {
            Label("شبكة", systemImage: "square.grid.2x2").tag(LayoutMode.grid)
            Label("قائمة", systemImage: "list.bullet").tag(LayoutMode.list)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var featureCollection: some View {
        if layoutMode.wrappedValue == .grid {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: cardMinimumWidth, maximum: cardMaximumWidth),
                        spacing: horizontalSizeClass == .regular ? 16 : 10,
                        alignment: .top
                    )
                ],
                alignment: .center,
                spacing: horizontalSizeClass == .regular ? 16 : 10
            ) {
                ForEach(LiDARFeature.allCases) { feature in
                    NavigationLink(value: feature) {
                        FeatureGridCard(feature: feature, capabilities: capabilities)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            LazyVStack(spacing: 11) {
                ForEach(LiDARFeature.allCases) { feature in
                    NavigationLink(value: feature) {
                        FeatureListRow(feature: feature, capabilities: capabilities)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
    }
}

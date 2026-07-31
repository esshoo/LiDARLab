import SwiftUI

struct HomeView: View {
    private enum LayoutMode: String {
        case grid
        case list
    }

    @AppStorage("homeLayoutMode") private var layoutModeRawValue = LayoutMode.grid.rawValue
    private let capabilities = DeviceCapabilities.current

    private var layoutMode: Binding<LayoutMode> {
        Binding(
            get: { LayoutMode(rawValue: layoutModeRawValue) ?? .grid },
            set: { layoutModeRawValue = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    layoutPicker
                    featureCollection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
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
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(capabilities.lidarAvailable ? Color.cyan.opacity(0.17) : Color.red.opacity(0.14))
                    .frame(width: 64, height: 64)
                Image(systemName: capabilities.lidarAvailable ? "sensor.tag.radiowaves.forward.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(capabilities.lidarAvailable ? .cyan : .red)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("مختبر عام لقدرات LiDAR")
                    .font(.headline)
                Text(capabilities.deviceSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(capabilities.systemDescription)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var layoutPicker: some View {
        Picker("طريقة العرض", selection: layoutMode) {
            Label("شبكة", systemImage: "square.grid.2x2").tag(LayoutMode.grid)
            Label("قائمة", systemImage: "list.bullet").tag(LayoutMode.list)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var featureCollection: some View {
        if layoutMode.wrappedValue == .grid {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)
            ], spacing: 14) {
                ForEach(LiDARFeature.allCases) { feature in
                    NavigationLink(value: feature) {
                        FeatureGridCard(feature: feature, capabilities: capabilities)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(LiDARFeature.allCases) { feature in
                    NavigationLink(value: feature) {
                        FeatureListRow(feature: feature, capabilities: capabilities)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

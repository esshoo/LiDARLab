import SwiftUI

struct AppSettingsView: View {
    var body: some View {
        TabView {
            NavigationStack {
                GeneralSettingsPlaceholderView()
            }
            .tabItem {
                Label("عام", systemImage: "gearshape")
            }

            NavigationStack {
                Color3DScanSettingsView()
            }
            .tabItem {
                Label("المسح 3D", systemImage: "viewfinder")
            }
        }
    }
}

private struct GeneralSettingsPlaceholderView: View {
    var body: some View {
        List {
            Section {
                Text("الإعدادات أصبحت مركزية. سنضيف لكل قسم تبويبه هنا عند تطويره، بدون تغيير سلوك الأقسام القديمة تلقائيًا.")
                    .foregroundStyle(.secondary)
            }

            Section("الأقسام") {
                Label("المسح ثلاثي الأبعاد الملون — متاح الآن", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("باقي الأقسام — تضاف عند تطوير كل قسم", systemImage: "clock")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("الإعدادات")
    }
}

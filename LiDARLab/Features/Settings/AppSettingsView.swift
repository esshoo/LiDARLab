import SwiftUI

struct AppSettingsView: View {
    var body: some View {
        TabView {
            NavigationStack {
                GeneralSettingsView()
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

private struct GeneralSettingsView: View {
    @AppStorage(LiveToolRuntimeSettings.keepScreenAwakeKey) private var keepScreenAwake = true

    var body: some View {
        List {
            Section("أثناء أدوات الكاميرا وLiDAR") {
                Toggle("إبقاء الشاشة مضاءة أثناء العمل", isOn: $keepScreenAwake)
                Text("يُطبق على أدوات القياس والمسح والعمق والسحابة النقطية والشبكة والمسح ثلاثي الأبعاد. عند إغلاق الأداة تعود الشاشة إلى سلوكها الطبيعي.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("تصميم شاشات المسح") {
                Label("الكاميرا هي المساحة الرئيسية", systemImage: "camera.viewfinder")
                Label("الأدوات الثانوية داخل أزرار جانبية", systemImage: "sidebar.right")
                Label("لوحة واحدة منبثقة في كل مرة", systemImage: "rectangle.on.rectangle")
                Text("الهدف هو منع تكدس البطاقات فوق الكاميرا والحفاظ على اللمس والرؤية أثناء القياس والمسح.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("الأقسام") {
                Label("القياس وأدوات AR", systemImage: "ruler")
                Label("LiDAR والعمق والشبكات", systemImage: "sensor.tag.radiowaves.forward")
                Label("المسح ثلاثي الأبعاد", systemImage: "cube.transparent")
                Label("الغرف والتسجيلات والتصدير", systemImage: "folder")
            }
        }
        .navigationTitle("الإعدادات")
    }
}

import SwiftUI

@main
struct LiDARLabApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(\.layoutDirection, .rightToLeft)
                .tint(.cyan)
        }
    }
}

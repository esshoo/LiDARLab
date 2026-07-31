import SwiftUI

@main
struct LiDARLabApp: App {
    @StateObject private var storage = LiDARLabStorage.shared
    @StateObject private var urlRouter = ThreeEURLRouter.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(storage)
                .environmentObject(urlRouter)
                .environment(\.layoutDirection, .rightToLeft)
                .tint(.cyan)
                .onOpenURL { url in
                    urlRouter.handle(url, storage: storage)
                }
        }
    }
}

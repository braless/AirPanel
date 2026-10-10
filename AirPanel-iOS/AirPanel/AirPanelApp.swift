import SwiftUI

@main
struct AirPanelApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onOpenURL { url in
                    store.handle(url: url)
                }
        }
    }
}

/// 根视图：根据登录态在「登录页」与「主界面」间切换
struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            if store.loggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(store.appearance.colorScheme)   // auto 时 nil → 跟随系统
        .animation(.easeInOut(duration: 0.25), value: store.loggedIn)
    }
}

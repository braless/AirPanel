import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        TabView(selection: $store.selectedTab) {
            NavigationStack { OverviewView() }
                .tabItem { Label("概览", systemImage: "square.grid.2x2.fill") }
                .tag(0)
            NavigationStack { DevicesView() }
                .tabItem { Label("设备", systemImage: "cpu.fill") }
                .tag(1)
            NavigationStack { RecordsView() }
                .tabItem { Label("记录", systemImage: "doc.text.fill") }
                .tag(2)
            NavigationStack { TaskHubView() }
                .tabItem { Label("任务", systemImage: "bolt.fill") }
                .tag(3)
            NavigationStack { SettingsView() }
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(4)
        }
        .tint(Theme.accent)
    }
}

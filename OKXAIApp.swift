import SwiftUI

@main
struct OKXAIApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear { store.loadConfig() }
                .fullScreenCover(isPresented: $store.showAuth) {
                    OKXAuthView()
                        .environmentObject(store)
                }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        TabView {
            AIChatView()
                .tabItem { Label("智能体", systemImage: "sparkles") }
            MarketView()
                .tabItem { Label("行情", systemImage: "chart.line.uptrend.xyaxis") }
            AccountView()
                .tabItem { Label("资产", systemImage: "wallet.bifold") }
            TradeView()
                .tabItem { Label("交易", systemImage: "arrow.left.arrow.right") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}

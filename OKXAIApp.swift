import SwiftUI

@main
struct OKXAIApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear { store.loadConfig() }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        TabView {
            MarketView()
                .tabItem { Label("行情", systemImage: "chart.line.uptrend.xyaxis") }
            AccountView()
                .tabItem { Label("资产", systemImage: "wallet.bifold") }
            TradeView()
                .tabItem { Label("交易", systemImage: "arrow.left.arrow.right") }
            AIChatView()
                .tabItem { Label("AI", systemImage: "bubble.left.and.bubble.right") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}

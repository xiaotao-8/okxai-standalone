import SwiftUI

@main
struct OKXAIApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .onAppear { store.loadConfig() }
        }
    }
}

/// 登录后才进入主界面
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
        .animation(.easeInOut, value: store.loggedIn)
        .background(Color.appBg.ignoresSafeArea())
    }
}

struct MainTabView: View {
    @EnvironmentObject var store: AppStore
    // 模拟器验证参数：-PreviewTab=N 直接打开第 N 个 tab
    @State private var tab: Int = {
        for arg in CommandLine.arguments where arg.hasPrefix("-PreviewTab=") {
            return Int(arg.dropFirst("-PreviewTab=".count)) ?? 0
        }
        return 0
    }()

    var body: some View {
        TabView(selection: $tab) {
            HomeView(tab: $tab)
                .tabItem { Label("首页", systemImage: "house") }
                .tag(0)
            MarketView(tab: $tab)
                .tabItem { Label("行情", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(1)
            TradeView()
                .tabItem { Label("交易", systemImage: "arrow.left.arrow.right") }
                .tag(2)
            AccountView()
                .tabItem { Label("资产", systemImage: "wallet.bifold") }
                .tag(3)
            AIChatView()
                .tabItem { Label("智能体", systemImage: "sparkles") }
                .tag(4)
            ProfileView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(5)
        }
        .tint(Color.accent)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
    }
}

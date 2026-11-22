import SwiftUI

@main
struct OKXAIApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

/// 登录后才进入主界面
struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack {
            Group {
                if store.loggedIn {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .animation(.easeInOut, value: store.loggedIn)

            // 全局提示条
            if !store.notice.isEmpty {
                VStack {
                    Spacer()
                    Text(store.notice)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 90)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.notice)
                .allowsHitTesting(false)
            }

            // 应用锁
            if store.locked {
                LockScreenView()
            }
        }
        .background(Color.appBg.ignoresSafeArea())
    }
}

/// Face ID 锁屏
struct LockScreenView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack {
            GradientHero()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accent)
                Text(store.appName)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.textPrimary)
                Text("应用已锁定")
                    .font(.subheadline)
                    .foregroundStyle(.textSecondary)
                Button {
                    store.unlock()
                } label: {
                    Label("使用 Face ID 解锁", systemImage: "faceid")
                        .font(.system(.body, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(PressScale())
                .padding(.horizontal, 40)
            }
        }
        .ignoresSafeArea()
    }
}

struct MainTabView: View {
    @EnvironmentObject var store: AppStore
    @State private var tab = 0

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

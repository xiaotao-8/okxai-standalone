import ActivityKit
import Foundation

// MARK: - 小组件与主 App 共享的持仓快照（走 App Group 共享容器）

/// 单个持仓快照
struct PositionSnapshot: Codable, Hashable {
    let instId: String
    let pos: String
    let upl: Double
    let avgPx: String
}

/// 账户快照：主 App 每次刷新资产后写入，小组件定时读取
struct AccountSnapshot: Codable {
    var totalEquity: Double
    var totalUpl: Double
    var positions: [PositionSnapshot]
    var updatedAt: Date

    static let suiteName = "group.com.okxai.OKXAI"
    static let key = "account_snapshot"

    static let empty = AccountSnapshot(totalEquity: 0, totalUpl: 0, positions: [], updatedAt: Date())

    static let sample = AccountSnapshot(
        totalEquity: 12580.42, totalUpl: 342.18,
        positions: [
            PositionSnapshot(instId: "BTC-USDT", pos: "0.05", upl: 210.50, avgPx: "60000"),
            PositionSnapshot(instId: "ETH-USDT", pos: "1.2", upl: 131.68, avgPx: "1700"),
        ],
        updatedAt: Date())

    static func load() -> AccountSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key),
              let snap = try? JSONDecoder().decode(AccountSnapshot.self, from: data) else { return nil }
        return snap
    }

    func save() {
        guard let defaults = UserDefaults(suiteName: Self.suiteName),
              let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

// MARK: - 实时通知栏（灵动岛 / 锁屏 Live Activity）

@available(iOS 16.2, *)
struct OKXLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var totalEquity: Double
        var totalUpl: Double
        var positionCount: Int
        var topInstId: String
        var topUpl: Double
    }
    var name: String = "OKXAI"
}

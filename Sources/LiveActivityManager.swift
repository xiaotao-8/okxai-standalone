import ActivityKit
import Foundation

/// 实时通知栏（灵动岛 / 锁屏）的启动、更新与关闭
@available(iOS 16.2, *)
enum LiveActivityManager {
    static func startOrUpdate(snapshot: AccountSnapshot) {
        let top = snapshot.positions.max(by: { abs($0.upl) < abs($1.upl) })
        let state = OKXLiveActivityAttributes.ContentState(
            totalEquity: snapshot.totalEquity,
            totalUpl: snapshot.totalUpl,
            positionCount: snapshot.positions.count,
            topInstId: top?.instId ?? "—",
            topUpl: top?.upl ?? 0)
        if let activity = Activity<OKXLiveActivityAttributes>.activities.first {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            do {
                _ = try Activity.request(
                    attributes: OKXLiveActivityAttributes(),
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil)
            } catch {
                // 用户关了实时活动或系统不允许，静默失败，不打扰用户
            }
        }
    }

    static func end() {
        for activity in Activity<OKXLiveActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}

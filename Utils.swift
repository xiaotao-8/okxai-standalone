import Foundation
import UIKit
import LocalAuthentication

// MARK: - 轻量持久化（UserDefaults + Codable）

enum Storage {
    static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func remove(_ key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - 网络错误中文化

extension Error {

    /// 把 URLSession / 系统的英文报错翻译成可操作的中文提示
    var okxFriendly: String {
        let ns = self as NSError
        guard ns.domain == NSURLErrorDomain else { return localizedDescription }
        switch ns.code {
        case NSURLErrorTimedOut:
            return "请求超时：连不上欧易服务器。请检查网络或开启代理后重试"
        case NSURLErrorNotConnectedToInternet:
            return "当前无网络连接，请检查 Wi-Fi / 蜂窝数据"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return "域名解析失败：无法解析 www.okx.com，请检查 DNS 或开启代理"
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted:
            return "TLS 连接被拒绝：网络可能存在拦截，请更换网络环境"
        case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
            return "无法连接到服务器：网络不稳定或被阻断"
        case NSURLErrorUserCancelledAuthentication, NSURLErrorUserAuthenticationRequired:
            return "需要身份验证：当前网络可能需要登录（如公共 Wi-Fi）"
        default:
            return "网络错误（\(ns.code)）：\(localizedDescription)"
        }
    }
}

// MARK: - 触觉反馈

enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notice = UINotificationFeedbackGenerator()

    static func tap() { light.impactOccurred() }
    static func select() { medium.impactOccurred() }
    static func ok() { notice.notificationOccurred(.success) }
    static func warn() { notice.notificationOccurred(.warning) }
    static func fail() { notice.notificationOccurred(.error) }
}

// MARK: - 应用锁（Face ID / 触控 ID）

enum AppLock {

    static var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    static func authenticate(reason: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let context = LAContext()
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                continuation.resume(returning: true)
                return
            }
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
                continuation.resume(returning: ok)
            }
        }
    }
}

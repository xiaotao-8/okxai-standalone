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

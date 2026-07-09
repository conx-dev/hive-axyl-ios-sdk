import Foundation
import Security

public protocol TokenStorage {
    func get(_ key: String) -> String?
    func set(_ key: String, _ value: String)
    func remove(_ key: String)
}

public final class InMemoryTokenStorage: TokenStorage {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    public init() {}

    public func get(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    public func set(_ key: String, _ value: String) {
        lock.lock()
        values[key] = value
        lock.unlock()
    }

    public func remove(_ key: String) {
        lock.lock()
        values[key] = nil
        lock.unlock()
    }
}

public final class UserDefaultsTokenStorage: TokenStorage {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func get(_ key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func set(_ key: String, _ value: String) {
        defaults.set(value, forKey: key)
    }

    public func remove(_ key: String) {
        defaults.removeObject(forKey: key)
    }
}

public final class KeychainTokenStorage: TokenStorage {
    private let service: String

    // 기본 service는 리브랜드(Hive Axyl) 전 값 유지 — 변경 시 기존 설치 기기의 Keychain 세션이 유실된다.
    public init(service: String = "com.hiveng.sdk") {
        self.service = service
    }

    public func get(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ key: String, _ value: String) {
        let data = Data(value.utf8)
        var query = baseQuery(key)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    public func remove(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

import Foundation
import Security

protocol GuestInstallationStorage {
    func get() throws -> String?
    func set(_ value: String) throws -> Bool
}

final class KeychainGuestInstallationStorage: GuestInstallationStorage {
    private let service: String

    init(service: String = "com.hiveng.sdk") {
        self.service = service
    }

    func get() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw storageError()
        }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String) throws -> Bool {
        let data = Data(value.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            throw storageError()
        }
        var query = baseQuery()
        query[kSecValueData as String] = data
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "hive-ng.device.id",
        ]
    }

    private func storageError() -> HiveAxylError {
        .code(.internal, message: "Guest installation credential storage is unavailable")
    }
}

final class GuestInstallation: @unchecked Sendable {
    private let storage: GuestInstallationStorage
    private let lock = NSLock()

    init(storage: GuestInstallationStorage) {
        self.storage = storage
    }

    func getOrCreateCredential() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        do {
            if let existing = try storage.get(), isCredential(existing) {
                return existing
            }
            var random = [UInt8](repeating: 0, count: 32)
            let status = SecRandomCopyBytes(kSecRandomDefault, random.count, &random)
            guard status == errSecSuccess else {
                throw unavailable()
            }
            let credential = "g1_" + encodeBase64Url(Data(random))
            guard try storage.set(credential), try storage.get() == credential else {
                throw unavailable()
            }
            return credential
        } catch let error as HiveAxylError {
            throw error
        } catch {
            throw unavailable()
        }
    }

    private func isCredential(_ value: String) -> Bool {
        guard value.hasPrefix("g1_"), value.utf8.count == 46 else {
            return false
        }
        let encoded = String(value.dropFirst(3))
        let standard = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/") + "="
        guard let decoded = Data(base64Encoded: standard), decoded.count == 32 else {
            return false
        }
        return encodeBase64Url(decoded) == encoded
    }

    private func encodeBase64Url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func unavailable() -> HiveAxylError {
        .code(.internal, message: "Guest login requires persistent app storage and secure randomness")
    }
}

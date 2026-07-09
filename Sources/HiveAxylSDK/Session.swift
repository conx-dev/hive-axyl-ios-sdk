import Foundation

final class Session: @unchecked Sendable {
    // 리브랜드(Hive Axyl) 전 키를 유지 — 변경 시 기존 설치 기기의 세션이 유실된다.
    enum Keys {
        static let accessToken = "hive-ng.player.token"
        static let refreshToken = "hive-ng.player.refresh"
        static let playerValidationToken = "hive-ng.player.validationToken"
        static let playerValidationTokenExpiresAt = "hive-ng.player.validationTokenExpiresAt"
        static let deviceId = "hive-ng.device.id"
    }

    let storage: TokenStorage
    var onCleared: (() -> Void)?
    var refreshFn: ((String) async throws -> Hiveng_V1_TokenPair)?

    private let lock = NSLock()
    private var refreshTask: Task<Bool, Never>?
    private var refreshError: Error?

    init(storage: TokenStorage) {
        self.storage = storage
    }

    var accessToken: String? {
        storage.get(Keys.accessToken)
    }

    var refreshToken: String? {
        storage.get(Keys.refreshToken)
    }

    var playerValidationToken: String? {
        guard let token = storage.get(Keys.playerValidationToken),
              let raw = storage.get(Keys.playerValidationTokenExpiresAt),
              let expiresAt = TimeInterval(raw) else {
            return nil
        }
        if expiresAt <= Date().timeIntervalSince1970 {
            storage.remove(Keys.playerValidationToken)
            storage.remove(Keys.playerValidationTokenExpiresAt)
            return nil
        }
        return token
    }

    func save(_ pair: Hiveng_V1_TokenPair) {
        storage.set(Keys.accessToken, pair.accessToken)
        storage.set(Keys.refreshToken, pair.refreshToken)
        if !pair.playerValidationToken.isEmpty && pair.hasPlayerValidationTokenExpiresAt {
            storage.set(Keys.playerValidationToken, pair.playerValidationToken)
            storage.set(
                Keys.playerValidationTokenExpiresAt,
                String(pair.playerValidationTokenExpiresAt.dateValue.timeIntervalSince1970)
            )
        } else {
            clearPlayerValidationToken()
        }
    }

    func save(
        accessToken: String,
        refreshToken: String,
        playerValidationToken: String,
        playerValidationTokenExpiresAt: String
    ) {
        storage.set(Keys.accessToken, accessToken)
        storage.set(Keys.refreshToken, refreshToken)
        if let expiresAt = RFC3339.parse(playerValidationTokenExpiresAt), !playerValidationToken.isEmpty {
            storage.set(Keys.playerValidationToken, playerValidationToken)
            storage.set(Keys.playerValidationTokenExpiresAt, String(expiresAt.timeIntervalSince1970))
        } else {
            clearPlayerValidationToken()
        }
    }

    func clear() {
        storage.remove(Keys.accessToken)
        storage.remove(Keys.refreshToken)
        clearPlayerValidationToken()
        onCleared?()
    }

    private func clearPlayerValidationToken() {
        storage.remove(Keys.playerValidationToken)
        storage.remove(Keys.playerValidationTokenExpiresAt)
    }

    // 동시 다발 SESSION_EXPIRED에서도 refresh는 1회만 수행 (single-flight)
    func tryRefresh() async -> Bool {
        await currentOrNewRefreshTask().value
    }

    func consumeRefreshError() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        let error = refreshError
        refreshError = nil
        return error
    }

    private func currentOrNewRefreshTask() -> Task<Bool, Never> {
        lock.lock()
        defer { lock.unlock() }
        if let running = refreshTask {
            return running
        }
        refreshError = nil
        let task = Task { [weak self] () -> Bool in
            guard let self else { return false }
            let refreshed = await self.performRefresh()
            self.lock.lock()
            self.refreshTask = nil
            self.lock.unlock()
            return refreshed
        }
        refreshTask = task
        return task
    }

    private func performRefresh() async -> Bool {
        guard let token = refreshToken, let refreshFn else {
            return false
        }
        do {
            let pair = try await refreshFn(token)
            save(pair)
            return true
        } catch {
            lock.lock()
            refreshError = error
            lock.unlock()
            // refresh 실패 = 재인증 필요 → 로그아웃 상태로 전환
            clear()
            return false
        }
    }
}

import Foundation

public final class PushAPI: @unchecked Sendable {
    private let lock = NSLock()
    private var client: ConnectClient?

    internal init() {}

    internal func bind(client: ConnectClient) {
        lock.lock()
        self.client = client
        lock.unlock()
    }

    internal func unbind() {
        lock.lock()
        client = nil
        lock.unlock()
    }

    public func registerPushTarget(
        fid: String,
        fcmToken: String = "",
        appIdentifier: String = ""
    ) async throws -> PushTarget {
        if fid.isEmpty {
            throw HiveAxylError.invalidArgument("fid is required")
        }
        var request = Hiveng_V1_RegisterPushTargetRequest()
        request.fid = fid
        request.fcmToken = fcmToken
        request.appIdentifier = appIdentifier
        request.platform = "ios"
        let response: Hiveng_V1_RegisterPushTargetResponse = try await requireClient().unary(
            "RemotePushService", "RegisterPushTarget", request
        )
        guard response.hasTarget else {
            throw HiveAxylError.transport("register push target response missing target")
        }
        return PushTarget(message: response.target)
    }

    public func deletePushTarget(fid: String) async throws {
        if fid.isEmpty {
            throw HiveAxylError.invalidArgument("fid is required")
        }
        var request = Hiveng_V1_DeletePushTargetRequest()
        request.fid = fid
        let _: Hiveng_V1_DeletePushTargetResponse = try await requireClient().unary(
            "RemotePushService", "DeletePushTarget", request
        )
    }

    private func requireClient() throws -> ConnectClient {
        lock.lock()
        defer { lock.unlock() }
        guard let client else {
            throw HiveAxylError.transport("discovery returned no endpoint for domain: remote_push")
        }
        return client
    }
}

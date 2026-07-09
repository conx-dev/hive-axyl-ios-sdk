import Foundation

// 게이트웨이 디스커버리: 도메인 키 → 베이스 URL.
enum Discovery {
    static func resolve(
        client: ConnectClient,
        clientVersion: String,
        projectId: String
    ) async throws -> [String: String] {
        var request = Hiveng_V1_ResolveEndpointsRequest()
        request.clientVersion = clientVersion
        request.projectID = projectId
        let response: Hiveng_V1_ResolveEndpointsResponse = try await client.unary(
            "DiscoveryService", "ResolveEndpoints", request, allowsSessionRefresh: false
        )
        var endpoints: [String: String] = [:]
        for entry in response.endpoints {
            endpoints[entry.domain] = entry.baseURL
        }
        return endpoints
    }
}

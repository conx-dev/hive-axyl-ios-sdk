# Hive Axyl iOS SDK

Hive Axyl iOS SDK is a Swift Package for game clients. It provides authentication, session persistence, notices, mailbox, payments, and remote push APIs over Hive Axyl platform services.

## Requirements

- iOS 14 or higher
- macOS 12 or higher for package builds
- Swift 5.9 or higher
- Xcode 15 or higher
- Swift Package Manager

StoreKit purchase helpers require iOS 15 or higher.

## Installation

### Xcode

1. Open your app project in Xcode.
2. Select **File > Add Package Dependencies**.
3. Enter the package URL:

```text
https://github.com/conx-dev/hive-axyl-ios-sdk.git
```

4. Select version `0.1.0` or a later released version.
5. Add `HiveAxylSDK` to your app target.

### Package.swift

Add the package dependency:

```swift
dependencies: [
    .package(
        url: "https://github.com/conx-dev/hive-axyl-ios-sdk.git",
        from: "0.1.0"
    )
]
```

Add the product to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "HiveAxylSDK", package: "hive-axyl-ios-sdk")
    ]
)
```

## Initialize

Create a `HiveAxyl` client and initialize it once before calling domain APIs.

```swift
import HiveAxylSDK

let hive = try HiveAxyl(
    config: HiveAxylConfig(
        projectId: "PROJECT_ID",
        apiKey: "CLIENT_API_KEY",
        clientVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    )
)

try await hive.initialize()
```

## Configuration

| Option | Required | Description |
| --- | --- | --- |
| `projectId` | Yes | Hive Axyl project ID. |
| `apiKey` | Yes | Client API key issued for the project. |
| `gatewayUrl` | No | Discovery gateway URL. Empty values fall back to the SDK default gateway. |
| `clientVersion` | No | Client version reported during discovery. |
| `language` | No | Language tag used for localized platform content. |
| `debug` | No | Enables SDK debug logging. |
| `tokenStorage` | No | Custom token storage implementation. Defaults to Keychain storage. |
| `urlSessionConfiguration` | No | Custom `URLSessionConfiguration` for networking. |

## Authentication

Fetch enabled login providers before showing login UI:

```swift
let providers = try await hive.auth.getLoginProviders()
```

Supported auth entry points:

- `hive.auth.loginAsGuest(deviceId:)`
- `hive.auth.loginWithGoogle(idToken:)`
- `hive.auth.loginWithApple(identityToken:)`
- `hive.auth.loginWithFacebook(accessToken:)`
- `hive.auth.restoreSession()`
- `hive.auth.logout()`
- `hive.auth.currentPlayer()`

OAuth tokens are obtained by your app through the platform provider SDKs. Hive Axyl SDK sends those tokens to the Hive Axyl server for validation.

## Payments

Use `hive.payment` for App Store product listing, purchase start, receipt verification, and StoreKit purchase helpers.

App Store Server API credentials must be configured in the Hive Axyl console. They are not stored in the client SDK.

## Notices, Mailbox, and Push

After `initialize()`, the same client exposes:

- `hive.notice` for active notices
- `hive.mailbox` for player mailbox operations
- `hive.push` for remote push target registration

Remote push delivery still requires your app to integrate Firebase Cloud Messaging and pass the device token to Hive Axyl.

## Error Handling

Domain errors are surfaced as `HiveAxylError`. Branch on the error case instead of parsing messages.

```swift
do {
    let player = try await hive.auth.loginAsGuest(deviceId: deviceId)
} catch HiveAxylError.banned(let reason, let until, let permanent) {
} catch HiveAxylError.maintenance(let info) {
} catch {
}
```

## Release Policy

Use a fixed SDK version in production builds. Swift Package releases are immutable Git tags, so fixes are released as new versions.

## License and Support

Use of this SDK is governed by the Hive Axyl license or service agreement for your project. For support, contact your Hive Axyl representative or support channel.

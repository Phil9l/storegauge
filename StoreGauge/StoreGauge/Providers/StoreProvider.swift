//
//  StoreProvider.swift
//  StoreGauge
//
//  Store-neutral provider definitions. Provider-specific API clients normalize
//  their data into the shared SwiftData models used by the rest of the app.
//

import Foundation

enum StorePlatform: String, Codable, CaseIterable, Identifiable, Sendable {
    case appleAppStore = "apple-app-store"
    case googlePlay = "google-play"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleAppStore: return "App Store"
        case .googlePlay: return "Google Play"
        }
    }

    var accountDisplayName: String {
        switch self {
        case .appleAppStore: return "App Store Connect"
        case .googlePlay: return "Google Play Console"
        }
    }

    /// SF Symbols are used here because this mark is rendered at 10–12 points.
    /// The app artwork remains the primary icon; this is only a store indicator.
    var symbol: String {
        switch self {
        case .appleAppStore: return "apple.logo"
        case .googlePlay: return "play.fill"
        }
    }

    var reviewReplyCharacterLimit: Int {
        switch self {
        case .appleAppStore: return 4_000
        case .googlePlay: return 350
        }
    }

    var consoleURL: URL? {
        switch self {
        case .appleAppStore:
            return URL(string: "https://appstoreconnect.apple.com")
        case .googlePlay:
            return URL(string: "https://play.google.com/console")
        }
    }

    func appConsoleURL(remoteIdentifier: String) -> URL? {
        switch self {
        case .appleAppStore:
            return URL(string: "https://appstoreconnect.apple.com/apps/\(remoteIdentifier)/appstore")
        case .googlePlay:
            // Play Console app URLs include a developer-account id that StoreGauge
            // does not have until the connector is configured, so open the console.
            return consoleURL
        }
    }
}

struct StoreCapabilities: OptionSet, Sendable {
    let rawValue: UInt16

    static let appDiscovery      = StoreCapabilities(rawValue: 1 << 0)
    static let reviews           = StoreCapabilities(rawValue: 1 << 1)
    static let reviewResponses   = StoreCapabilities(rawValue: 1 << 2)
    static let sales             = StoreCapabilities(rawValue: 1 << 3)
    static let subscriptions     = StoreCapabilities(rawValue: 1 << 4)
    static let analytics         = StoreCapabilities(rawValue: 1 << 5)
    static let releaseStatus     = StoreCapabilities(rawValue: 1 << 6)
    static let phasedReleases    = StoreCapabilities(rawValue: 1 << 7)
    static let metadata          = StoreCapabilities(rawValue: 1 << 8)
    static let betaTesting       = StoreCapabilities(rawValue: 1 << 9)
    static let builds            = StoreCapabilities(rawValue: 1 << 10)
    static let responseDeletion  = StoreCapabilities(rawValue: 1 << 11)
    static let grossSales        = StoreCapabilities(rawValue: 1 << 12)
    static let earnings          = StoreCapabilities(rawValue: 1 << 13)
    static let vitals            = StoreCapabilities(rawValue: 1 << 14)
}

struct StoreProviderDefinition: Sendable {
    let platform: StorePlatform
    let capabilities: StoreCapabilities
    let isConnectorAvailable: Bool
}

enum StoreProviderRegistry {
    static let appleAppStore = StoreProviderDefinition(
        platform: .appleAppStore,
        capabilities: [
            .appDiscovery, .reviews, .reviewResponses, .sales, .subscriptions,
            .analytics, .releaseStatus, .phasedReleases, .metadata, .betaTesting,
            .builds, .responseDeletion,
        ],
        isConnectorAvailable: true
    )

    /// API features plus optional financial exports from the account's private
    /// Google Cloud Storage report bucket.
    static let googlePlay = StoreProviderDefinition(
        platform: .googlePlay,
        capabilities: [
            .appDiscovery, .reviews, .reviewResponses, .releaseStatus,
            .analytics, .vitals, .grossSales, .earnings,
        ],
        isConnectorAvailable: true
    )

    static func definition(for platform: StorePlatform) -> StoreProviderDefinition {
        switch platform {
        case .appleAppStore: return appleAppStore
        case .googlePlay: return googlePlay
        }
    }
}

enum StoreProviderError: LocalizedError {
    case connectorUnavailable(StorePlatform)
    case unsupportedOperation(StorePlatform, String)

    var errorDescription: String? {
        switch self {
        case .connectorUnavailable(let platform):
            return "The \(platform.accountDisplayName) connector is not available yet."
        case .unsupportedOperation(let platform, let operation):
            return "\(operation) is not available for \(platform.displayName)."
        }
    }
}

typealias StoreSyncProgress = (String) -> Void

@MainActor
protocol StoreAccountSyncing: AnyObject {
    var platform: StorePlatform { get }
    func sync(account: Account, progress: @escaping StoreSyncProgress) async throws
}

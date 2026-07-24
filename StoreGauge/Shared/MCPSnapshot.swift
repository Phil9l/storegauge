//
//  MCPSnapshot.swift
//  StoreGauge
//
//  Credential-free, read-only data shared with the optional MCP helper.
//

import Foundation

nonisolated enum StoreGaugeMCPConstants {
    static let appGroupIdentifier = StoreGaugeWidgetConstants.appGroupIdentifier
    static let snapshotFileName = "mcp-snapshot.json"
    static let activityFileName = "mcp-activity.json"
    static let sessionDirectoryName = "mcp-sessions"
    static let enabledDefaultsKey = "mcpEnabled"
}

nonisolated struct MCPMetricSnapshot: Codable, Hashable, Sendable {
    /// Stable StoreGauge metric identity. Optional so helpers can read v1 snapshots.
    let id: String?
    let date: Date
    let kind: String
    let value: Double
    let currency: String?
    let source: String?
    /// Value converted into the snapshot's display currency when applicable.
    let displayValue: Double?
}

nonisolated struct MCPReviewSnapshot: Codable, Hashable, Sendable {
    let id: String
    let remoteIdentifier: String?
    let rating: Int
    let title: String?
    let body: String?
    let reviewer: String?
    let territory: String
    let language: String?
    let createdDate: Date
    let triage: String
    let hasResponse: Bool?
    let responseBody: String?
    let responseIdentifier: String?
    let responseState: String?
    let responseDate: Date?
    let isRead: Bool?
    let translatedTitle: String?
    let translatedBody: String?
    let translationSourceLanguage: String?
    let translationTargetLanguage: String?
}

nonisolated struct MCPStatusSnapshot: Codable, Hashable, Sendable {
    let id: String
    let date: Date
    let version: String?
    let fromState: String?
    let toState: String?
}

nonisolated struct MCPMetadataSnapshot: Codable, Hashable, Sendable {
    let id: String
    let locale: String
    let name: String?
    let subtitle: String?
    let description: String?
    let keywords: String?
    let promotionalText: String?
    let whatsNew: String?
    let marketingURL: String?
    let supportURL: String?
    let screenshots: String?
    let updatedAt: Date
}

nonisolated struct MCPMetadataChangeSnapshot: Codable, Hashable, Sendable {
    let id: String
    let date: Date
    let locale: String
    let field: String
    let oldValue: String?
    let newValue: String?
    let version: String?
}

nonisolated struct MCPAnnotationSnapshot: Codable, Hashable, Sendable {
    let id: String
    let date: Date
    let note: String
    let category: String
    let createdAt: Date
}

nonisolated struct MCPAppSnapshot: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let remoteIdentifier: String
    let platform: String
    let name: String
    let bundleID: String
    let accountID: String?
    let accountName: String?
    let sku: String?
    let primaryLocale: String?
    let iconURL: String?
    let firstSeenAt: Date?
    let isPinned: Bool?
    let version: String?
    let releaseState: String
    let releaseStateRaw: String?
    let releaseUpdatedAt: Date?
    let currentPlatform: String?
    let phasedReleaseState: String?
    let phasedReleaseDay: Int?
    let isSelected: Bool
    let metrics: [MCPMetricSnapshot]
    let reviews: [MCPReviewSnapshot]
    let statusHistory: [MCPStatusSnapshot]?
    let metadata: [MCPMetadataSnapshot]?
    let metadataChanges: [MCPMetadataChangeSnapshot]?
    let annotations: [MCPAnnotationSnapshot]?
}

nonisolated struct StoreGaugeMCPSnapshot: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let displayCurrency: String
    let includesReviewText: Bool
    let includesFinancialData: Bool
    let apps: [MCPAppSnapshot]
    let globalAnnotations: [MCPAnnotationSnapshot]?

    static let empty = StoreGaugeMCPSnapshot(
        schemaVersion: 1,
        generatedAt: .distantPast,
        displayCurrency: "USD",
        includesReviewText: false,
        includesFinancialData: false,
        apps: [],
        globalAnnotations: nil
    )
}

nonisolated struct StoreGaugeMCPActivity: Codable, Hashable, Sendable {
    enum State: String, Codable, Sendable {
        case connected
        case disconnected
        case error
    }

    let state: State
    let sessionID: String
    let clientName: String?
    let connectedAt: Date?
    let lastHeartbeatAt: Date
    let lastActivityAt: Date?
    let lastActivity: String?
    let requestCount: Int
    let errorMessage: String?

    var isLive: Bool {
        state == .connected && Date().timeIntervalSince(lastHeartbeatAt) < 15
    }
}

nonisolated enum StoreGaugeMCPStorage {
    static func containerURL(fileManager: FileManager = .default) -> URL? {
        if let override = ProcessInfo.processInfo.environment["STOREGAUGE_MCP_DATA_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: StoreGaugeMCPConstants.appGroupIdentifier
        )
    }

    static func snapshotURL(fileManager: FileManager = .default) -> URL? {
        containerURL(fileManager: fileManager)?
            .appendingPathComponent(StoreGaugeMCPConstants.snapshotFileName, isDirectory: false)
    }

    static func activityURL(fileManager: FileManager = .default) -> URL? {
        containerURL(fileManager: fileManager)?
            .appendingPathComponent(StoreGaugeMCPConstants.activityFileName, isDirectory: false)
    }

    static func activityDirectoryURL(fileManager: FileManager = .default) -> URL? {
        containerURL(fileManager: fileManager)?
            .appendingPathComponent(StoreGaugeMCPConstants.sessionDirectoryName, isDirectory: true)
    }

    static func loadSnapshot(fileManager: FileManager = .default) -> StoreGaugeMCPSnapshot {
        load(StoreGaugeMCPSnapshot.self, from: snapshotURL(fileManager: fileManager)) ?? .empty
    }

    static func saveSnapshot(_ snapshot: StoreGaugeMCPSnapshot,
                             fileManager: FileManager = .default) throws {
        try save(snapshot, to: snapshotURL(fileManager: fileManager), fileManager: fileManager)
    }

    static func removeSnapshot(fileManager: FileManager = .default) {
        guard let url = snapshotURL(fileManager: fileManager) else { return }
        try? fileManager.removeItem(at: url)
    }

    static func loadActivity(fileManager: FileManager = .default) -> StoreGaugeMCPActivity? {
        loadActivities(fileManager: fileManager).max { $0.lastHeartbeatAt < $1.lastHeartbeatAt }
    }

    static func loadActivities(fileManager: FileManager = .default) -> [StoreGaugeMCPActivity] {
        var activities: [StoreGaugeMCPActivity] = []
        if let directory = activityDirectoryURL(fileManager: fileManager),
           let urls = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
           ) {
            activities.append(contentsOf: urls.compactMap {
                load(StoreGaugeMCPActivity.self, from: $0)
            })
        }
        // Read the original single-session file for a smooth upgrade.
        if let legacy = load(StoreGaugeMCPActivity.self, from: activityURL(fileManager: fileManager)),
           !activities.contains(where: { $0.sessionID == legacy.sessionID }) {
            activities.append(legacy)
        }
        return activities.sorted { $0.lastHeartbeatAt > $1.lastHeartbeatAt }
    }

    static func saveActivity(_ activity: StoreGaugeMCPActivity,
                             fileManager: FileManager = .default) throws {
        let url = activityDirectoryURL(fileManager: fileManager)?
            .appendingPathComponent("\(activity.sessionID).json", isDirectory: false)
        try save(activity, to: url, fileManager: fileManager)
        pruneOldActivities(fileManager: fileManager)
    }

    private static func pruneOldActivities(fileManager: FileManager) {
        guard let directory = activityDirectoryURL(fileManager: fileManager),
              let urls = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else { return }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        for url in urls {
            guard let activity = load(StoreGaugeMCPActivity.self, from: url),
                  activity.lastHeartbeatAt < cutoff else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL?) -> T? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, to url: URL?,
                                           fileManager: FileManager) throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

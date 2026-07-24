//
//  WidgetSnapshot.swift
//  StoreGauge
//
//  Small, credential-free snapshot shared by StoreGauge and its widgets.
//

import Foundation

nonisolated enum StoreGaugeWidgetConstants {
    static let appGroupIdentifier = "group.com.bazun.storegauge"
    static let snapshotFileName = "widget-snapshot.json"
    static let performanceKind = "com.bazun.storegauge.widgets.performance"
    static let feedbackKind = "com.bazun.storegauge.widgets.feedback"
}

nonisolated struct WidgetMetricSample: Codable, Hashable, Sendable {
    let date: Date
    let value: Double
}

nonisolated struct WidgetFeedbackSnapshot: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let appID: String
    let appName: String
    let rating: Int
    let title: String
    let body: String
    let territory: String
    let createdDate: Date
}

nonisolated struct WidgetAppSnapshot: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let appStoreID: String
    /// Optional so snapshots from the Apple-only build remain decodable.
    let platformRaw: String?
    let name: String
    let isSelected: Bool
    let stateLabel: String
    let downloads: [WidgetMetricSample]
    let proceeds: [WidgetMetricSample]
    let feedback: [WidgetFeedbackSnapshot]
}

nonisolated struct StoreGaugeWidgetSnapshot: Codable, Hashable, Sendable {
    let generatedAt: Date
    let currency: String
    let apps: [WidgetAppSnapshot]

    static let empty = StoreGaugeWidgetSnapshot(
        generatedAt: .distantPast,
        currency: "USD",
        apps: []
    )
}

nonisolated enum StoreGaugeWidgetStorage {
    static func snapshotURL(fileManager: FileManager = .default) -> URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: StoreGaugeWidgetConstants.appGroupIdentifier)?
            .appendingPathComponent(StoreGaugeWidgetConstants.snapshotFileName, isDirectory: false)
    }

    static func load(fileManager: FileManager = .default) -> StoreGaugeWidgetSnapshot {
        guard let url = snapshotURL(fileManager: fileManager),
              let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(StoreGaugeWidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    static func save(_ snapshot: StoreGaugeWidgetSnapshot, fileManager: FileManager = .default) throws {
        guard let url = snapshotURL(fileManager: fileManager) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

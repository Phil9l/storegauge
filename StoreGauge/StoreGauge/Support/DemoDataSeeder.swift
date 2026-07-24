//
//  DemoDataSeeder.swift
//  StoreGauge
//
//  Creates a stable, fully local dataset for App Review and product demos.
//

import Foundation
import SwiftData

@MainActor
enum DemoDataSeeder {
    static func seed(account: Account, context: ModelContext) throws {
        guard account.isDemo else { return }
        if account.apps.isEmpty {
            let definitions = appDefinitions(for: account.platform)
            for (index, definition) in definitions.enumerated() {
                let app = TrackedApp(
                    appStoreID: definition.remoteID,
                    bundleID: definition.bundleID,
                    name: definition.name,
                    sku: "demo-\(index + 1)",
                    account: account,
                    platform: account.platform
                )
                app.currentVersionString = index == 0 ? "2.4.1" : "1.8.0"
                app.currentPlatform = account.platform == .appleAppStore ? "iOS" : "Android"
                app.currentStateRaw = definition.state.rawValue
                app.statusUpdatedAt = Date().addingTimeInterval(-3_600)
                app.isNewlyDiscovered = false
                app.reviewsBackfilled = true
                context.insert(app)
                account.apps.append(app)
                seedMetrics(for: app, index: index, platform: account.platform, context: context)
                seedReviews(for: app, index: index, context: context)
                seedStatus(for: app, platform: account.platform, context: context)
            }
        }
        account.lastSyncedAt = Date()
        account.lastSyncError = nil
        try context.save()
    }

    private struct AppDefinition {
        let remoteID: String
        let bundleID: String
        let name: String
        let state: AppStoreState
    }

    private static func appDefinitions(for platform: StorePlatform) -> [AppDefinition] {
        switch platform {
        case .appleAppStore:
            return [
                .init(remoteID: "900000001", bundleID: "com.example.focusgarden",
                      name: "Focus Garden", state: .readyForSale),
                .init(remoteID: "900000002", bundleID: "com.example.pocketweather",
                      name: "Pocket Weather", state: .waitingForReview),
            ]
        case .googlePlay:
            return [
                .init(remoteID: "com.example.focusgarden", bundleID: "com.example.focusgarden",
                      name: "Focus Garden", state: .googlePublished),
                .init(remoteID: "com.example.pocketweather", bundleID: "com.example.pocketweather",
                      name: "Pocket Weather", state: .googleInReview),
            ]
        }
    }

    private static func seedMetrics(for app: TrackedApp, index: Int,
                                    platform: StorePlatform, context: ModelContext) {
        for offset in 1...90 {
            let day = Date.daysAgo(offset).startOfDayUTC
            let wave = sin(Double(offset + index * 7) / 6.0)
            let jitter = noise(seed: offset + index * 997)
            let base = index == 0 ? 185.0 : 74.0
            let downloads = max(8, base + wave * base * 0.18 + jitter * base * 0.22)
            let updates = max(2, downloads * (0.32 + noise(seed: offset * 3 + index) * 0.12))
            let sessions = downloads * (3.8 + noise(seed: offset * 5 + index))

            switch platform {
            case .appleAppStore:
                insert(app: app, kind: .units, day: day, value: downloads + updates,
                       source: .sales, context: context)
                insert(app: app, kind: .updates, day: day, value: updates,
                       source: .sales, context: context)
                insert(app: app, kind: .proceeds, day: day, value: downloads * (index == 0 ? 0.38 : 0.21),
                       currency: "USD", source: .sales, context: context)
                insert(app: app, kind: .impressions, day: day, value: downloads * 18.5,
                       source: .analytics, context: context)
                insert(app: app, kind: .pageViews, day: day, value: downloads * 4.2,
                       source: .analytics, context: context)
                insert(app: app, kind: .sessions, day: day, value: sessions,
                       source: .analytics, context: context)
                insert(app: app, kind: .activeDevices, day: day, value: sessions * 0.62,
                       source: .analytics, context: context)
            case .googlePlay:
                insert(app: app, kind: .installs, day: day, value: downloads,
                       source: .googleStatistics, context: context)
                insert(app: app, kind: .updates, day: day, value: updates,
                       source: .googleStatistics, context: context)
                insert(app: app, kind: .grossSales, day: day, value: downloads * (index == 0 ? 0.51 : 0.29),
                       currency: "USD", source: .googleEstimatedSales, context: context)
                insert(app: app, kind: .orders, day: day, value: downloads * 0.08,
                       source: .googleEstimatedSales, context: context)
                insert(app: app, kind: .netEarnings, day: day, value: downloads * (index == 0 ? 0.34 : 0.19),
                       currency: "USD", source: .googleEarnings, context: context)
                insert(app: app, kind: .crashRate, day: day,
                       value: 0.004 + noise(seed: offset * 11 + index) * 0.003,
                       source: .googleVitals, context: context)
                insert(app: app, kind: .anrRate, day: day,
                       value: 0.001 + noise(seed: offset * 13 + index) * 0.0015,
                       source: .googleVitals, context: context)
            }
        }
    }

    private static func insert(app: TrackedApp, kind: MetricKind, day: Date, value: Double,
                               currency: String? = nil, source: MetricSource,
                               context: ModelContext) {
        context.insert(MetricPoint(
            key: MetricPoint.makeKey(app: app, kind: kind, day: day, currency: currency),
            date: day,
            kind: kind,
            value: normalized(value, kind: kind, currency: currency),
            currency: currency,
            source: source,
            app: app
        ))
    }

    private static func normalized(_ value: Double, kind: MetricKind, currency: String?) -> Double {
        if kind == .crashRate || kind == .anrRate {
            return (value * 100_000).rounded() / 100_000
        }
        if currency != nil { return (value * 100).rounded() / 100 }
        return value.rounded()
    }

    private static func seedReviews(for app: TrackedApp, index: Int, context: ModelContext) {
        let samples: [(Int, String, String, String, String, String, Int)] = [
            (5, "Exactly what I needed 🙌🏽", "Fast, clear, and thoughtfully designed. Love it 🚀", "Maya", "US", "en", 1),
            (2, "Needs a small fix", "The latest version occasionally forgets my filter selection.", "Jon", "GB", "en", 3),
            (4, "Sehr hilfreich", "Die Übersicht ist schnell und sehr übersichtlich.", "Lena", "DE", "de", 6),
            (5, "Muy buena", "La uso cada día y funciona perfectamente.", "Sofía", "ES", "es", 11),
        ]
        for (reviewIndex, sample) in samples.enumerated() {
            let review = Review(
                id: "demo-\(index)-\(reviewIndex)",
                rating: sample.0,
                title: sample.1,
                body: sample.2,
                reviewer: sample.3,
                territory: sample.4,
                reviewerLanguage: sample.5,
                createdDate: Date().addingTimeInterval(Double(-sample.6 * 86_400)),
                app: app
            )
            if reviewIndex == 2 {
                review.isAcknowledged = true
                review.isRead = true
            } else if reviewIndex == 3 {
                review.responseID = "demo-response-\(index)"
                review.responseBody = "Thank you—we’re glad you’re enjoying it!"
                review.responseState = "PUBLISHED"
                review.responseDate = Date().addingTimeInterval(-9 * 86_400)
                review.isRead = true
            }
            context.insert(review)
        }
    }

    private static func seedStatus(for app: TrackedApp, platform: StorePlatform,
                                   context: ModelContext) {
        let live = platform == .appleAppStore
            ? AppStoreState.readyForSale.rawValue
            : AppStoreState.googlePublished.rawValue
        context.insert(StatusEvent(
            date: Date().addingTimeInterval(-24 * 86_400),
            versionString: "2.4.0",
            fromStateRaw: platform == .appleAppStore
                ? AppStoreState.waitingForReview.rawValue
                : AppStoreState.googleInReview.rawValue,
            toStateRaw: live,
            app: app
        ))
    }

    private static func noise(seed: Int) -> Double {
        var value = UInt64(truncatingIfNeeded: seed)
        value = value &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(value % 10_000) / 10_000.0 - 0.5
    }
}

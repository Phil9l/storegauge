//
//  WidgetSnapshotExporter.swift
//  StoreGauge
//
//  Publishes a compact view of local data for WidgetKit. The extension never
//  receives App Store Connect credentials or direct access to SwiftData.
//

import Foundation
import SwiftData
import WidgetKit

@MainActor
enum WidgetSnapshotExporter {
    static func publish(context: ModelContext, fx: FXService, currency: String) {
        let descriptor = FetchDescriptor<TrackedApp>(sortBy: [SortDescriptor(\.name)])
        let apps = ((try? context.fetch(descriptor)) ?? []).filter(\.isTracked)

        let appSnapshots = apps.map { app in
            let aggregator = MetricsAggregator(apps: [app], fx: fx, currency: currency)
            // Keep two full 30-day periods so configurable widgets can compare
            // the selected range with the immediately preceding range.
            let downloads = aggregator.downloadSeries(days: 60)
            let proceeds = aggregator.salesSeries(.proceeds, days: 60)
            let feedback = app.reviews
                .filter(\.needsAttention)
                .sorted { $0.createdDate > $1.createdDate }
                .prefix(50)
                .map {
                    WidgetFeedbackSnapshot(
                        id: $0.id,
                        appID: app.id.uuidString,
                        appName: app.name,
                        rating: $0.rating,
                        title: $0.title,
                        body: $0.body,
                        territory: $0.territory,
                        createdDate: $0.createdDate
                    )
                }

            return WidgetAppSnapshot(
                id: app.id.uuidString,
                appStoreID: app.remoteIdentifier,
                platformRaw: app.platform.rawValue,
                name: app.name,
                isSelected: app.isSelected,
                stateLabel: app.state.label,
                downloads: downloads.map { WidgetMetricSample(date: $0.date, value: $0.value) },
                proceeds: proceeds.map { WidgetMetricSample(date: $0.date, value: $0.value) },
                feedback: Array(feedback)
            )
        }

        let snapshot = StoreGaugeWidgetSnapshot(
            generatedAt: Date(),
            currency: currency,
            apps: appSnapshots
        )

        guard (try? StoreGaugeWidgetStorage.save(snapshot)) != nil else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: StoreGaugeWidgetConstants.performanceKind)
        WidgetCenter.shared.reloadTimelines(ofKind: StoreGaugeWidgetConstants.feedbackKind)
    }
}

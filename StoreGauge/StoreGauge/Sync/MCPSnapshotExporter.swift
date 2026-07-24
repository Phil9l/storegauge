//
//  MCPSnapshotExporter.swift
//  StoreGauge
//
//  Exports a credential-free dataset for the optional MCP helper.
//

import Foundation
import CryptoKit
import SwiftData

@MainActor
enum MCPSnapshotExporter {
    static func publish(context: ModelContext, settings: AppSettings, fx: FXService) {
        guard settings.mcpEnabled else {
            StoreGaugeMCPStorage.removeSnapshot()
            return
        }

        let descriptor = FetchDescriptor<TrackedApp>(sortBy: [SortDescriptor(\.name)])
        let apps = ((try? context.fetch(descriptor)) ?? []).filter {
            !$0.isArchived && (!settings.mcpSelectedAppsOnly || $0.isSelected)
        }

        let financialKinds: Set<MetricKind> = [.proceeds, .grossSales, .netEarnings, .orders]
        let appSnapshots = apps.map { app in
            let metrics = app.metrics
                .filter { settings.mcpIncludeFinancialData || !financialKinds.contains($0.kind) }
                .sorted { $0.date < $1.date }
                .map { metric in
                    let displayValue: Double?
                    if let currency = metric.currency {
                        displayValue = fx.convert(metric.value, from: currency,
                                                  to: settings.displayCurrency)
                    } else {
                        displayValue = nil
                    }
                    return MCPMetricSnapshot(
                        id: metric.key,
                        date: metric.date,
                        kind: metric.kind.rawValue,
                        value: metric.value,
                        currency: metric.currency,
                        source: metric.sourceRaw,
                        displayValue: displayValue
                    )
                }

            let reviews = app.reviews
                .sorted { $0.createdDate > $1.createdDate }
                .map { review in
                    MCPReviewSnapshot(
                        id: review.id,
                        remoteIdentifier: review.remoteIdentifier,
                        rating: review.rating,
                        title: settings.mcpIncludeReviewText ? review.title : nil,
                        body: settings.mcpIncludeReviewText ? review.body : nil,
                        reviewer: settings.mcpIncludeReviewText ? review.reviewer : nil,
                        territory: review.territory,
                        language: review.reviewerLanguage,
                        createdDate: review.createdDate,
                        triage: review.triage.rawValue,
                        hasResponse: review.hasResponse,
                        responseBody: settings.mcpIncludeReviewText ? review.responseBody : nil,
                        responseIdentifier: review.responseID,
                        responseState: review.responseState,
                        responseDate: review.responseDate,
                        isRead: review.isRead,
                        translatedTitle: settings.mcpIncludeReviewText ? review.translatedTitle : nil,
                        translatedBody: settings.mcpIncludeReviewText ? review.translatedBody : nil,
                        translationSourceLanguage: review.translationSourceLanguage,
                        translationTargetLanguage: review.translationTargetLanguage
                    )
                }

            let statusHistory = app.statusEvents
                .sorted { $0.date > $1.date }
                .map { event in
                    MCPStatusSnapshot(
                        id: [
                            app.id.uuidString.lowercased(),
                            String(event.date.timeIntervalSince1970),
                            event.versionString ?? "-",
                            event.fromStateRaw ?? "-",
                            event.toStateRaw ?? "-"
                        ].joined(separator: "|"),
                        date: event.date,
                        version: event.versionString,
                        fromState: event.fromStateRaw,
                        toState: event.toStateRaw
                    )
                }

            let metadata = app.metadataSnapshots
                .sorted { $0.locale.localizedCaseInsensitiveCompare($1.locale) == .orderedAscending }
                .map {
                    MCPMetadataSnapshot(
                        id: $0.key,
                        locale: $0.locale,
                        name: $0.name,
                        subtitle: $0.subtitle,
                        description: $0.localizedDescription,
                        keywords: $0.keywords,
                        promotionalText: $0.promotionalText,
                        whatsNew: $0.whatsNew,
                        marketingURL: $0.marketingURL,
                        supportURL: $0.supportURL,
                        screenshots: $0.screenshots,
                        updatedAt: $0.updatedAt
                    )
                }

            let metadataChanges = app.metadataChanges
                .sorted { $0.date > $1.date }
                .map {
                    MCPMetadataChangeSnapshot(
                        id: stableID([
                            app.id.uuidString.lowercased(), String($0.date.timeIntervalSince1970),
                            $0.locale, $0.fieldRaw, $0.versionString ?? "-",
                            $0.oldValue ?? "-", $0.newValue ?? "-"
                        ]),
                        date: $0.date,
                        locale: $0.locale,
                        field: $0.fieldRaw,
                        oldValue: $0.oldValue,
                        newValue: $0.newValue,
                        version: $0.versionString
                    )
                }

            let annotations = app.annotations
                .sorted { $0.date > $1.date }
                .map {
                    MCPAnnotationSnapshot(
                        id: $0.id.uuidString,
                        date: $0.date,
                        note: $0.note,
                        category: $0.categoryRaw,
                        createdAt: $0.createdAt
                    )
                }

            return MCPAppSnapshot(
                id: app.id.uuidString,
                remoteIdentifier: app.remoteIdentifier,
                platform: app.platform.rawValue,
                name: app.name,
                bundleID: app.bundleID,
                accountID: app.account?.id.uuidString,
                accountName: app.account?.name,
                sku: app.sku,
                primaryLocale: app.primaryLocale,
                iconURL: app.iconURLString,
                firstSeenAt: app.firstSeenAt,
                isPinned: app.isPinned,
                version: app.currentVersionString,
                releaseState: app.state.label,
                releaseStateRaw: app.currentStateRaw,
                releaseUpdatedAt: app.statusUpdatedAt,
                currentPlatform: app.currentPlatform,
                phasedReleaseState: app.phasedReleaseState,
                phasedReleaseDay: app.phasedReleaseDay,
                isSelected: app.isSelected,
                metrics: metrics,
                reviews: Array(reviews),
                statusHistory: statusHistory,
                metadata: metadata,
                metadataChanges: metadataChanges,
                annotations: annotations
            )
        }

        let allAnnotations = (try? context.fetch(FetchDescriptor<ChartAnnotation>())) ?? []
        let globalAnnotations = allAnnotations
            .filter { $0.app == nil }
            .sorted { $0.date > $1.date }
            .map {
                MCPAnnotationSnapshot(
                    id: $0.id.uuidString,
                    date: $0.date,
                    note: $0.note,
                    category: $0.categoryRaw,
                    createdAt: $0.createdAt
                )
            }

        let snapshot = StoreGaugeMCPSnapshot(
            schemaVersion: 2,
            generatedAt: Date(),
            displayCurrency: settings.displayCurrency,
            includesReviewText: settings.mcpIncludeReviewText,
            includesFinancialData: settings.mcpIncludeFinancialData,
            apps: appSnapshots,
            globalAnnotations: globalAnnotations
        )
        try? StoreGaugeMCPStorage.saveSnapshot(snapshot)
    }

    private static func stableID(_ fields: [String]) -> String {
        SHA256.hash(data: Data(fields.joined(separator: "\u{1f}").utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

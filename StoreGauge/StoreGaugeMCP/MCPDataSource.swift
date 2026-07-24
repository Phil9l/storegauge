import Foundation
import MCP

actor MCPDataSource {
    func portfolio(days: Int) throws -> Value {
        let snapshot = try loadSnapshot()
        let apps = snapshot.apps
        let metrics = recentMetrics(in: apps, days: days)
        let reviews = apps.flatMap(\.reviews).filter { $0.createdDate >= cutoff(days) }
        let downloads = total(metrics, kinds: ["installs"]) +
            max(0, total(metrics, kinds: ["units"]) - total(metrics, kinds: ["updates"]))
        let ratings = reviews.map { Double($0.rating) }

        return .object([
            "generated_at": dateValue(snapshot.generatedAt),
            "period_days": .int(days),
            "display_currency": .string(snapshot.displayCurrency),
            "app_count": .int(apps.count),
            "downloads": number(downloads),
            "updates": number(total(metrics, kinds: ["updates"])),
            "sessions": number(total(metrics, kinds: ["sessions"])),
            "active_devices": number(total(metrics, kinds: ["activeDevices"])),
            "crashes": number(total(metrics, kinds: ["crashes"])),
            "proceeds": financialValue(totalDisplay(metrics, kinds: ["proceeds"]), snapshot),
            "gross_sales": financialValue(totalDisplay(metrics, kinds: ["grossSales"]), snapshot),
            "net_earnings": financialValue(totalDisplay(metrics, kinds: ["netEarnings"]), snapshot),
            "orders": financialValue(total(metrics, kinds: ["orders"]), snapshot),
            "review_count": .int(reviews.count),
            "average_rating": ratings.isEmpty ? .null : number(ratings.reduce(0, +) / Double(ratings.count)),
            "review_text_included": .bool(snapshot.includesReviewText),
            "financial_data_included": .bool(snapshot.includesFinancialData)
        ])
    }

    func apps(arguments: [String: Value] = [:]) throws -> Value {
        let snapshot = try loadSnapshot()
        let platform = normalized(arguments["platform"]?.stringValue)
        let account = normalized(arguments["account"]?.stringValue)
        let query = normalized(arguments["query"]?.stringValue)
        let apps = snapshot.apps.filter { app in
            if let platform, app.platform.lowercased() != platform { return false }
            if let account {
                let accounts = [app.accountID, app.accountName].compactMap { $0?.lowercased() }
                if !accounts.contains(account) { return false }
            }
            if let query {
                let fields = [app.name, app.bundleID, app.remoteIdentifier, app.sku]
                    .compactMap { $0?.lowercased() }
                if !fields.contains(where: { $0.contains(query) }) { return false }
            }
            return true
        }

        return .object([
            "generated_at": dateValue(snapshot.generatedAt),
            "total_matches": .int(apps.count),
            "apps": .array(apps.map(appValue))
        ])
    }

    func performance(appID: String?, days: Int) throws -> Value {
        let snapshot = try loadSnapshot()
        let apps = try selectedApps(snapshot, appID: appID)
        return .object([
            "generated_at": dateValue(snapshot.generatedAt),
            "period_days": .int(days),
            "display_currency": .string(snapshot.displayCurrency),
            "apps": .array(apps.map { app in
                .object([
                    "app": appValue(app),
                    "metrics": .array(app.metrics
                        .filter { $0.date >= cutoff(days) }
                        .sorted(by: metricAscending)
                        .map { metricValue(app: app, metric: $0) })
                ])
            })
        ])
    }

    func metrics(arguments: [String: Value]) throws -> Value {
        let snapshot = try loadSnapshot()
        let apps = try selectedApps(snapshot, appID: arguments["app_id"]?.stringValue)
        let platform = normalized(arguments["platform"]?.stringValue)
        let kinds = Set(arguments["kinds"]?.arrayValue?.compactMap {
            normalized($0.stringValue)
        } ?? [])
        let source = normalized(arguments["source"]?.stringValue)
        let range = try dateRange(arguments)
        let limit = bounded(arguments["limit"]?.intValue, default: 200, maximum: 1_000)
        let cursor = try decodeCursor(arguments["cursor"]?.stringValue, kind: "metrics")

        var rows: [MetricRow] = []
        for app in apps where platform == nil || app.platform.lowercased() == platform {
            for metric in app.metrics {
                guard within(metric.date, range: range) else { continue }
                if !kinds.isEmpty, !kinds.contains(metric.kind.lowercased()) { continue }
                if let source, metric.source?.lowercased() != source { continue }
                rows.append(MetricRow(app: app, metric: metric))
            }
        }
        rows.sort(by: metricRowAscending)
        return pagedResult(
            rows: rows,
            cursor: cursor,
            limit: limit,
            generatedAt: snapshot.generatedAt,
            collectionName: "metrics",
            cursorKind: "metrics",
            date: { $0.metric.date },
            id: \.cursorID,
            value: { metricValue(app: $0.app, metric: $0.metric) },
            extra: [
                "display_currency": .string(snapshot.displayCurrency),
                "financial_data_included": .bool(snapshot.includesFinancialData)
            ]
        )
    }

    func reviews(arguments: [String: Value]) throws -> Value {
        let snapshot = try loadSnapshot()
        let apps = try selectedApps(snapshot, appID: arguments["app_id"]?.stringValue)
        let status = normalized(arguments["status"]?.stringValue)
        let platform = normalized(arguments["platform"]?.stringValue)
        let language = normalized(arguments["language"]?.stringValue)
        let territory = normalized(arguments["territory"]?.stringValue)
        let minimum = min(max(arguments["minimum_rating"]?.intValue ?? 1, 1), 5)
        let maximum = min(max(arguments["maximum_rating"]?.intValue ?? 5, 1), 5)
        guard minimum <= maximum else {
            throw MCPError.invalidParams("minimum_rating must be less than or equal to maximum_rating")
        }
        let query = normalized(arguments["query"]?.stringValue)
        let hasResponse = arguments["has_response"]?.boolValue
        let range = try dateRange(arguments)
        let limit = bounded(arguments["limit"]?.intValue, default: 50, maximum: 200)
        let cursor = try decodeCursor(arguments["cursor"]?.stringValue, kind: "reviews")

        var rows: [ReviewRow] = []
        for app in apps where platform == nil || app.platform.lowercased() == platform {
            for review in app.reviews {
                guard review.rating >= minimum, review.rating <= maximum,
                      within(review.createdDate, range: range) else { continue }
                if let status, review.triage.lowercased() != status { continue }
                if let language, review.language?.lowercased() != language { continue }
                if let territory, review.territory.lowercased() != territory { continue }
                if let hasResponse, (review.hasResponse ?? (review.responseBody?.isEmpty == false)) != hasResponse {
                    continue
                }
                if let query {
                    let fields = [
                        review.title, review.body, review.reviewer, review.responseBody,
                        review.translatedTitle, review.translatedBody
                    ].compactMap { $0?.lowercased() }
                    guard fields.contains(where: { $0.contains(query) }) else { continue }
                }
                rows.append(ReviewRow(app: app, review: review))
            }
        }
        rows.sort(by: reviewRowAscending)
        return pagedResult(
            rows: rows,
            cursor: cursor,
            limit: limit,
            generatedAt: snapshot.generatedAt,
            collectionName: "reviews",
            cursorKind: "reviews",
            date: { $0.review.createdDate },
            id: \.cursorID,
            value: reviewValue,
            extra: ["review_text_included": .bool(snapshot.includesReviewText)]
        )
    }

    func releases(appID: String?) throws -> Value {
        let snapshot = try loadSnapshot()
        let apps = try selectedApps(snapshot, appID: appID)
        return .object([
            "generated_at": dateValue(snapshot.generatedAt),
            "releases": .array(apps.map(releaseValue))
        ])
    }

    func releaseHistory(arguments: [String: Value]) throws -> Value {
        let snapshot = try loadSnapshot()
        let apps = try selectedApps(snapshot, appID: arguments["app_id"]?.stringValue)
        let platform = normalized(arguments["platform"]?.stringValue)
        let state = normalized(arguments["state"]?.stringValue)
        let range = try dateRange(arguments)
        let limit = bounded(arguments["limit"]?.intValue, default: 100, maximum: 500)
        let cursor = try decodeCursor(arguments["cursor"]?.stringValue, kind: "release_history")

        var rows: [StatusRow] = []
        for app in apps where platform == nil || app.platform.lowercased() == platform {
            for statusEvent in app.statusHistory ?? [] {
                guard within(statusEvent.date, range: range) else { continue }
                if let state {
                    let states = [statusEvent.fromState, statusEvent.toState]
                        .compactMap { $0?.lowercased() }
                    guard states.contains(state) else { continue }
                }
                rows.append(StatusRow(app: app, status: statusEvent))
            }
        }
        rows.sort(by: statusRowAscending)
        return pagedResult(
            rows: rows,
            cursor: cursor,
            limit: limit,
            generatedAt: snapshot.generatedAt,
            collectionName: "release_history",
            cursorKind: "release_history",
            date: { $0.status.date },
            id: \.cursorID,
            value: statusValue
        )
    }

    func metadata(arguments: [String: Value]) throws -> Value {
        let snapshot = try loadSnapshot()
        let apps = try selectedApps(snapshot, appID: arguments["app_id"]?.stringValue)
        let platform = normalized(arguments["platform"]?.stringValue)
        let locale = normalized(arguments["locale"]?.stringValue)
        let query = normalized(arguments["query"]?.stringValue)
        let limit = bounded(arguments["limit"]?.intValue, default: 50, maximum: 200)
        let cursor = try decodeCursor(arguments["cursor"]?.stringValue, kind: "metadata")

        var rows: [MetadataRow] = []
        for app in apps where platform == nil || app.platform.lowercased() == platform {
            for metadata in app.metadata ?? [] {
                if let locale, metadata.locale.lowercased() != locale { continue }
                if let query {
                    let fields = [
                        metadata.name, metadata.subtitle, metadata.description, metadata.keywords,
                        metadata.promotionalText, metadata.whatsNew, metadata.marketingURL,
                        metadata.supportURL, metadata.screenshots
                    ].compactMap { $0?.lowercased() }
                    guard fields.contains(where: { $0.contains(query) }) else { continue }
                }
                rows.append(MetadataRow(app: app, metadata: metadata))
            }
        }
        rows.sort(by: metadataRowAscending)
        return pagedResult(
            rows: rows,
            cursor: cursor,
            limit: limit,
            generatedAt: snapshot.generatedAt,
            collectionName: "metadata",
            cursorKind: "metadata",
            date: { $0.metadata.updatedAt },
            id: \.cursorID,
            value: metadataValue
        )
    }

    func metadataChanges(arguments: [String: Value]) throws -> Value {
        let snapshot = try loadSnapshot()
        let apps = try selectedApps(snapshot, appID: arguments["app_id"]?.stringValue)
        let platform = normalized(arguments["platform"]?.stringValue)
        let locale = normalized(arguments["locale"]?.stringValue)
        let field = normalized(arguments["field"]?.stringValue)
        let query = normalized(arguments["query"]?.stringValue)
        let range = try dateRange(arguments)
        let limit = bounded(arguments["limit"]?.intValue, default: 100, maximum: 500)
        let cursor = try decodeCursor(arguments["cursor"]?.stringValue, kind: "metadata_changes")

        var rows: [MetadataChangeRow] = []
        for app in apps where platform == nil || app.platform.lowercased() == platform {
            for change in app.metadataChanges ?? [] {
                guard within(change.date, range: range) else { continue }
                if let locale, change.locale.lowercased() != locale { continue }
                if let field, change.field.lowercased() != field { continue }
                if let query {
                    let fields = [change.oldValue, change.newValue].compactMap { $0?.lowercased() }
                    guard fields.contains(where: { $0.contains(query) }) else { continue }
                }
                rows.append(MetadataChangeRow(app: app, change: change))
            }
        }
        rows.sort(by: metadataChangeRowAscending)
        return pagedResult(
            rows: rows,
            cursor: cursor,
            limit: limit,
            generatedAt: snapshot.generatedAt,
            collectionName: "metadata_changes",
            cursorKind: "metadata_changes",
            date: { $0.change.date },
            id: \.cursorID,
            value: metadataChangeValue
        )
    }

    func annotations(arguments: [String: Value]) throws -> Value {
        let snapshot = try loadSnapshot()
        let requestedAppID = arguments["app_id"]?.stringValue
        let apps = try selectedApps(snapshot, appID: requestedAppID)
        let category = normalized(arguments["category"]?.stringValue)
        let query = normalized(arguments["query"]?.stringValue)
        let range = try dateRange(arguments)
        let limit = bounded(arguments["limit"]?.intValue, default: 100, maximum: 500)
        let cursor = try decodeCursor(arguments["cursor"]?.stringValue, kind: "annotations")

        var rows: [AnnotationRow] = apps.flatMap { app in
            (app.annotations ?? []).map { AnnotationRow(app: app, annotation: $0) }
        }
        if requestedAppID == nil {
            rows.append(contentsOf: (snapshot.globalAnnotations ?? []).map {
                AnnotationRow(app: nil, annotation: $0)
            })
        }
        rows = rows.filter { row in
            guard within(row.annotation.date, range: range) else { return false }
            if let category, row.annotation.category.lowercased() != category { return false }
            if let query, !row.annotation.note.lowercased().contains(query) { return false }
            return true
        }
        rows.sort(by: annotationRowAscending)
        return pagedResult(
            rows: rows,
            cursor: cursor,
            limit: limit,
            generatedAt: snapshot.generatedAt,
            collectionName: "annotations",
            cursorKind: "annotations",
            date: { $0.annotation.date },
            id: \.cursorID,
            value: annotationValue
        )
    }

    func resources() throws -> [Resource] {
        let snapshot = try loadSnapshot()
        let fixed = [
            Resource(name: "portfolio", uri: "storegauge://portfolio", title: "StoreGauge portfolio",
                     description: "Current cross-store portfolio summary.", mimeType: "application/json"),
            Resource(name: "apps", uri: "storegauge://apps", title: "StoreGauge apps",
                     description: "Current App Store and Google Play app catalog.", mimeType: "application/json")
        ]
        return fixed + snapshot.apps.map { app in
            Resource(name: "app-\(app.id)", uri: "storegauge://apps/\(app.id)", title: app.name,
                     description: "Recent store data for \(app.name).", mimeType: "application/json")
        }
    }

    func resource(uri: String) throws -> Value {
        if uri == "storegauge://portfolio" { return try portfolio(days: 30) }
        if uri == "storegauge://apps" { return try apps() }
        let prefix = "storegauge://apps/"
        guard uri.hasPrefix(prefix) else { throw MCPError.invalidParams("Unknown resource URI") }
        return try performance(appID: String(uri.dropFirst(prefix.count)), days: 30)
    }

    private func loadSnapshot() throws -> StoreGaugeMCPSnapshot {
        let snapshot = StoreGaugeMCPStorage.loadSnapshot()
        guard snapshot.generatedAt != .distantPast else {
            throw MCPError.serverError(code: -32002,
                message: "MCP sharing is off or StoreGauge has not exported data yet. Open StoreGauge → Settings → Integrations.")
        }
        return snapshot
    }

    private func selectedApps(_ snapshot: StoreGaugeMCPSnapshot, appID: String?) throws -> [MCPAppSnapshot] {
        guard let appID, !appID.isEmpty else { return snapshot.apps }
        let match = snapshot.apps.first {
            [$0.id, $0.remoteIdentifier, $0.bundleID, $0.name].contains {
                $0.localizedCaseInsensitiveCompare(appID) == .orderedSame
            }
        }
        guard let match else { throw MCPError.invalidParams("No app matches '\(appID)'. Use list_apps to find an ID.") }
        return [match]
    }

    private func recentMetrics(in apps: [MCPAppSnapshot], days: Int) -> [MCPMetricSnapshot] {
        apps.flatMap(\.metrics).filter { $0.date >= cutoff(days) }
    }

    private func cutoff(_ days: Int) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
    }

    private func total(_ metrics: [MCPMetricSnapshot], kinds: Set<String>) -> Double {
        metrics.filter { kinds.contains($0.kind) }.reduce(0) { $0 + $1.value }
    }

    private func totalDisplay(_ metrics: [MCPMetricSnapshot], kinds: Set<String>) -> Double {
        metrics.filter { kinds.contains($0.kind) }.reduce(0) { $0 + ($1.displayValue ?? $1.value) }
    }

    private func appValue(_ app: MCPAppSnapshot) -> Value {
        .object([
            "id": .string(app.id),
            "store_id": .string(app.remoteIdentifier),
            "platform": .string(app.platform),
            "name": .string(app.name),
            "bundle_id": .string(app.bundleID),
            "account_id": optionalString(app.accountID),
            "account_name": optionalString(app.accountName),
            "sku": optionalString(app.sku),
            "primary_locale": optionalString(app.primaryLocale),
            "icon_url": optionalString(app.iconURL),
            "first_seen_at": optionalDate(app.firstSeenAt),
            "version": optionalString(app.version),
            "release_state": .string(app.releaseState),
            "release_state_raw": optionalString(app.releaseStateRaw),
            "release_updated_at": optionalDate(app.releaseUpdatedAt),
            "current_platform": optionalString(app.currentPlatform),
            "phased_release_state": optionalString(app.phasedReleaseState),
            "phased_release_day": app.phasedReleaseDay.map(Value.int) ?? .null,
            "selected": .bool(app.isSelected),
            "pinned": .bool(app.isPinned ?? false),
            "metric_count": .int(app.metrics.count),
            "review_count": .int(app.reviews.count),
            "release_event_count": .int(app.statusHistory?.count ?? 0),
            "metadata_locale_count": .int(app.metadata?.count ?? 0),
            "metadata_change_count": .int(app.metadataChanges?.count ?? 0),
            "annotation_count": .int(app.annotations?.count ?? 0)
        ])
    }

    private func metricValue(app: MCPAppSnapshot, metric: MCPMetricSnapshot) -> Value {
        .object([
            "id": optionalString(metric.id),
            "app_id": .string(app.id),
            "app_name": .string(app.name),
            "platform": .string(app.platform),
            "date": dateValue(metric.date),
            "kind": .string(metric.kind),
            "value": number(metric.value),
            "currency": optionalString(metric.currency),
            "source": optionalString(metric.source),
            "display_value": metric.displayValue.map(number) ?? .null
        ])
    }

    private func reviewValue(_ row: ReviewRow) -> Value {
        let app = row.app
        let review = row.review
        return .object([
            "id": .string(review.id),
            "store_review_id": optionalString(review.remoteIdentifier),
            "app_id": .string(app.id),
            "app_name": .string(app.name),
            "platform": .string(app.platform),
            "rating": .int(review.rating),
            "title": optionalString(review.title),
            "body": optionalString(review.body),
            "reviewer": optionalString(review.reviewer),
            "territory": .string(review.territory),
            "language": optionalString(review.language),
            "created_at": dateValue(review.createdDate),
            "triage": .string(review.triage),
            "is_read": review.isRead.map(Value.bool) ?? .null,
            "has_response": review.hasResponse.map(Value.bool) ?? .null,
            "response": optionalString(review.responseBody),
            "response_id": optionalString(review.responseIdentifier),
            "response_state": optionalString(review.responseState),
            "response_date": optionalDate(review.responseDate),
            "translated_title": optionalString(review.translatedTitle),
            "translated_body": optionalString(review.translatedBody),
            "translation_source_language": optionalString(review.translationSourceLanguage),
            "translation_target_language": optionalString(review.translationTargetLanguage)
        ])
    }

    private func releaseValue(_ app: MCPAppSnapshot) -> Value {
        .object([
            "app_id": .string(app.id),
            "name": .string(app.name),
            "platform": .string(app.platform),
            "version": optionalString(app.version),
            "state": .string(app.releaseState),
            "raw_state": optionalString(app.releaseStateRaw),
            "updated_at": optionalDate(app.releaseUpdatedAt),
            "current_platform": optionalString(app.currentPlatform),
            "phased_release_state": optionalString(app.phasedReleaseState),
            "phased_release_day": app.phasedReleaseDay.map(Value.int) ?? .null
        ])
    }

    private func statusValue(_ row: StatusRow) -> Value {
        .object([
            "id": .string(row.status.id),
            "app_id": .string(row.app.id),
            "app_name": .string(row.app.name),
            "platform": .string(row.app.platform),
            "date": dateValue(row.status.date),
            "version": optionalString(row.status.version),
            "from_state": optionalString(row.status.fromState),
            "to_state": optionalString(row.status.toState)
        ])
    }

    private func metadataValue(_ row: MetadataRow) -> Value {
        let metadata = row.metadata
        return .object([
            "id": .string(metadata.id),
            "app_id": .string(row.app.id),
            "app_name": .string(row.app.name),
            "platform": .string(row.app.platform),
            "locale": .string(metadata.locale),
            "name": optionalString(metadata.name),
            "subtitle": optionalString(metadata.subtitle),
            "description": optionalString(metadata.description),
            "keywords": optionalString(metadata.keywords),
            "promotional_text": optionalString(metadata.promotionalText),
            "whats_new": optionalString(metadata.whatsNew),
            "marketing_url": optionalString(metadata.marketingURL),
            "support_url": optionalString(metadata.supportURL),
            "screenshots": optionalString(metadata.screenshots),
            "updated_at": dateValue(metadata.updatedAt)
        ])
    }

    private func metadataChangeValue(_ row: MetadataChangeRow) -> Value {
        let change = row.change
        return .object([
            "id": .string(change.id),
            "app_id": .string(row.app.id),
            "app_name": .string(row.app.name),
            "platform": .string(row.app.platform),
            "date": dateValue(change.date),
            "locale": .string(change.locale),
            "field": .string(change.field),
            "old_value": optionalString(change.oldValue),
            "new_value": optionalString(change.newValue),
            "version": optionalString(change.version)
        ])
    }

    private func annotationValue(_ row: AnnotationRow) -> Value {
        .object([
            "id": .string(row.annotation.id),
            "app_id": optionalString(row.app?.id),
            "app_name": optionalString(row.app?.name),
            "platform": optionalString(row.app?.platform),
            "scope": .string(row.app == nil ? "portfolio" : "app"),
            "date": dateValue(row.annotation.date),
            "note": .string(row.annotation.note),
            "category": .string(row.annotation.category),
            "created_at": dateValue(row.annotation.createdAt)
        ])
    }

    private func financialValue(_ value: Double, _ snapshot: StoreGaugeMCPSnapshot) -> Value {
        snapshot.includesFinancialData ? number(value) : .null
    }
}

private struct ReviewRow {
    let app: MCPAppSnapshot
    let review: MCPReviewSnapshot
    var cursorID: String { "\(app.id)|\(review.id)" }
}

private struct MetricRow {
    let app: MCPAppSnapshot
    let metric: MCPMetricSnapshot
    var cursorID: String {
        "\(app.id)|\(metric.id ?? "\(metric.kind)|\(metric.currency ?? "-")")"
    }
}

private struct StatusRow {
    let app: MCPAppSnapshot
    let status: MCPStatusSnapshot
    var cursorID: String { "\(app.id)|\(status.id)" }
}

private struct MetadataRow {
    let app: MCPAppSnapshot
    let metadata: MCPMetadataSnapshot
    var cursorID: String { "\(app.id)|\(metadata.id)" }
}

private struct MetadataChangeRow {
    let app: MCPAppSnapshot
    let change: MCPMetadataChangeSnapshot
    var cursorID: String { "\(app.id)|\(change.id)" }
}

private struct AnnotationRow {
    let app: MCPAppSnapshot?
    let annotation: MCPAnnotationSnapshot
    var cursorID: String { "\(app?.id ?? "portfolio")|\(annotation.id)" }
}

private struct PageCursor: Codable {
    let version: Int
    let kind: String
    let date: Date
    let id: String
}

private struct DateRange {
    let start: Date?
    let end: Date?
}

private func pagedResult<Row>(
    rows: [Row],
    cursor: PageCursor?,
    limit: Int,
    generatedAt: Date,
    collectionName: String,
    cursorKind: String,
    date: (Row) -> Date,
    id: KeyPath<Row, String>,
    value: (Row) -> Value,
    extra: [String: Value] = [:]
) -> Value {
    let remaining = rows.filter { row in
        guard let cursor else { return true }
        let rowDate = date(row)
        return rowDate < cursor.date ||
            (rowDate == cursor.date && row[keyPath: id] > cursor.id)
    }
    let page = Array(remaining.prefix(limit))
    let hasMore = remaining.count > page.count
    let nextCursor: Value
    if hasMore, let last = page.last {
        nextCursor = .string(encodeCursor(PageCursor(
            version: 1, kind: cursorKind, date: date(last), id: last[keyPath: id]
        )))
    } else {
        nextCursor = .null
    }

    var object: [String: Value] = [
        "generated_at": dateValue(generatedAt),
        "total_matches": .int(rows.count),
        "page_size": .int(page.count),
        "has_more": .bool(hasMore),
        "next_cursor": nextCursor,
        collectionName: .array(page.map(value))
    ]
    object.merge(extra) { _, new in new }
    return .object(object)
}

private func dateRange(_ arguments: [String: Value]) throws -> DateRange {
    let start = try parseDate(arguments["start_date"]?.stringValue, field: "start_date", endOfDay: false)
    let end = try parseDate(arguments["end_date"]?.stringValue, field: "end_date", endOfDay: true)
    if let start, let end, start > end {
        throw MCPError.invalidParams("start_date must be before or equal to end_date")
    }
    return DateRange(start: start, end: end)
}

private func parseDate(_ string: String?, field: String, endOfDay: Bool) throws -> Date? {
    guard let string = trimmed(string) else { return nil }
    if let date = ISO8601DateFormatter().date(from: string) { return date }
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractionalFormatter.date(from: string) { return date }
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.calendar = Calendar(identifier: .gregorian)
    dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    dateFormatter.dateFormat = "yyyy-MM-dd"
    if let date = dateFormatter.date(from: string) {
        guard endOfDay else { return date }
        return date.addingTimeInterval(86_400 - 0.001)
    }
    throw MCPError.invalidParams("\(field) must be an ISO 8601 date or timestamp")
}

private func within(_ date: Date, range: DateRange) -> Bool {
    (range.start == nil || date >= range.start!) && (range.end == nil || date <= range.end!)
}

private func decodeCursor(_ string: String?, kind: String) throws -> PageCursor? {
    guard let string = trimmed(string) else { return nil }
    var base64 = string.replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    guard let data = Data(base64Encoded: base64),
          let cursor = try? decoder.decode(PageCursor.self, from: data),
          cursor.version == 1, cursor.kind == kind else {
        throw MCPError.invalidParams("cursor is invalid or belongs to a different StoreGauge tool")
    }
    return cursor
}

private func encodeCursor(_ cursor: PageCursor) -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    guard let data = try? encoder.encode(cursor) else { return "" }
    return data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func normalized(_ string: String?) -> String? {
    trimmed(string)?.lowercased()
}

private func trimmed(_ string: String?) -> String? {
    guard let value = string?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else { return nil }
    return value
}

private func bounded(_ value: Int?, default defaultValue: Int, maximum: Int) -> Int {
    min(max(value ?? defaultValue, 1), maximum)
}

private func reviewRowAscending(_ lhs: ReviewRow, _ rhs: ReviewRow) -> Bool {
    lhs.review.createdDate != rhs.review.createdDate
        ? lhs.review.createdDate > rhs.review.createdDate
        : lhs.cursorID < rhs.cursorID
}

private func metricRowAscending(_ lhs: MetricRow, _ rhs: MetricRow) -> Bool {
    lhs.metric.date != rhs.metric.date
        ? lhs.metric.date > rhs.metric.date
        : lhs.cursorID < rhs.cursorID
}

private func statusRowAscending(_ lhs: StatusRow, _ rhs: StatusRow) -> Bool {
    lhs.status.date != rhs.status.date
        ? lhs.status.date > rhs.status.date
        : lhs.cursorID < rhs.cursorID
}

private func metadataRowAscending(_ lhs: MetadataRow, _ rhs: MetadataRow) -> Bool {
    lhs.metadata.updatedAt != rhs.metadata.updatedAt
        ? lhs.metadata.updatedAt > rhs.metadata.updatedAt
        : lhs.cursorID < rhs.cursorID
}

private func metadataChangeRowAscending(_ lhs: MetadataChangeRow, _ rhs: MetadataChangeRow) -> Bool {
    lhs.change.date != rhs.change.date
        ? lhs.change.date > rhs.change.date
        : lhs.cursorID < rhs.cursorID
}

private func annotationRowAscending(_ lhs: AnnotationRow, _ rhs: AnnotationRow) -> Bool {
    lhs.annotation.date != rhs.annotation.date
        ? lhs.annotation.date > rhs.annotation.date
        : lhs.cursorID < rhs.cursorID
}

private func metricAscending(_ lhs: MCPMetricSnapshot, _ rhs: MCPMetricSnapshot) -> Bool {
    lhs.date != rhs.date ? lhs.date < rhs.date : (lhs.id ?? "") < (rhs.id ?? "")
}

private func dateValue(_ date: Date) -> Value {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return .string(formatter.string(from: date))
}

private func optionalDate(_ date: Date?) -> Value { date.map(dateValue) ?? .null }
private func optionalString(_ string: String?) -> Value { string.map(Value.string) ?? .null }
private func number(_ value: Double) -> Value {
    value.rounded() == value && value <= Double(Int.max) && value >= Double(Int.min)
        ? .int(Int(value)) : .double(value)
}

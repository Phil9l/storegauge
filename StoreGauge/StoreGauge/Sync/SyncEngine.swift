//
//  SyncEngine.swift
//  StoreGauge
//
//  Routes each account to its store provider. Providers normalize their data
//  into StoreGauge's shared SwiftData models.
//

import Foundation
import SwiftData

@MainActor
final class SyncEngine {
    let context: ModelContext
    private let appleProvider: AppleAppStoreSyncProvider
    private let googleProvider: GooglePlaySyncProvider

    init(context: ModelContext, settings: AppSettings, notifier: Notifier) {
        self.context = context
        self.appleProvider = AppleAppStoreSyncProvider(context: context, settings: settings, notifier: notifier)
        self.googleProvider = GooglePlaySyncProvider(context: context, settings: settings, notifier: notifier)
    }

    typealias Progress = StoreSyncProgress

    /// Transitional Apple credential access for on-demand features. New provider
    /// operations should be dispatched by platform instead of assuming ASC.
    func credentials(for account: Account) throws -> ASCCredentials {
        guard account.platform == .appleAppStore else {
            throw StoreProviderError.unsupportedOperation(account.platform, "App Store Connect credentials")
        }
        return try appleProvider.credentials(for: account)
    }

    func googleCredentials(for account: Account) throws -> GoogleServiceAccountCredentials {
        guard account.platform == .googlePlay else {
            throw StoreProviderError.unsupportedOperation(account.platform, "Google Play credentials")
        }
        return try googleProvider.credentials(for: account)
    }

    func syncAll(progress: @escaping Progress = { _ in }) async {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        for account in accounts.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            await syncAccount(account, progress: progress)
        }
    }

    func syncAccount(_ account: Account, progress: @escaping Progress = { _ in }) async {
        let startedAt = Date()
        account.lastSyncAttemptAt = startedAt
        do {
            if account.isDemo {
                progress("Refreshing demo data · \(account.name)")
                try DemoDataSeeder.seed(account: account, context: context)
            } else {
                switch account.platform {
                case .appleAppStore:
                    try await appleProvider.sync(account: account, progress: progress)
                case .googlePlay:
                    try await googleProvider.sync(account: account, progress: progress)
                }
            }
            account.lastSyncedAt = Date()
            account.lastSyncError = nil
            account.lastSyncErrorAt = nil
            account.lastSyncDuration = Date().timeIntervalSince(startedAt)
            try context.save()
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            account.lastSyncError = detail
            account.lastSyncErrorAt = Date()
            account.lastSyncDuration = Date().timeIntervalSince(startedAt)
            DiagnosticLog.record("\(account.platform.displayName) · Sync failed · \(account.name) · \(detail)")
            try? context.save()
        }
    }

    /// Short, notification-focused refresh for iOS background execution.
    /// It deliberately skips analytics, financial reports, vitals, metadata
    /// history, and app discovery so it can finish inside BGAppRefreshTask's
    /// small runtime budget.
    func syncBackgroundAlerts() async -> Bool {
        let accounts = ((try? context.fetch(FetchDescriptor<Account>())) ?? [])
            .filter { !$0.isDemo }
            .sorted { $0.sortIndex < $1.sortIndex }
        guard !accounts.isEmpty else { return false }

        var completedAny = false
        for account in accounts {
            if Task.isCancelled { return false }
            do {
                switch account.platform {
                case .appleAppStore:
                    try await appleProvider.syncBackgroundAlerts(account: account)
                case .googlePlay:
                    try await googleProvider.syncBackgroundAlerts(account: account)
                }
                completedAny = true
            } catch is CancellationError {
                return false
            } catch {
                let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                DiagnosticLog.record(
                    "\(account.platform.displayName) · Background alert refresh failed · \(account.name) · \(detail)"
                )
            }
        }
        return completedAny
    }
}

// MARK: - Google Play provider

@MainActor
final class GooglePlaySyncProvider: StoreAccountSyncing {
    let platform = StorePlatform.googlePlay
    let context: ModelContext
    let settings: AppSettings
    let notifier: Notifier

    init(context: ModelContext, settings: AppSettings, notifier: Notifier) {
        self.context = context
        self.settings = settings
        self.notifier = notifier
    }

    func credentials(for account: Account) throws -> GoogleServiceAccountCredentials {
        guard let json = Keychain.load(account: account.id.uuidString) else {
            throw GooglePlayError.message("The service-account key for “\(account.name)” is missing from Keychain. Edit the account and choose the JSON key again.")
        }
        return try GoogleServiceAccountCredentials.decode(json: json)
    }

    func sync(account: Account, progress: @escaping StoreSyncProgress) async throws {
        guard account.platform == platform else {
            throw StoreProviderError.unsupportedOperation(account.platform, "Google Play sync")
        }
        let isFirstSync = account.lastSyncedAt == nil
        let client = GooglePlayClient(credentials: try credentials(for: account))
        DiagnosticLog.record("Google Play · Sync started · \(account.name)")
        progress("Loading Google Play apps · \(account.name)")
        let summaries = try await client.listApps()
        upsertApps(summaries, account: account, isFirstSync: isFirstSync)
        try context.save()

        var firstError: Error?
        for app in account.apps where app.isTracked {
            do {
                try await syncApp(app, client: client, isFirstSync: isFirstSync, progress: progress)
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        do {
            try await syncVitals(account: account, client: client, progress: progress)
        } catch {
            if firstError == nil { firstError = error }
        }

        if account.googleFinancialBucket?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            do {
                try await syncStatisticsReports(account: account, progress: progress)
            } catch {
                if firstError == nil { firstError = error }
            }
            do {
                try await syncFinancialReports(account: account, progress: progress)
            } catch {
                if let googleError = error as? GooglePlayError, googleError.statusCode == 403 {
                    // The report bucket is also useful without financial access:
                    // Global View app information still provides install exports.
                    DiagnosticLog.record("Google Play · Financial reports unavailable · \(googleError.detail)")
                } else if firstError == nil {
                    firstError = error
                }
            }
        }
        try context.save()
        if let firstError {
            DiagnosticLog.record("Google Play · Sync completed with error · \(firstError.localizedDescription)")
            throw firstError
        }
        DiagnosticLog.record("Google Play · Sync completed · \(account.name) · \(summaries.count) apps")
    }

    func syncBackgroundAlerts(account: Account) async throws {
        guard account.platform == platform else {
            throw StoreProviderError.unsupportedOperation(account.platform, "Google Play background alerts")
        }
        let client = GooglePlayClient(credentials: try credentials(for: account))
        let isFirstSync = account.lastSyncedAt == nil
        for app in account.apps where app.isTracked {
            try Task.checkCancellation()
            try await syncApp(
                app,
                client: client,
                isFirstSync: isFirstSync,
                progress: { _ in }
            )
        }
    }

    private struct FinancialMetricKey: Hashable {
        let appID: UUID
        let day: Date
        let currency: String?
    }

    private struct FinancialMetricValue {
        let appID: UUID
        let kind: MetricKind
        let day: Date
        let value: Double
        let currency: String?
        let source: MetricSource
    }

    private struct NormalizedMetric {
        let kind: MetricKind
        let day: Date
        let value: Double
        let currency: String?
        let source: MetricSource
    }

    private func syncVitals(account: Account,
                            client: GooglePlayClient,
                            progress: @escaping StoreSyncProgress) async throws {
        if let last = account.lastGoogleVitalsSyncAt,
           last > Date().addingTimeInterval(-2 * 60 * 60) {
            return
        }
        let historyDays = min(max(settings.salesHistoryDays, 30), 365)
        let cutoff = Date.daysAgo(historyDays).startOfDayUTC

        var firstError: Error?
        for app in account.apps where app.isTracked {
            do {
                progress("Google Play · Android vitals · \(app.name)")
                let vitals = try await client.vitals(packageName: app.remoteIdentifier,
                                                     historyDays: historyDays)
                let desired = vitals.crashRate.map {
                    NormalizedMetric(kind: .crashRate, day: $0.date, value: $0.value,
                                     currency: nil, source: .googleVitals)
                } + vitals.anrRate.map {
                    NormalizedMetric(kind: .anrRate, day: $0.date, value: $0.value,
                                     currency: nil, source: .googleVitals)
                }
                reconcileMetrics(app: app, desired: desired, source: .googleVitals,
                                 kinds: [.crashRate, .anrRate], cutoff: cutoff)
            } catch {
                if let googleError = error as? GooglePlayError, googleError.statusCode == 404 {
                    DiagnosticLog.record("Google Play · Android vitals · \(app.remoteIdentifier) · no published data")
                } else {
                    if firstError == nil {
                        firstError = operationError(error, app: app, operation: "Android vitals")
                    }
                    // A service outage or rate limit applies to the endpoint,
                    // not one package. Avoid repeating the full backoff for every app.
                    if (error as? GooglePlayError)?.isTransient == true { break }
                }
            }
        }
        if let firstError { throw firstError }
        account.lastGoogleVitalsSyncAt = Date()
        try context.save()
    }

    private func syncStatisticsReports(account: Account,
                                       progress: @escaping StoreSyncProgress) async throws {
        if let last = account.lastGoogleStatisticsSyncAt,
           last > Date().addingTimeInterval(-6 * 60 * 60) {
            return
        }
        guard let bucket = account.googleFinancialBucket else { return }
        let client = try GoogleCloudStorageClient(credentials: try credentials(for: account), bucket: bucket)
        let historyDays = min(max(settings.salesHistoryDays, 7), 365)
        let cutoff = Date.daysAgo(historyDays).startOfDayUTC
        let monthTokens = reportMonthTokens(cutoff: cutoff, through: Date().startOfDayUTC)

        for app in account.apps where app.isTracked {
            let prefix = "stats/installs/installs_\(app.remoteIdentifier)_"
            let objects = try await client.listObjects(prefix: prefix, maxResults: 10_000).filter { object in
                let name = object.name.lowercased()
                return name.hasSuffix("_country.csv") && monthTokens.contains(where: object.name.contains)
            }
            var installsByDay: [Date: Double] = [:]
            var upgradesByDay: [Date: Double] = [:]
            for object in objects {
                progress("Google Play · Installs · \(app.name) · \(object.name.split(separator: "/").last ?? "report")")
                let data = try await client.download(object: object.name)
                let rows = try await Task.detached(priority: .utility) {
                    try GoogleStatisticsReportParser.installs(data: data)
                }.value
                for row in rows where row.packageID == app.remoteIdentifier && row.date >= cutoff {
                    // The country export partitions users, so summing its rows
                    // produces the account-wide daily total without double-counting.
                    installsByDay[row.date, default: 0] += row.dailyUserInstalls
                    upgradesByDay[row.date, default: 0] += row.dailyDeviceUpgrades
                }
            }
            let dates = Set(installsByDay.keys).union(upgradesByDay.keys)
            let desired = dates.flatMap { day in
                [
                    NormalizedMetric(kind: .installs, day: day,
                                     value: installsByDay[day] ?? 0,
                                     currency: nil, source: .googleStatistics),
                    NormalizedMetric(kind: .updates, day: day,
                                     value: upgradesByDay[day] ?? 0,
                                     currency: nil, source: .googleStatistics),
                ]
            }
            reconcileMetrics(app: app, desired: desired, source: .googleStatistics,
                             kinds: [.installs, .updates], cutoff: cutoff)
            DiagnosticLog.record("Google Play · Install statistics · \(app.remoteIdentifier) · \(objects.count) reports · \(dates.count) days")
        }
        account.lastGoogleStatisticsSyncAt = Date()
        try context.save()
    }

    private func reconcileMetrics(app: TrackedApp,
                                  desired: [NormalizedMetric],
                                  source: MetricSource,
                                  kinds: Set<MetricKind>,
                                  cutoff: Date) {
        let desiredByKey = Dictionary(desired.map { metric in
            (MetricPoint.makeKey(app: app, kind: metric.kind, day: metric.day,
                                 currency: metric.currency), metric)
        }, uniquingKeysWith: { _, latest in latest })
        let existing = Dictionary(app.metrics.map { ($0.key, $0) },
                                  uniquingKeysWith: { first, _ in first })
        for (key, metric) in desiredByKey {
            if let point = existing[key] {
                point.date = metric.day
                point.kindRaw = metric.kind.rawValue
                point.value = metric.value
                point.currency = metric.currency
                point.sourceRaw = metric.source.rawValue
            } else {
                insertMetric(app: app, kind: metric.kind, day: metric.day,
                             value: metric.value, currency: metric.currency,
                             source: metric.source)
            }
        }
        let desiredKeys = Set(desiredByKey.keys)
        let stale = app.metrics.filter {
            $0.date >= cutoff && $0.sourceRaw == source.rawValue &&
                kinds.contains($0.kind) && !desiredKeys.contains($0.key)
        }
        for point in stale { context.delete(point) }
    }

    private func reportMonthTokens(cutoff: Date, through end: Date) -> Set<String> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let startMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: cutoff)) ?? cutoff
        let endMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: end)) ?? end
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMM"
        var tokens = Set<String>()
        var month = startMonth
        while month <= endMonth {
            tokens.insert(formatter.string(from: month))
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return tokens
    }

    private func syncFinancialReports(account: Account,
                                      progress: @escaping StoreSyncProgress) async throws {
        // The monthly files change daily, but Google data itself normally lags by
        // 3–7 days. A six-hour throttle keeps a 15-minute poll from downloading
        // the same potentially large ZIPs over and over.
        if let last = account.lastGoogleFinancialSyncAt,
           last > Date().addingTimeInterval(-6 * 60 * 60) {
            return
        }
        guard let bucket = account.googleFinancialBucket else { return }
        let trackedApps = account.apps.filter(\.isTracked)
        guard !trackedApps.isEmpty else { return }
        let client = try GoogleCloudStorageClient(credentials: try credentials(for: account), bucket: bucket)
        progress("Google Play · Financial reports")

        let calendar: Calendar = {
            var value = Calendar(identifier: .gregorian)
            value.timeZone = TimeZone(identifier: "UTC")!
            return value
        }()
        let today = Date().startOfDayUTC
        let cutoff = calendar.date(byAdding: .day, value: -max(1, settings.salesHistoryDays), to: today) ?? today
        let monthTokens = reportMonthTokens(cutoff: cutoff, through: today)

        let salesObjects = try await client.listObjects(prefix: "sales/").filter {
            $0.name.lowercased().hasSuffix(".zip") && monthTokens.contains(where: $0.name.contains)
        }
        let earningObjects = try await client.listObjects(prefix: "earnings/").filter {
            $0.name.lowercased().hasSuffix(".zip") && monthTokens.contains(where: $0.name.contains)
        }

        var sales: [GoogleEstimatedSale] = []
        for object in salesObjects {
            progress("Google Play · Estimated sales · \(object.name.split(separator: "/").last ?? "report")")
            let archive = try await client.download(object: object.name)
            let parsed = try await Task.detached(priority: .utility) {
                let csv = try GoogleFinancialArchive.csvData(from: archive)
                return try GoogleFinancialReportParser.estimatedSales(data: csv)
            }.value
            sales.append(contentsOf: parsed.filter { $0.date >= cutoff })
        }

        var earnings: [GoogleEarning] = []
        for object in earningObjects {
            progress("Google Play · Earnings · \(object.name.split(separator: "/").last ?? "report")")
            let archive = try await client.download(object: object.name)
            let parsed = try await Task.detached(priority: .utility) {
                let csv = try GoogleFinancialArchive.csvData(from: archive)
                return try GoogleFinancialReportParser.earnings(data: csv)
            }.value
            earnings.append(contentsOf: parsed.filter { $0.date >= cutoff })
        }

        let appByPackage = Dictionary(trackedApps.map { ($0.remoteIdentifier, $0) },
                                     uniquingKeysWith: { first, _ in first })
        var gross: [FinancialMetricKey: Double] = [:]
        var orders: [FinancialMetricKey: Double] = [:]
        for row in sales {
            guard let app = appByPackage[row.packageID] else { continue }
            let moneyKey = FinancialMetricKey(appID: app.id, day: row.date, currency: row.currency)
            let orderKey = FinancialMetricKey(appID: app.id, day: row.date, currency: nil)
            gross[moneyKey, default: 0] += row.grossAmount
            orders[orderKey, default: 0] += row.orderDelta
        }
        var net: [FinancialMetricKey: Double] = [:]
        for row in earnings {
            guard let app = appByPackage[row.packageID] else { continue }
            let key = FinancialMetricKey(appID: app.id, day: row.date, currency: row.merchantCurrency)
            net[key, default: 0] += row.netAmount
        }

        let appByID = Dictionary(trackedApps.map { ($0.id, $0) },
                                uniquingKeysWith: { first, _ in first })
        var desired: [String: FinancialMetricValue] = [:]
        for (key, value) in gross {
            if let app = appByID[key.appID] {
                let metricKey = MetricPoint.makeKey(app: app, kind: .grossSales, day: key.day, currency: key.currency)
                desired[metricKey] = FinancialMetricValue(appID: app.id, kind: .grossSales, day: key.day,
                                                          value: value, currency: key.currency,
                                                          source: .googleEstimatedSales)
            }
        }
        for (key, value) in orders {
            if let app = appByID[key.appID] {
                let metricKey = MetricPoint.makeKey(app: app, kind: .orders, day: key.day, currency: nil)
                desired[metricKey] = FinancialMetricValue(appID: app.id, kind: .orders, day: key.day,
                                                          value: value, currency: nil,
                                                          source: .googleEstimatedSales)
            }
        }
        for (key, value) in net {
            if let app = appByID[key.appID] {
                let metricKey = MetricPoint.makeKey(app: app, kind: .netEarnings, day: key.day, currency: key.currency)
                desired[metricKey] = FinancialMetricValue(appID: app.id, kind: .netEarnings, day: key.day,
                                                          value: value, currency: key.currency,
                                                          source: .googleEarnings)
            }
        }

        // Reconcile only after every requested report parsed successfully. This
        // updates revised refunds/adjustments and removes rows that disappeared.
        for app in trackedApps {
            let appDesired = desired.filter { $0.value.appID == app.id }
            let existing = Dictionary(app.metrics.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            for (key, metric) in appDesired {
                if let point = existing[key] {
                    point.date = metric.day
                    point.kindRaw = metric.kind.rawValue
                    point.value = metric.value
                    point.currency = metric.currency
                    point.sourceRaw = metric.source.rawValue
                } else {
                    insertMetric(app: app, kind: metric.kind, day: metric.day, value: metric.value,
                                 currency: metric.currency, source: metric.source)
                }
            }
            let desiredKeys = Set(appDesired.keys)
            let stale = app.metrics.filter {
                $0.date >= cutoff &&
                    ($0.kind == .grossSales || $0.kind == .orders || $0.kind == .netEarnings) &&
                    !desiredKeys.contains($0.key)
            }
            for point in stale { context.delete(point) }
        }
        account.lastGoogleFinancialSyncAt = Date()
        try context.save()
        DiagnosticLog.record("Google Play · Financial reports imported · \(sales.count) sales rows · \(earnings.count) earnings rows")
    }

    private func insertMetric(app: TrackedApp, kind: MetricKind, day: Date, value: Double,
                              currency: String?, source: MetricSource) {
        let key = MetricPoint.makeKey(app: app, kind: kind, day: day, currency: currency)
        context.insert(MetricPoint(key: key, date: day, kind: kind, value: value,
                                   currency: currency, source: source, app: app))
    }

    private func upsertApps(_ summaries: [GooglePlayAppSummary], account: Account, isFirstSync: Bool) {
        let existing = Dictionary(account.apps.map { ($0.remoteIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        for summary in summaries {
            if let app = existing[summary.packageName] {
                app.name = summary.displayName
                app.bundleID = summary.packageName
                app.platform = platform
            } else {
                let app = TrackedApp(appStoreID: summary.packageName,
                                     bundleID: summary.packageName,
                                     name: summary.displayName,
                                     account: account,
                                     platform: platform)
                app.isNewlyDiscovered = !isFirstSync
                context.insert(app)
                account.apps.append(app)
                if !isFirstSync && settings.notificationsEnabled {
                    notifier.notifyNewApp(app: summary.displayName)
                }
            }
        }
    }

    private func syncApp(_ app: TrackedApp,
                         client: GooglePlayClient,
                         isFirstSync: Bool,
                         progress: @escaping StoreSyncProgress) async throws {
        progress("Google Play · \(app.name)")
        var firstError: Error?

        do {
            if let release = try await client.productionRelease(packageName: app.remoteIdentifier) {
                let oldState = app.currentStateRaw
                app.currentVersionString = release.name.isEmpty ? release.versionCode.map(String.init) : release.name
                app.currentPlatform = "Android"
                app.currentStateRaw = release.lifecycleState
                app.statusUpdatedAt = Date()

                if oldState != release.lifecycleState, let oldState, !isFirstSync {
                    context.insert(StatusEvent(versionString: app.currentVersionString,
                                               fromStateRaw: oldState,
                                               toStateRaw: release.lifecycleState,
                                               app: app))
                    if settings.notificationsEnabled {
                        notifier.notifyStatusChange(app: app.name, state: AppStoreState(raw: release.lifecycleState))
                    }
                }
            }
        } catch {
            firstError = operationError(error, app: app, operation: "Production release")
        }

        try Task.checkCancellation()
        if app.iconURLString == nil {
            app.iconURLString = await IconService.iconURL(for: app.remoteIdentifier, platform: platform)
        }

        do {
            let fetched = try await client.reviews(packageName: app.remoteIdentifier)
            let existingByID = Dictionary(app.reviews.map { ($0.remoteIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
            var newOnes: [Review] = []
            for item in fetched {
                if let review = existingByID[item.id] {
                    if review.body != item.body { review.clearTranslation() }
                    review.rating = item.rating
                    review.body = item.body
                    review.reviewer = item.reviewer
                    review.reviewerLanguage = item.language
                    review.createdDate = item.createdDate
                    review.responseID = item.responseBody == nil ? nil : item.id
                    review.responseBody = item.responseBody
                    review.responseState = item.responseBody == nil ? nil : "PUBLISHED"
                    review.responseDate = item.responseDate
                } else {
                    let review = Review(id: item.id,
                                        rating: item.rating,
                                        title: "",
                                        body: item.body,
                                        reviewer: item.reviewer,
                                        territory: "",
                                        reviewerLanguage: item.language,
                                        createdDate: item.createdDate,
                                        app: app)
                    review.responseID = item.responseBody == nil ? nil : item.id
                    review.responseBody = item.responseBody
                    review.responseState = item.responseBody == nil ? nil : "PUBLISHED"
                    review.responseDate = item.responseDate
                    review.isRead = app.reviewsBackfilled ? false : true
                    context.insert(review)
                    if app.reviewsBackfilled && !isFirstSync { newOnes.append(review) }
                }
            }
            if !app.reviewsBackfilled { app.reviewsBackfilled = true }
            notifyNewReviews(newOnes, app: app, isFirstSync: isFirstSync)
        } catch {
            if firstError == nil {
                firstError = operationError(error, app: app, operation: "Reviews")
            }
        }

        try context.save()
        if let firstError { throw firstError }
    }

    private func operationError(_ error: Error, app: TrackedApp, operation: String) -> GooglePlayError {
        let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return .message("\(app.name) · \(operation): \(detail)",
                        statusCode: (error as? GooglePlayError)?.statusCode)
    }

    private func notifyNewReviews(_ reviews: [Review], app: TrackedApp, isFirstSync: Bool) {
        guard settings.notificationsEnabled, !isFirstSync, !reviews.isEmpty else { return }
        let rule = app.alertRuleRaw.flatMap(ReviewAlertRule.init(rawValue:)) ?? settings.globalAlertRule
        let alertable = reviews.filter { rule.allows(rating: $0.rating) }
        for review in alertable.prefix(5) {
            notifier.notifyNewReview(app: app.name, rating: review.rating,
                                     title: review.title, body: review.body)
        }
        if alertable.count > 5 {
            notifier.notify(title: "\(alertable.count) new reviews · \(app.name)",
                            body: "Open StoreGauge to triage them.")
        }
    }
}

// MARK: - Apple App Store provider

@MainActor
final class AppleAppStoreSyncProvider: StoreAccountSyncing {
    let platform = StorePlatform.appleAppStore
    let context: ModelContext
    let settings: AppSettings
    let notifier: Notifier

    init(context: ModelContext, settings: AppSettings, notifier: Notifier) {
        self.context = context
        self.settings = settings
        self.notifier = notifier
    }

    typealias Progress = StoreSyncProgress

    func credentials(for account: Account) throws -> ASCCredentials {
        guard let p8 = Keychain.load(account: account.id.uuidString) else {
            throw ASCError.message("The private key for “\(account.name)” is missing from the Keychain. Edit the account and paste the .p8 key again.")
        }
        return ASCCredentials(issuerID: account.issuerID, keyID: account.keyID, p8PEM: p8)
    }

    func sync(account: Account, progress: @escaping StoreSyncProgress) async throws {
        guard account.platform == platform else {
            throw StoreProviderError.unsupportedOperation(account.platform, "Apple sync")
        }
        let isFirstSync = account.lastSyncedAt == nil
        let client = ASCClient(credentials: try credentials(for: account))
        progress("Loading apps · \(account.name)")
        let summaries = try await client.listApps()
        upsertApps(summaries, account: account, isFirstSync: isFirstSync)
        try? context.save()

        for app in account.apps where app.isTracked {
            await syncApp(app, client: client, isFirstSync: isFirstSync, progress: progress)
        }
        await syncSales(account: account, client: client, progress: progress)
        if settings.fetchAnalytics {
            await syncAnalytics(account: account, client: client, progress: progress)
        }
    }

    func syncBackgroundAlerts(account: Account) async throws {
        guard account.platform == platform else {
            throw StoreProviderError.unsupportedOperation(account.platform, "App Store background alerts")
        }
        let client = ASCClient(credentials: try credentials(for: account))
        let isFirstSync = account.lastSyncedAt == nil
        for app in account.apps where app.isTracked {
            try Task.checkCancellation()
            await syncApp(
                app,
                client: client,
                isFirstSync: isFirstSync,
                progress: { _ in },
                includeMetadata: false
            )
        }
    }

    // MARK: Apps

    private func upsertApps(_ summaries: [AppSummary], account: Account, isFirstSync: Bool) {
        let existing = Dictionary(account.apps.map { ($0.remoteIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        for s in summaries {
            if let app = existing[s.appStoreID] {
                app.name = s.name
                app.bundleID = s.bundleID
                app.sku = s.sku
                app.primaryLocale = s.primaryLocale
            } else {
                let app = TrackedApp(appStoreID: s.appStoreID, bundleID: s.bundleID, name: s.name,
                                     sku: s.sku, account: account, platform: platform)
                app.isNewlyDiscovered = !isFirstSync
                context.insert(app)
                account.apps.append(app)
                if !isFirstSync && settings.notificationsEnabled {
                    notifier.notifyNewApp(app: s.name)
                }
            }
        }
    }

    private func syncApp(
        _ app: TrackedApp,
        client: ASCClient,
        isFirstSync: Bool,
        progress: @escaping Progress,
        includeMetadata: Bool = true
    ) async {
        progress("Syncing · \(app.name)")

        // Version / status
        if let versions = try? await client.appVersions(appID: app.remoteIdentifier), !versions.isEmpty {
            let current = versions.max { ($0.createdDate ?? .distantPast) < ($1.createdDate ?? .distantPast) } ?? versions[0]
            let oldState = app.currentStateRaw
            let newState = current.stateRaw
            app.currentVersionString = current.versionString
            app.currentPlatform = current.platform
            app.statusUpdatedAt = Date()

            // Phased release progress for the current version.
            let oldPhased = app.phasedReleaseState
            let phased = await client.phasedRelease(versionID: current.id)
            app.phasedReleaseState = phased?.state
            app.phasedReleaseDay = phased?.currentDay
            if !isFirstSync, oldPhased == "ACTIVE", phased?.state == "COMPLETE", settings.notificationsEnabled {
                notifier.notify(title: "\(app.name): rollout complete", body: "Your phased release reached 100% of users.")
            }

            if oldState != newState {
                if oldState != nil && !isFirstSync {
                    context.insert(StatusEvent(versionString: current.versionString, fromStateRaw: oldState, toStateRaw: newState, app: app))
                    if settings.notificationsEnabled {
                        notifier.notifyStatusChange(app: app.name, state: AppStoreState(raw: newState))
                    }
                }
                app.currentStateRaw = newState
            }
        }

        guard !Task.isCancelled else { return }
        // Icon
        if app.iconURLString == nil {
            app.iconURLString = await IconService.iconURL(for: app.remoteIdentifier)
        }

        guard !Task.isCancelled else { return }
        // Reviews
        let knownIDs = Set(app.reviews.map(\.remoteIdentifier))
        let existingByID = Dictionary(app.reviews.map { ($0.remoteIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        if let fetched = try? await client.reviews(appID: app.remoteIdentifier, knownIDs: knownIDs) {
            var newOnes: [Review] = []
            for r in fetched {
                if let ex = existingByID[r.id] {
                    ex.responseID = r.responseID
                    ex.responseBody = r.responseBody
                    ex.responseState = r.responseState
                    ex.responseDate = r.responseDate
                } else {
                    let review = Review(id: r.id, rating: r.rating, title: r.title, body: r.body,
                                        reviewer: r.reviewer, territory: r.territory, createdDate: r.createdDate, app: app)
                    review.responseID = r.responseID
                    review.responseBody = r.responseBody
                    review.responseState = r.responseState
                    review.responseDate = r.responseDate
                    review.isRead = app.reviewsBackfilled ? false : true
                    context.insert(review)
                    if app.reviewsBackfilled && !isFirstSync { newOnes.append(review) }
                }
            }
            if !app.reviewsBackfilled { app.reviewsBackfilled = true }

            if settings.notificationsEnabled && !newOnes.isEmpty {
                let rule = app.alertRuleRaw.flatMap(ReviewAlertRule.init(rawValue:)) ?? settings.globalAlertRule
                let alertable = newOnes.filter { rule.allows(rating: $0.rating) }
                for r in alertable.prefix(5) {
                    notifier.notifyNewReview(app: app.name, rating: r.rating, title: r.title, body: r.body)
                }
                if alertable.count > 5 {
                    notifier.notify(title: "\(alertable.count) new reviews · \(app.name)",
                                    body: "Open StoreGauge to triage them.")
                }
            }
        }

        if includeMetadata, !Task.isCancelled {
            await syncMetadata(app, client: client)
        }
        try? context.save()
    }

    // MARK: Metadata (all-locale, throttled)

    private func syncMetadata(_ app: TrackedApp, client: ASCClient) async {
        // One-time historical backfill from past App Store versions (ignores throttle).
        if !app.metadataBackfilled {
            await backfillMetadataHistory(app, client: client)
            app.metadataBackfilled = true
            app.lastMetadataSyncAt = Date()
            try? context.save()
            return
        }
        if let last = app.lastMetadataSyncAt, Date().timeIntervalSince(last) < 6 * 3600 { return }
        let (version, locales) = await client.appMetadata(appID: app.remoteIdentifier, includeScreenshots: true)
        guard !locales.isEmpty else { return }
        app.lastMetadataSyncAt = Date()

        let snapByLocale = Dictionary(app.metadataSnapshots.map { ($0.locale, $0) }, uniquingKeysWith: { a, _ in a })
        var recordedChanges: [(locale: String, field: MetadataField)] = []
        for lm in locales {
            let existing = snapByLocale[lm.locale]
            let snap: MetadataSnapshot
            if let existing { snap = existing } else {
                snap = MetadataSnapshot(appStoreID: app.remoteIdentifier, locale: lm.locale, app: app)
                context.insert(snap)
            }
            let canRecord = existing != nil   // don't record "changes" for a brand-new baseline/locale
            let values: [(MetadataField, String?)] = [
                (.name, lm.name), (.subtitle, lm.subtitle), (.description, lm.description), (.keywords, lm.keywords),
                (.promotionalText, lm.promotionalText), (.whatsNew, lm.whatsNew),
                (.marketingURL, lm.marketingURL), (.supportURL, lm.supportURL), (.screenshots, lm.screenshots),
            ]
            for (field, raw) in values {
                let newV = (raw?.isEmpty == true) ? nil : raw
                let oldV = snap.value(for: field)
                let oldNorm = (oldV?.isEmpty == true) ? nil : oldV
                if newV != oldNorm {
                    if canRecord {
                        context.insert(MetadataChange(locale: lm.locale, field: field, oldValue: oldNorm,
                                                      newValue: newV, versionString: version, app: app))
                        recordedChanges.append((lm.locale, field))
                    }
                    snap.set(newV, for: field)
                }
            }
            snap.updatedAt = Date()
        }
        try? context.save()

        if settings.notificationsEnabled, !recordedChanges.isEmpty {
            let fields = Array(Set(recordedChanges.map(\.field.label))).sorted()
            let localeCount = Set(recordedChanges.map(\.locale)).count
            let fieldSummary = fields.prefix(3).joined(separator: ", ")
            let extra = fields.count > 3 ? " and \(fields.count - 3) more" : ""
            notifier.notify(
                title: "\(app.name): store listing changed",
                body: "\(fieldSummary)\(extra) changed across \(localeCount) \(localeCount == 1 ? "localization" : "localizations").",
                id: "metadata-\(app.id.uuidString)"
            )
        }
    }

    /// Reconstructs the change timeline from past App Store versions, then sets the
    /// current baseline snapshot. Text fields only (name/subtitle/screenshots have
    /// no version history in the API, so those are captured as the baseline).
    private func backfillMetadataHistory(_ app: TrackedApp, client: ASCClient) async {
        func norm(_ s: String?) -> String? { (s?.isEmpty == true) ? nil : s }
        let textFields: [MetadataField] = [.description, .keywords, .promotionalText, .whatsNew, .marketingURL, .supportURL]

        // 1. Diff consecutive versions per locale, dating each change at the version's release.
        let history = await client.versionHistory(appID: app.remoteIdentifier)
        var previous: [String: LocaleMetadata] = [:]
        for vm in history {
            for (locale, current) in vm.localizations {
                if let old = previous[locale] {
                    for field in textFields {
                        let newV = norm(current.value(for: field))
                        let oldV = norm(old.value(for: field))
                        if newV != oldV {
                            context.insert(MetadataChange(date: vm.date, locale: locale, field: field,
                                                          oldValue: oldV, newValue: newV, versionString: vm.version, app: app))
                        }
                    }
                }
                previous[locale] = current
            }
        }

        // 2. Baseline snapshot from current metadata (name/subtitle/screenshots + latest text).
        let (_, currentLocales) = await client.appMetadata(appID: app.remoteIdentifier, includeScreenshots: true)
        let snapByLocale = Dictionary(app.metadataSnapshots.map { ($0.locale, $0) }, uniquingKeysWith: { a, _ in a })
        for lm in currentLocales {
            let snap: MetadataSnapshot
            if let existing = snapByLocale[lm.locale] { snap = existing } else {
                snap = MetadataSnapshot(appStoreID: app.remoteIdentifier, locale: lm.locale, app: app)
                context.insert(snap)
            }
            for field in MetadataField.allCases { snap.set(norm(lm.value(for: field)), for: field) }
            snap.updatedAt = Date()
        }
        try? context.save()
    }

    // MARK: Sales / income

    private func syncSales(account: Account, client: ASCClient, progress: @escaping Progress) async {
        guard let vendor = account.vendorNumber?.trimmingCharacters(in: .whitespaces), !vendor.isEmpty else { return }
        let apps = account.apps.filter(\.isTracked)
        guard !apps.isEmpty else { return }
        let appByID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let byAppleID = Dictionary(apps.map { ($0.remoteIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        let bySKU = Dictionary(apps.compactMap { app in app.sku.map { ($0, app) } }, uniquingKeysWith: { a, _ in a })

        // App rows match by Apple Identifier; IAP/subscription rows carry the IAP's
        // own id and link to the parent app via Parent Identifier (== app SKU).
        func resolve(_ row: SalesRow) -> TrackedApp? {
            if let a = byAppleID[row.appleID] { return a }
            if !row.parentIdentifier.isEmpty, let a = bySKU[row.parentIdentifier] { return a }
            if !row.sku.isEmpty, let a = bySKU[row.sku] { return a }
            return nil
        }

        let days = (1...max(1, settings.salesHistoryDays)).map { Date.daysAgo($0).startOfDayUTC }
        var toFetch: [Date] = []
        for (offset, day) in days.enumerated() {
            if offset < 5 { toFetch.append(day); continue } // always refresh the last 5 days (Apple revises recent data)
            let dayStr = DayFormatter.string(from: day)
            let exists = apps.contains { app in
                app.metrics.contains { ($0.kindRaw == MetricKind.units.rawValue || $0.kindRaw == MetricKind.proceeds.rawValue) && DayFormatter.string(from: $0.date) == dayStr }
            }
            if !exists { toFetch.append(day) }
        }

        for day in toFetch {
            progress("Sales · \(DayFormatter.string(from: day))")
            let tsv: String?
            do { tsv = try await client.salesReportTSV(vendorNumber: vendor, date: day) }
            catch { continue }
            guard let tsv else { continue }

            var unitsByApp: [UUID: Int] = [:]
            var updatesByApp: [UUID: Int] = [:]
            var proceedsByApp: [UUID: [String: Double]] = [:]
            let rows = await Task.detached(priority: .utility) { SalesReport.parseRows(tsv: tsv) }.value
            for row in rows {
                guard let app = resolve(row) else { continue }
                if !row.isIAP {
                    unitsByApp[app.id, default: 0] += row.units   // downloads = app rows only
                    if row.productType.uppercased().hasPrefix("7") { updatesByApp[app.id, default: 0] += row.units }
                }
                if row.proceeds != 0 { proceedsByApp[app.id, default: [:]][row.currency, default: 0] += row.proceeds }
            }
            for (appID, units) in unitsByApp {
                if let app = appByID[appID] {
                    upsertMetric(app: app, kind: .units, day: day, value: Double(units), currency: nil, source: .sales)
                    upsertMetric(app: app, kind: .updates, day: day, value: Double(updatesByApp[appID] ?? 0), currency: nil, source: .sales)
                }
            }
            for (appID, byCurrency) in proceedsByApp {
                guard let app = appByID[appID] else { continue }
                for (currency, amount) in byCurrency {
                    upsertMetric(app: app, kind: .proceeds, day: day, value: amount, currency: currency, source: .sales)
                }
            }
            try? context.save()
        }
    }

    // MARK: Analytics (optional / best-effort)

    private func syncAnalytics(account: Account, client: ASCClient, progress: @escaping Progress) async {
        let service = AnalyticsService(client: client)
        for app in account.apps where app.isTracked {
            progress("Analytics · \(app.name)")
            guard let points = try? await service.recentMetrics(appID: app.remoteIdentifier) else { continue }
            for p in points {
                upsertMetric(app: app, kind: p.kind, day: p.date.startOfDayUTC, value: p.value, currency: nil, source: .analytics)
            }
            try? context.save()
        }
    }

    // MARK: Metric upsert

    private func upsertMetric(app: TrackedApp, kind: MetricKind, day: Date, value: Double, currency: String?, source: MetricSource) {
        let key = MetricPoint.makeKey(app: app, kind: kind, day: day, currency: currency)
        let descriptor = FetchDescriptor<MetricPoint>(predicate: #Predicate { $0.key == key })
        if let existing = try? context.fetch(descriptor).first {
            existing.value = value
        } else {
            context.insert(MetricPoint(key: key, date: day, kind: kind, value: value, currency: currency, source: source, app: app))
        }
    }
}

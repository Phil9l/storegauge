//
//  AppModel.swift
//  StoreGauge
//
//  App-wide coordinator injected into the SwiftUI environment. Owns the model
//  container, settings, sync engine and poller, and exposes global UI state.
//

import Foundation
import SwiftData
#if os(macOS)
import ServiceManagement
import AppKit
#endif

enum StoreGaugeDestination: Equatable {
    case overview
    case reviews
    case app(UUID)
}

struct StoreGaugeNavigationRequest: Equatable {
    let id = UUID()
    let destination: StoreGaugeDestination
}

@MainActor
@Observable
final class AppModel {
    let container: ModelContainer
    let context: ModelContext
    let settings = AppSettings()
    let fx = FXService.shared
    let notifier = Notifier()
    let engine: SyncEngine

    @ObservationIgnored private lazy var poller: Poller = Poller(
        intervalMinutes: { [weak self] in self?.settings.pollIntervalMinutes ?? 30 },
        action: { [weak self] in await self?.syncNow() }
    )

    // Global UI state
    var isSyncing = false
    var syncActivity = ""
    var untriagedCount = 0
    var lastSyncError: String?
    var lastSyncedAt: Date?
    var hasBootstrapped = false
    var navigationRequest: StoreGaugeNavigationRequest?

    // Income deep-dive cache (survives tab switches; refreshed after sync)
    var incomeBreakdown: IncomeBreakdown?
    var incomeLoading = false
    var incomeProgress: Double = 0
    @ObservationIgnored private var incomeCacheKey: String?
    @ObservationIgnored private var incomeLoadingKey: String?
    @ObservationIgnored private var incomeTask: Task<Void, Never>?

    // Subscriptions cache
    var subscriptionData: SubscriptionData?
    var subLoading = false
    var subProgress: Double = 0
    @ObservationIgnored private var subCacheKey: String?
    @ObservationIgnored private var subLoadingKey: String?
    @ObservationIgnored private var subTask: Task<Void, Never>?

    init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
        self.engine = SyncEngine(context: context, settings: settings, notifier: notifier)
    }

    // MARK: Lifecycle

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        #if DEBUG
        seedFromEnvironmentIfNeeded()
        #endif
        migrateStoreProviderDataIfNeeded()
        migrateSalesIfNeeded()
        applyActivationPolicy()
        await notifier.refreshAuthorizationStatus()
        #if os(macOS)
        if settings.notificationsEnabled { await notifier.requestAuthorization() }
        #else
        if settings.notificationsEnabled && !notifier.isAuthorized {
            settings.notificationsEnabled = false
        }
        #endif
        if accounts().contains(where: { !$0.isDemo }) {
            await fx.refreshIfNeeded()
        }
        recomputeBadges()
        if !accounts().isEmpty {
            await syncNow()
        }
        poller.start()
    }

    #if DEBUG
    /// Developer convenience: seed one account from environment variables so the
    /// app can be launched against real data without the file picker. Enabled
    /// only when STOREGAUGE_DEV_SEED=1. Never compiled into release builds.
    private func seedFromEnvironmentIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        guard env["STOREGAUGE_DEV_SEED"] == "1", accounts().isEmpty,
              let issuer = env["ASC_ISSUER"], let keyID = env["ASC_KEY_ID"], let p8 = env["ASC_P8"]
        else { return }
        let account = Account(name: env["ASC_NAME"] ?? "Developer", issuerID: issuer, keyID: keyID,
                              vendorNumber: env["ASC_VENDOR"])
        _ = try? Keychain.save(p8, account: account.id.uuidString)
        context.insert(account)
        try? context.save()
    }
    #endif

    /// Namespaces legacy Apple-only identities before another provider can write
    /// records with ids that are only unique inside its own app/account.
    private func migrateStoreProviderDataIfNeeded() {
        let migrationKey = "storeProviderIdentityV1Done"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        for account in accounts where StorePlatform(rawValue: account.platformRaw) == nil {
            account.platform = .appleAppStore
        }

        let apps = (try? context.fetch(FetchDescriptor<TrackedApp>())) ?? []
        for app in apps where StorePlatform(rawValue: app.platformRaw) == nil {
            app.platform = app.account?.platform ?? .appleAppStore
        }

        let reviews = (try? context.fetch(FetchDescriptor<Review>())) ?? []
        for review in reviews where review.remoteID == nil {
            let legacyID = review.id
            review.remoteID = legacyID
            review.id = Review.makeLocalID(app: review.app, remoteIdentifier: legacyID)
        }

        let metrics = (try? context.fetch(FetchDescriptor<MetricPoint>())) ?? []
        for metric in metrics {
            guard let app = metric.app else { continue }
            metric.key = MetricPoint.makeKey(
                app: app,
                kind: metric.kind,
                day: metric.date,
                currency: metric.currency
            )
        }

        let snapshots = (try? context.fetch(FetchDescriptor<MetadataSnapshot>())) ?? []
        for snapshot in snapshots {
            guard let app = snapshot.app else { continue }
            snapshot.key = "\(app.storageIdentity)|metadata|\(snapshot.locale)"
        }

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: migrationKey)
        } catch {
            // Leave the flag unset so the migration is retried after the cause is fixed.
        }
    }

    func restartPoller() { poller.start() }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "storegauge" else { return }
        let destination: StoreGaugeDestination
        switch url.host {
        case "reviews":
            destination = .reviews
        case "app":
            guard let rawID = url.pathComponents.dropFirst().first,
                  let appID = UUID(uuidString: rawID) else { return }
            destination = .app(appID)
        default:
            destination = .overview
        }
        navigationRequest = StoreGaugeNavigationRequest(destination: destination)
        #if os(macOS)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        #endif
    }

    /// One-time cleanup: older builds dropped IAP/subscription proceeds. Clear
    /// sales-sourced metrics so the next sync backfills them with the fixed parser.
    private func migrateSalesIfNeeded() {
        let key = "salesReparseV3Done"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let salesRaw = MetricSource.sales.rawValue
        let descriptor = FetchDescriptor<MetricPoint>(predicate: #Predicate { $0.sourceRaw == salesRaw })
        if let old = try? context.fetch(descriptor) {
            for m in old { context.delete(m) }
            try? context.save()
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: Data access

    func accounts() -> [Account] {
        let descriptor = FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func allApps() -> [TrackedApp] {
        (try? context.fetch(FetchDescriptor<TrackedApp>())) ?? []
    }

    // MARK: Sync

    func syncNow() async {
        guard !isSyncing else { return }
        isSyncing = true
        syncActivity = "Starting…"
        if accounts().contains(where: { !$0.isDemo }) {
            await fx.refreshIfNeeded()
        }
        await engine.syncAll { [weak self] activity in
            self?.syncActivity = activity
        }
        isSyncing = false
        syncActivity = ""
        refreshSyncStatus()
        recomputeBadges()
        invalidateIncome()
        invalidateSubscriptions()
        checkAnomalies()
    }

    // MARK: Anomaly alerts

    /// After a sync, flag apps whose downloads or proceeds swung sharply week-over-week.
    /// Throttled to ~once per day so a sharp week doesn't re-alert on every poll.
    func checkAnomalies() {
        guard settings.anomalyAlertsEnabled, settings.notificationsEnabled else { return }
        let key = "lastAnomalyCheck"
        if let last = UserDefaults.standard.object(forKey: key) as? Date,
           Date().timeIntervalSince(last) < 20 * 3600 { return }

        let threshold = Double(settings.anomalyThresholdPercent) / 100.0
        for app in allApps() where app.isSelected && !app.isArchived {
            let agg = MetricsAggregator(apps: [app], fx: fx, currency: settings.displayCurrency)
            // Downloads — require a non-trivial base week so tiny numbers don't spam.
            if let w = agg.weekOverWeekDownloads(), w.previous >= 30 {
                let f = (w.recent - w.previous) / w.previous
                if abs(f) >= threshold {
                    notifier.notifyAnomaly(app: app.name, metric: "Downloads", fraction: f,
                                           from: Format.int(w.previous), to: Format.int(w.recent))
                }
            }
            // Proceeds — require at least a little revenue to compare against.
            if let w = agg.weekOverWeekSales(.proceeds), w.previous >= 10 {
                let f = (w.recent - w.previous) / w.previous
                if abs(f) >= threshold {
                    notifier.notifyAnomaly(app: app.name, metric: "Proceeds", fraction: f,
                                           from: Format.currency(w.previous, code: settings.displayCurrency, compact: true),
                                           to: Format.currency(w.recent, code: settings.displayCurrency, compact: true))
                }
            }
        }
        UserDefaults.standard.set(Date(), forKey: key)
    }

    func syncAccount(_ account: Account, waitingForActiveSync: Bool = false) async {
        if waitingForActiveSync {
            while isSyncing {
                if Task.isCancelled { return }
                try? await Task.sleep(for: .milliseconds(100))
            }
        } else {
            guard !isSyncing else { return }
        }
        isSyncing = true
        await engine.syncAccount(account) { [weak self] activity in
            self?.syncActivity = activity
        }
        isSyncing = false
        syncActivity = ""
        refreshSyncStatus()
        recomputeBadges()
    }

    func refreshAllData(for account: Account) async {
        guard !isSyncing else { return }
        account.lastGoogleFinancialSyncAt = nil
        account.lastGoogleStatisticsSyncAt = nil
        account.lastGoogleVitalsSyncAt = nil
        for app in account.apps {
            app.lastMetadataSyncAt = nil
        }
        try? context.save()
        await syncAccount(account)
    }

    func refreshSyncStatus() {
        let currentAccounts = accounts()
        lastSyncedAt = currentAccounts.compactMap(\.lastSyncedAt).max()
        lastSyncError = currentAccounts.compactMap(\.lastSyncError).first
    }

    // MARK: Reviews

    func markRead(_ reviews: [Review], read: Bool = true) {
        for r in reviews { r.isRead = read }
        try? context.save()
        recomputeBadges()
    }

    func acknowledge(_ reviews: [Review], _ ack: Bool = true) {
        for r in reviews {
            r.isAcknowledged = ack
            if ack { r.isRead = true }
        }
        try? context.save()
        recomputeBadges()
    }

    private func appleClient(for review: Review) throws -> ASCClient {
        guard let app = review.app, let account = app.account else {
            throw ASCError.message("This review isn't linked to an account.")
        }
        guard app.platform == .appleAppStore else {
            throw StoreProviderError.unsupportedOperation(app.platform, "Review responses")
        }
        return ASCClient(credentials: try engine.credentials(for: account))
    }

    private func googleClient(for review: Review) throws -> GooglePlayClient {
        guard let app = review.app, let account = app.account else {
            throw GooglePlayError.message("This review isn't linked to an account.")
        }
        guard app.platform == .googlePlay else {
            throw StoreProviderError.unsupportedOperation(app.platform, "Google Play review responses")
        }
        return GooglePlayClient(credentials: try engine.googleCredentials(for: account))
    }

    func editResponse(to review: Review, body: String) async throws {
        guard let app = review.app else {
            throw GooglePlayError.message("This review isn't linked to an app.")
        }
        if app.account?.isDemo == true {
            review.responseID = review.responseID ?? "demo-response-\(review.remoteIdentifier)"
            review.responseBody = body
            review.responseDate = Date()
            review.responseState = "PUBLISHED"
            review.isRead = true
            try? context.save()
            recomputeBadges()
            return
        }
        switch app.platform {
        case .appleAppStore:
            guard let id = review.responseID else {
                try await reply(to: review, body: body); return
            }
            try await appleClient(for: review).editReviewResponse(responseID: id, body: body)
            review.responseBody = body
            review.responseDate = Date()
        case .googlePlay:
            let result = try await googleClient(for: review).reply(
                packageName: app.remoteIdentifier,
                reviewID: review.remoteIdentifier,
                body: body
            )
            review.responseID = review.remoteIdentifier
            review.responseBody = result.body
            review.responseDate = result.editedAt
            review.responseState = "PUBLISHED"
        }
        try? context.save()
    }

    func deleteResponse(from review: Review) async throws {
        if review.app?.account?.isDemo == true {
            review.responseID = nil
            review.responseBody = nil
            review.responseState = nil
            review.responseDate = nil
            try? context.save()
            recomputeBadges()
            return
        }
        guard let platform = review.app?.platform else {
            throw GooglePlayError.message("This review isn't linked to an app.")
        }
        guard platform == .appleAppStore else {
            throw StoreProviderError.unsupportedOperation(.googlePlay, "Deleting review replies")
        }
        guard let id = review.responseID else { return }
        try await appleClient(for: review).deleteReviewResponse(responseID: id)
        review.responseID = nil
        review.responseBody = nil
        review.responseState = nil
        review.responseDate = nil
        try? context.save()
        recomputeBadges()
    }

    func builds(for app: TrackedApp) async -> [BuildInfo] {
        guard app.platform == .appleAppStore, app.capabilities.contains(.builds),
              let account = app.account, let creds = try? engine.credentials(for: account) else { return [] }
        let client = ASCClient(credentials: creds)
        return (try? await client.latestBuilds(appID: app.remoteIdentifier)) ?? []
    }

    func screenshots(for app: TrackedApp, locale: String) async -> [ScreenshotGroup] {
        guard app.platform == .appleAppStore, app.capabilities.contains(.metadata),
              let account = app.account, let creds = try? engine.credentials(for: account) else { return [] }
        return await ASCClient(credentials: creds).screenshots(appID: app.remoteIdentifier, locale: locale)
    }

    func addAnnotation(date: Date, note: String, category: AnnotationCategory = .note, to app: TrackedApp?) {
        context.insert(ChartAnnotation(date: date.startOfDayUTC, note: note, category: category, app: app))
        try? context.save()
    }

    func updateAnnotation(_ annotation: ChartAnnotation, date: Date, note: String, category: AnnotationCategory) {
        annotation.date = date.startOfDayUTC
        annotation.note = note
        annotation.category = category
        try? context.save()
    }

    func deleteAnnotation(_ annotation: ChartAnnotation) {
        context.delete(annotation)
        try? context.save()
    }

    struct TestFlightData: Sendable {
        var groups: [BetaGroupInfo] = []
        var feedback: [BetaFeedbackInfo] = []
        var isEmpty: Bool { groups.isEmpty && feedback.isEmpty }
    }

    func loadTestFlight(for app: TrackedApp) async -> TestFlightData {
        guard app.platform == .appleAppStore, app.capabilities.contains(.betaTesting),
              let account = app.account, let creds = try? engine.credentials(for: account) else { return TestFlightData() }
        let client = ASCClient(credentials: creds)
        let groups = (try? await client.betaGroups(appID: app.remoteIdentifier)) ?? []
        let feedback = (try? await client.betaFeedback(appID: app.remoteIdentifier)) ?? []
        return TestFlightData(groups: groups, feedback: feedback)
    }

    // MARK: Income deep-dive

    struct IncomeBreakdown: Sendable {
        struct AppAgg: Sendable {
            var total = 0.0
            var appProceeds = 0.0
            var iap = 0.0
            var refund = 0.0
            var refundUnits = 0
            var byCountry: [String: Double] = [:]
            var byDay: [Date: Double] = [:]      // proceeds per day (display currency)
        }
        var byApp: [String: AppAgg] = [:]     // keyed by TrackedApp UUID string
        var currency = "USD"
        var hasVendor = true
        var days = 30

        /// Aggregate for one app, or all apps merged when `appID` is nil.
        func scoped(to appID: String?) -> AppAgg {
            if let appID { return byApp[appID] ?? AppAgg() }
            var m = AppAgg()
            for a in byApp.values {
                m.total += a.total; m.appProceeds += a.appProceeds; m.iap += a.iap
                m.refund += a.refund; m.refundUnits += a.refundUnits
                for (c, v) in a.byCountry { m.byCountry[c, default: 0] += v }
                for (d, v) in a.byDay { m.byDay[d, default: 0] += v }
            }
            return m
        }
    }

    /// Loads the income breakdown, caching by (days, currency). Repeated tab
    /// visits reuse the cache; a sync or currency change invalidates it.
    /// Model-owned load: not tied to any view's lifecycle, so switching tabs can't
    /// cancel it or cache a partial result.
    func ensureIncome(days: Int, force: Bool = false) {
        let key = "\(days)|\(settings.displayCurrency)"
        if !force, incomeCacheKey == key, incomeBreakdown != nil { return }
        if !force, incomeLoading, incomeLoadingKey == key { return }
        incomeTask?.cancel()
        incomeLoading = true
        incomeProgress = 0
        incomeLoadingKey = key
        incomeTask = Task { [weak self] in
            guard let self else { return }
            let b = await self.loadIncomeBreakdown(days: days)
            if Task.isCancelled { return }   // superseded by a newer request
            self.incomeBreakdown = b
            self.incomeCacheKey = b.hasVendor ? key : nil   // don't cache the "no vendor" empty state
            self.incomeLoading = false
            self.incomeLoadingKey = nil
        }
    }

    func invalidateIncome() { incomeCacheKey = nil }

    /// Fetches and parses the last `days` daily Sales reports into a per-app breakdown.
    /// One API call per day per account with a vendor number.
    private func loadIncomeBreakdown(days: Int) async -> IncomeBreakdown {
        var b = IncomeBreakdown()
        b.currency = settings.displayCurrency
        let appleAccounts = accounts().filter {
            $0.platform == .appleAppStore &&
                ($0.vendorNumber?.trimmingCharacters(in: .whitespaces).isEmpty == false)
        }
        let demoAccounts = appleAccounts.filter(\.isDemo)
        let accts = appleAccounts.filter { !$0.isDemo }
        guard !accts.isEmpty || !demoAccounts.isEmpty else { b.hasVendor = false; return b }
        if !accts.isEmpty { await fx.refreshIfNeeded() }
        let cur = settings.displayCurrency

        let cutoff = Date.daysAgo(days).startOfDayUTC
        for app in demoAccounts.flatMap(\.apps).filter({ !$0.isArchived }) {
            var agg = IncomeBreakdown.AppAgg()
            for point in app.metrics where point.kind == .proceeds && point.date >= cutoff {
                let amount = fx.convert(point.value, from: point.currency ?? "USD", to: cur) ?? point.value
                agg.total += amount
                agg.appProceeds += amount * 0.38
                agg.iap += amount * 0.62
                agg.byDay[point.date.startOfDayUTC, default: 0] += amount
            }
            agg.refund = -agg.total * 0.025
            agg.refundUnits = -max(1, Int(agg.total / 80))
            agg.byCountry = ["US": agg.total * 0.48, "DE": agg.total * 0.19,
                             "GB": agg.total * 0.14, "JP": agg.total * 0.11,
                             "CA": agg.total * 0.08]
            b.byApp[app.id.uuidString] = agg
        }

        // Resolver so IAP/subscription rows roll up to the parent app.
        let apps = accts.flatMap(\.apps).filter { !$0.isArchived }
        let appByAppleID = Dictionary(apps.map { ($0.remoteIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        let appBySKU = Dictionary(apps.compactMap { a in a.sku.map { ($0, a) } }, uniquingKeysWith: { a, _ in a })
        func resolveApp(_ row: SalesRow) -> TrackedApp? {
            if let app = appByAppleID[row.appleID] { return app }
            if !row.parentIdentifier.isEmpty, let app = appBySKU[row.parentIdentifier] { return app }
            if !row.sku.isEmpty, let app = appBySKU[row.sku] { return app }
            return nil
        }

        b.days = days
        let totalSteps = max(1, accts.count * max(1, days))
        var step = 0
        for account in accts {
            guard let vendor = account.vendorNumber, let creds = try? engine.credentials(for: account) else { continue }
            let client = ASCClient(credentials: creds)
            for offset in 1...max(1, days) {
                let day = Date.daysAgo(offset).startOfDayUTC
                step += 1
                incomeProgress = Double(step) / Double(totalSteps)
                let tsv: String?
                do { tsv = try await client.salesReportTSV(vendorNumber: vendor, date: day) } catch { continue }
                guard let tsv else { continue }
                let rows = await Task.detached(priority: .utility) { SalesReport.parseRows(tsv: tsv) }.value
                for row in rows {
                    guard let app = resolveApp(row) else { continue }
                    let conv = fx.convert(row.proceeds, from: row.currency, to: cur) ?? (row.currency == cur ? row.proceeds : 0)
                    let id = app.id.uuidString
                    var agg = b.byApp[id] ?? IncomeBreakdown.AppAgg()
                    agg.total += conv
                    if row.isIAP { agg.iap += conv } else { agg.appProceeds += conv }
                    if row.isRefund { agg.refund += conv; agg.refundUnits += row.units }
                    if !row.country.isEmpty { agg.byCountry[row.country, default: 0] += conv }
                    agg.byDay[day, default: 0] += conv
                    b.byApp[id] = agg
                }
            }
        }
        return b
    }

    // MARK: Subscriptions

    struct SubscriptionData: Sendable {
        struct SubAgg: Sendable {
            var name = ""
            var appID = ""              // TrackedApp UUID string
            var active = 0
            var paid = 0
            var trials = 0
            var mrr = 0.0
        }
        var currency = "USD"
        var hasVendor = true
        var totalActive = 0
        var totalPaid = 0
        var totalTrials = 0
        var mrr = 0.0
        var bySubscription: [String: SubAgg] = [:]   // keyed by subscription Apple id
        var byCountry: [String: Int] = [:]
        var trend: [DatedValue] = []
        var snapshotDate: Date?
        var events: [String: Int] = [:]   // category (New/Cancelled/Renewals/…) -> quantity over range
    }

    func ensureSubscriptions(days: Int, force: Bool = false) {
        let key = "\(days)|\(settings.displayCurrency)"
        if !force, subCacheKey == key, subscriptionData != nil { return }
        if !force, subLoading, subLoadingKey == key { return }
        subTask?.cancel()
        subLoading = true
        subProgress = 0
        subLoadingKey = key
        subTask = Task { [weak self] in
            guard let self else { return }
            let d = await self.loadSubscriptions(days: days)
            if Task.isCancelled { return }
            self.subscriptionData = d
            self.subCacheKey = d.hasVendor ? key : nil
            self.subLoading = false
            self.subLoadingKey = nil
        }
    }

    func invalidateSubscriptions() { subCacheKey = nil }

    /// The daily SUBSCRIPTION report is a snapshot of currently-active subscriptions.
    /// We take the most recent day per account as "current" and build an active-count trend.
    private func loadSubscriptions(days: Int) async -> SubscriptionData {
        var d = SubscriptionData()
        d.currency = settings.displayCurrency
        let appleAccounts = accounts().filter {
            $0.platform == .appleAppStore &&
                ($0.vendorNumber?.trimmingCharacters(in: .whitespaces).isEmpty == false)
        }
        let demoAccounts = appleAccounts.filter(\.isDemo)
        let accts = appleAccounts.filter { !$0.isDemo }
        guard !accts.isEmpty || !demoAccounts.isEmpty else { d.hasVendor = false; return d }
        if !accts.isEmpty { await fx.refreshIfNeeded() }
        let cur = settings.displayCurrency

        var trendByDay: [Date: Int] = [:]
        for (accountIndex, account) in demoAccounts.enumerated() {
            for (appIndex, app) in account.apps.filter({ !$0.isArchived }).enumerated() {
                let active = appIndex == 0 ? 184 : 67
                let paid = active - (appIndex == 0 ? 23 : 9)
                let trials = active - paid
                let mrr = Double(paid) * (appIndex == 0 ? 4.49 : 2.99)
                let key = "\(account.id.uuidString)|demo-pro-\(appIndex)"
                var sub = SubscriptionData.SubAgg()
                sub.name = appIndex == 0 ? "Pro Monthly" : "Plus Monthly"
                sub.appID = app.id.uuidString
                sub.active = active
                sub.paid = paid
                sub.trials = trials
                sub.mrr = mrr
                d.bySubscription[key] = sub
                d.totalActive += active
                d.totalPaid += paid
                d.totalTrials += trials
                d.mrr += mrr
                d.byCountry["US", default: 0] += Int(Double(active) * 0.47)
                d.byCountry["DE", default: 0] += Int(Double(active) * 0.21)
                d.byCountry["GB", default: 0] += Int(Double(active) * 0.17)
                d.byCountry["CA", default: 0] += Int(Double(active) * 0.15)
                for offset in 1...max(1, days) {
                    let variation = Int(sin(Double(offset + accountIndex * 3 + appIndex) / 5) * 5)
                    trendByDay[Date.daysAgo(offset).startOfDayUTC, default: 0] += active - variation
                }
            }
        }
        if !demoAccounts.isEmpty {
            d.snapshotDate = Date.daysAgo(1).startOfDayUTC
            d.events["New"] = 28
            d.events["Renewals"] = 146
            d.events["Trial→Paid"] = 17
            d.events["Cancelled"] = 11
            d.events["Refunds"] = 3
        }
        let totalSteps = max(1, accts.count * max(1, days))
        var step = 0
        for account in accts {
            guard let vendor = account.vendorNumber, let creds = try? engine.credentials(for: account) else { continue }
            let client = ASCClient(credentials: creds)
            let appsByRemoteID = Dictionary(
                account.apps.filter { !$0.isArchived }.map { ($0.remoteIdentifier, $0) },
                uniquingKeysWith: { a, _ in a }
            )
            var currentSet = false
            for offset in 1...max(1, days) {
                let day = Date.daysAgo(offset).startOfDayUTC
                step += 1
                subProgress = Double(step) / Double(totalSteps)
                // Subscription events (flow: subscribe/cancel/renew/refund) — aggregated over the whole range.
                if let etsv = try? await client.subscriptionEventReportTSV(vendorNumber: vendor, date: day) {
                    let events = await Task.detached(priority: .utility) { SubscriptionReport.parseEvents(tsv: etsv) }.value
                    for r in events where appsByRemoteID[r.appAppleID] != nil {
                        d.events[r.category, default: 0] += r.quantity
                    }
                }
                let tsv: String?
                do { tsv = try await client.subscriptionReportTSV(vendorNumber: vendor, date: day) } catch { continue }
                guard let tsv else { continue }
                let rows = await Task.detached(priority: .utility) { SubscriptionReport.parseRows(tsv: tsv) }.value
                let visibleRows = rows.filter { appsByRemoteID[$0.appAppleID] != nil }
                trendByDay[day, default: 0] += visibleRows.reduce(0) { $0 + $1.totalActive }

                if !currentSet {   // most recent day for this account
                    currentSet = true
                    if d.snapshotDate == nil || day > d.snapshotDate! { d.snapshotDate = day }
                    for r in visibleRows {
                        let mrrRow = Double(r.paidActive) * (fx.convert(r.monthlyProceeds, from: r.proceedsCurrency, to: cur) ?? r.monthlyProceeds)
                        d.totalActive += r.totalActive
                        d.totalPaid += r.paidActive
                        d.totalTrials += r.activeTrial
                        d.mrr += mrrRow
                        let subscriptionKey = "\(account.id.uuidString)|\(r.subscriptionAppleID)"
                        var agg = d.bySubscription[subscriptionKey] ?? .init()
                        agg.name = r.subscriptionName
                        agg.appID = appsByRemoteID[r.appAppleID]?.id.uuidString ?? ""
                        agg.active += r.totalActive
                        agg.paid += r.paidActive
                        agg.trials += r.activeTrial
                        agg.mrr += mrrRow
                        d.bySubscription[subscriptionKey] = agg
                        if !r.country.isEmpty { d.byCountry[r.country, default: 0] += r.totalActive }
                    }
                }
            }
        }
        d.trend = trendByDay.sorted { $0.key < $1.key }.map { DatedValue(date: $0.key, value: Double($0.value)) }
        return d
    }

    func reply(to review: Review, body: String) async throws {
        guard let app = review.app else {
            throw GooglePlayError.message("This review isn't linked to an app.")
        }
        if app.account?.isDemo == true {
            review.responseID = "demo-response-\(review.remoteIdentifier)"
            review.responseBody = body
            review.responseDate = Date()
            review.responseState = "PUBLISHED"
            review.isRead = true
            review.isAcknowledged = false
            try? context.save()
            recomputeBadges()
            return
        }
        switch app.platform {
        case .appleAppStore:
            review.responseID = try await appleClient(for: review).replyToReview(
                reviewID: review.remoteIdentifier,
                body: body
            )
            review.responseBody = body
            review.responseDate = Date()
        case .googlePlay:
            let result = try await googleClient(for: review).reply(
                packageName: app.remoteIdentifier,
                reviewID: review.remoteIdentifier,
                body: body
            )
            review.responseID = review.remoteIdentifier
            review.responseBody = result.body
            review.responseDate = result.editedAt
        }
        review.responseState = "PUBLISHED"
        review.isRead = true
        review.isAcknowledged = false
        try? context.save()
        recomputeBadges()
    }

    /// The actionable queue: reviews needing a reply (unanswered & unacknowledged)
    /// across the selected apps.
    func recomputeBadges() {
        let descriptor = FetchDescriptor<Review>(predicate: #Predicate { $0.responseBody == nil && !$0.isAcknowledged })
        let pending = (try? context.fetch(descriptor)) ?? []
        untriagedCount = pending.filter {
            $0.app?.isSelected == true && $0.app?.isArchived != true
        }.count
        WidgetSnapshotExporter.publish(context: context, fx: fx, currency: settings.displayCurrency)
        publishMCPData()
        #if os(macOS)
        NSApp.dockTile.badgeLabel = untriagedCount > 0 ? "\(untriagedCount)" : nil
        #endif
    }

    func publishMCPData() {
        MCPSnapshotExporter.publish(context: context, settings: settings, fx: fx)
    }

    // MARK: System integration

    func applyActivationPolicy() {
        #if os(macOS)
        NSApp.setActivationPolicy(settings.menuBarOnly ? .accessory : .regular)
        if !settings.menuBarOnly { NSApp.activate(ignoringOtherApps: true) }
        #endif
    }

    func updateLoginItem() {
        #if os(macOS)
        do {
            if settings.launchAtLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            // Non-fatal; the toggle simply won't take effect.
        }
        #endif
    }
}

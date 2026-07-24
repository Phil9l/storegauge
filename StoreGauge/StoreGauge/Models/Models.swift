//
//  Models.swift
//  StoreGauge
//
//  SwiftData persistent models. The store is a local SQLite database managed by
//  SwiftData. Secrets (the .p8 private key) are never stored here — they live in
//  the Keychain, keyed by the Account id.
//

import Foundation
import SwiftData

// MARK: - Account

/// One store account. Apple-specific fields remain persisted for a safe
/// lightweight migration; other providers keep their secret payload in Keychain.
@Model
final class Account {
    static let demoMarker = "__STOREGAUGE_DEMO__"

    @Attribute(.unique) var id: UUID
    var name: String
    var platformRaw: String = StorePlatform.appleAppStore.rawValue
    /// Provider account/project id when one is needed (for example Google Cloud).
    var externalAccountID: String?
    // App Store Connect configuration (unused by non-Apple providers).
    var issuerID: String
    var keyID: String
    /// Vendor number for Sales & Trends reports (optional; needed for income).
    var vendorNumber: String?
    /// Private Google Play report bucket (`pubsite_prod_rev_…`) for statistics and finance.
    var googleFinancialBucket: String?
    /// Avoids repeatedly downloading monthly Google reports during background polls.
    var lastGoogleFinancialSyncAt: Date?
    /// Statistics exports change daily but are several days behind.
    var lastGoogleStatisticsSyncAt: Date?
    /// Android vitals are queried directly and do not need the report bucket.
    var lastGoogleVitalsSyncAt: Date?
    var createdAt: Date
    var lastSyncedAt: Date?
    /// Most recent sync attempt, including attempts that only partially succeeded.
    var lastSyncAttemptAt: Date?
    var lastSyncDuration: Double?
    var lastSyncErrorAt: Date?
    var lastSyncError: String?
    var sortIndex: Int

    @Relationship(deleteRule: .cascade, inverse: \TrackedApp.account)
    var apps: [TrackedApp] = []

    init(id: UUID = UUID(), name: String, issuerID: String, keyID: String,
         vendorNumber: String? = nil, sortIndex: Int = 0,
         platform: StorePlatform = .appleAppStore, externalAccountID: String? = nil,
         googleFinancialBucket: String? = nil) {
        self.id = id
        self.name = name
        self.platformRaw = platform.rawValue
        self.externalAccountID = externalAccountID
        self.issuerID = issuerID
        self.keyID = keyID
        self.vendorNumber = vendorNumber
        self.googleFinancialBucket = googleFinancialBucket
        self.createdAt = Date()
        self.sortIndex = sortIndex
    }

    var platform: StorePlatform {
        get { StorePlatform(rawValue: platformRaw) ?? .appleAppStore }
        set { platformRaw = newValue.rawValue }
    }

    var provider: StoreProviderDefinition { StoreProviderRegistry.definition(for: platform) }

    /// Demo accounts are populated locally and never contact either store API.
    var isDemo: Bool {
        issuerID == Self.demoMarker || externalAccountID == Self.demoMarker
    }
}

// MARK: - TrackedApp

@Model
final class TrackedApp {
    @Attribute(.unique) var id: UUID
    /// Provider app id. The persisted name is retained to migrate existing stores
    /// without destructive schema changes; use `remoteIdentifier` in new code.
    var appStoreID: String
    var platformRaw: String = StorePlatform.appleAppStore.rawValue
    var bundleID: String
    var name: String
    var sku: String?
    var primaryLocale: String?
    var iconURLString: String?

    /// Whether we poll data for this app. Archived apps keep their local history
    /// but opt out of sync until they are restored.
    var isTracked: Bool
    /// Whether the app is included in dashboard aggregation / filters.
    var isSelected: Bool
    /// Pinned apps sort above the rest of their account in the sidebar.
    var isPinned: Bool = false
    /// True until the user has acknowledged a freshly discovered app.
    var isNewlyDiscovered: Bool
    var firstSeenAt: Date

    // Cached "current" status for quick display without a query.
    var currentVersionString: String?
    var currentStateRaw: String?
    var currentPlatform: String?
    var statusUpdatedAt: Date?
    var phasedReleaseState: String?   // ACTIVE / PAUSED / COMPLETE
    var phasedReleaseDay: Int?

    /// True once historical reviews have been imported, so later syncs can flag
    /// genuinely new reviews as unread and notify.
    var reviewsBackfilled: Bool = false

    /// Per-app notification rule for new reviews; nil = use the global rule.
    var alertRuleRaw: String?

    /// Throttles the (heavier) all-locale metadata pass.
    var lastMetadataSyncAt: Date?
    /// Whether we've backfilled version-history metadata changes yet.
    var metadataBackfilled: Bool = false

    var account: Account?

    @Relationship(deleteRule: .cascade, inverse: \Review.app)
    var reviews: [Review] = []
    @Relationship(deleteRule: .cascade, inverse: \MetricPoint.app)
    var metrics: [MetricPoint] = []
    @Relationship(deleteRule: .cascade, inverse: \StatusEvent.app)
    var statusEvents: [StatusEvent] = []
    @Relationship(deleteRule: .cascade, inverse: \MetadataSnapshot.app)
    var metadataSnapshots: [MetadataSnapshot] = []
    @Relationship(deleteRule: .cascade, inverse: \MetadataChange.app)
    var metadataChanges: [MetadataChange] = []
    @Relationship(deleteRule: .cascade, inverse: \ChartAnnotation.app)
    var annotations: [ChartAnnotation] = []

    init(id: UUID = UUID(), appStoreID: String, bundleID: String, name: String,
         sku: String? = nil, account: Account? = nil, platform: StorePlatform? = nil) {
        self.id = id
        self.appStoreID = appStoreID
        self.platformRaw = (platform ?? account?.platform ?? .appleAppStore).rawValue
        self.bundleID = bundleID
        self.name = name
        self.sku = sku
        self.account = account
        self.isTracked = true
        self.isSelected = true
        self.isNewlyDiscovered = true
        self.firstSeenAt = Date()
    }

    var platform: StorePlatform {
        get { StorePlatform(rawValue: platformRaw) ?? account?.platform ?? .appleAppStore }
        set { platformRaw = newValue.rawValue }
    }

    var remoteIdentifier: String {
        get { appStoreID }
        set { appStoreID = newValue }
    }

    /// Archiving is the user-facing inverse of tracking. Keeping it derived from
    /// the existing persisted flag makes the change migration-free.
    var isArchived: Bool {
        get { !isTracked }
        set { isTracked = !newValue }
    }

    /// Stable local namespace for provider ids that are only unique within one app.
    var storageIdentity: String { "\(platform.rawValue)|\(id.uuidString.lowercased())" }
    var capabilities: StoreCapabilities { StoreProviderRegistry.definition(for: platform).capabilities }
    var state: AppStoreState { AppStoreState(raw: currentStateRaw) }
}

// MARK: - Review

@Model
final class Review {
    /// StoreGauge-local, provider-scoped identity.
    @Attribute(.unique) var id: String
    /// Raw id expected by the provider API. Optional for lightweight migration.
    var remoteID: String?
    var rating: Int
    var title: String
    var body: String
    var reviewer: String
    var territory: String
    /// Google Play exposes reviewer language rather than storefront territory.
    var reviewerLanguage: String?
    var createdDate: Date

    /// The most recent on-device translation. Keeping one target locally avoids
    /// repeating work while still letting a target-language change invalidate it.
    var translatedTitle: String?
    var translatedBody: String?
    var translationSourceLanguage: String?
    var translationTargetLanguage: String?

    var responseBody: String?
    var responseState: String?
    var responseDate: Date?
    /// Provider response id. Google reuses the review id for reply updates.
    var responseID: String?

    /// False until the user has seen/triaged the review.
    var isRead: Bool
    /// User marked this review as handled without replying.
    var isAcknowledged: Bool = false

    var app: TrackedApp?

    init(id remoteID: String, rating: Int, title: String, body: String, reviewer: String,
         territory: String, reviewerLanguage: String? = nil,
         createdDate: Date, app: TrackedApp? = nil) {
        self.id = Self.makeLocalID(app: app, remoteIdentifier: remoteID)
        self.remoteID = remoteID
        self.rating = rating
        self.title = title
        self.body = body
        self.reviewer = reviewer
        self.territory = territory
        self.reviewerLanguage = reviewerLanguage
        self.createdDate = createdDate
        self.isRead = false
        self.app = app
    }

    var remoteIdentifier: String { remoteID ?? id }

    static func makeLocalID(app: TrackedApp?, remoteIdentifier: String) -> String {
        guard let app else { return remoteIdentifier }
        return "\(app.storageIdentity)|review|\(remoteIdentifier)"
    }

    var hasResponse: Bool { (responseBody?.isEmpty == false) }

    /// In the actionable queue: not answered and not acknowledged.
    var needsAttention: Bool { !hasResponse && !isAcknowledged }

    var triage: TriageStatus {
        if hasResponse { return .answered }
        if isAcknowledged { return .acknowledged }
        return .needsReply
    }

    func clearTranslation() {
        translatedTitle = nil
        translatedBody = nil
        translationSourceLanguage = nil
        translationTargetLanguage = nil
    }

    func hasTranslation(to language: Locale.Language) -> Bool {
        guard translatedBody?.isEmpty == false,
              let identifier = translationTargetLanguage else { return false }
        return Locale.Language(identifier: identifier).isEquivalent(to: language)
    }
}

enum TriageStatus: String, CaseIterable, Sendable {
    case needsReply, acknowledged, answered

    var label: String {
        switch self {
        case .needsReply: return "Needs Reply"
        case .acknowledged: return "Acknowledged"
        case .answered: return "Answered"
        }
    }
    var symbol: String {
        switch self {
        case .needsReply: return "exclamationmark.bubble.fill"
        case .acknowledged: return "checkmark.circle.fill"
        case .answered: return "arrowshape.turn.up.left.fill"
        }
    }
}

// MARK: - MetricPoint

/// A single day's value for one metric on one app. Proceeds are stored per
/// currency so aggregation can convert to a display currency at read time.
@Model
final class MetricPoint {
    /// Composite identity: "<local app identity>|<kind>|<day>|<currency>".
    @Attribute(.unique) var key: String
    var date: Date
    var kindRaw: String
    var value: Double
    /// ISO currency for `proceeds`; nil for count metrics.
    var currency: String?
    var sourceRaw: String

    var app: TrackedApp?

    init(key: String, date: Date, kind: MetricKind, value: Double,
         currency: String? = nil, source: MetricSource, app: TrackedApp? = nil) {
        self.key = key
        self.date = date
        self.kindRaw = kind.rawValue
        self.value = value
        self.currency = currency
        self.sourceRaw = source.rawValue
        self.app = app
    }

    var kind: MetricKind { MetricKind(rawValue: kindRaw) ?? .units }

    static func makeKey(app: TrackedApp, kind: MetricKind, day: Date, currency: String?) -> String {
        let d = DayFormatter.string(from: day)
        return "\(app.storageIdentity)|metric|\(kind.rawValue)|\(d)|\(currency ?? "-")"
    }
}

// MARK: - StatusEvent

/// A recorded change in an app's review/distribution state, for a timeline.
@Model
final class StatusEvent {
    var date: Date
    var versionString: String?
    var fromStateRaw: String?
    var toStateRaw: String?
    var app: TrackedApp?

    init(date: Date = Date(), versionString: String?, fromStateRaw: String?,
         toStateRaw: String?, app: TrackedApp? = nil) {
        self.date = date
        self.versionString = versionString
        self.fromStateRaw = fromStateRaw
        self.toStateRaw = toStateRaw
        self.app = app
    }

    var toState: AppStoreState { AppStoreState(raw: toStateRaw) }
    var fromState: AppStoreState? { fromStateRaw.map(AppStoreState.init(raw:)) }
}

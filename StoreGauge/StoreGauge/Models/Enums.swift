//
//  Enums.swift
//  StoreGauge
//
//  Domain enums shared across the app.
//

import Foundation

/// The review / distribution state of an App Store version.
/// Raw values match `appStoreState` (legacy) and `appVersionState` returned by the API.
enum AppStoreState: String, Codable, CaseIterable, Sendable {
    case prepareForSubmission = "PREPARE_FOR_SUBMISSION"
    case readyForReview = "READY_FOR_REVIEW"
    case waitingForReview = "WAITING_FOR_REVIEW"
    case inReview = "IN_REVIEW"
    case pendingDeveloperRelease = "PENDING_DEVELOPER_RELEASE"
    case pendingAppleRelease = "PENDING_APPLE_RELEASE"
    case processingForDistribution = "PROCESSING_FOR_APP_STORE"
    case readyForDistribution = "READY_FOR_DISTRIBUTION"
    case readyForSale = "READY_FOR_SALE"
    case rejected = "REJECTED"
    case metadataRejected = "METADATA_REJECTED"
    case developerRejected = "DEVELOPER_REJECTED"
    case invalidBinary = "INVALID_BINARY"
    case pendingContract = "PENDING_CONTRACT"
    case waitingForExportCompliance = "WAITING_FOR_EXPORT_COMPLIANCE"
    case replacedWithNewVersion = "REPLACED_WITH_NEW_VERSION"
    case removedFromSale = "REMOVED_FROM_SALE"
    case developerRemovedFromSale = "DEVELOPER_REMOVED_FROM_SALE"
    case notApplicable = "NOT_APPLICABLE"
    case accepted = "ACCEPTED"
    // Google Play production release lifecycle states.
    case googleDraft = "RELEASE_LIFECYCLE_STATE_DRAFT"
    case googleNotSentForReview = "RELEASE_LIFECYCLE_STATE_NOT_SENT_FOR_REVIEW"
    case googleInReview = "RELEASE_LIFECYCLE_STATE_IN_REVIEW"
    case googleApprovedNotPublished = "RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED"
    case googleNotApproved = "RELEASE_LIFECYCLE_STATE_NOT_APPROVED"
    case googlePublished = "RELEASE_LIFECYCLE_STATE_PUBLISHED"
    case unknown = "UNKNOWN"

    init(raw: String?) {
        self = AppStoreState(rawValue: raw ?? "") ?? .unknown
    }

    /// Coarse bucket used for grouping and colour coding.
    enum Category: String, CaseIterable, Sendable {
        case live, inReview, pending, prepare, problem, removed, other
    }

    var category: Category {
        switch self {
        case .readyForSale, .readyForDistribution, .googlePublished: return .live
        case .waitingForReview, .inReview, .readyForReview, .processingForDistribution,
             .waitingForExportCompliance, .googleInReview: return .inReview
        case .pendingDeveloperRelease, .pendingAppleRelease, .pendingContract, .accepted,
             .googleNotSentForReview, .googleApprovedNotPublished: return .pending
        case .prepareForSubmission, .googleDraft: return .prepare
        case .rejected, .metadataRejected, .developerRejected, .invalidBinary,
             .googleNotApproved: return .problem
        case .removedFromSale, .developerRemovedFromSale, .replacedWithNewVersion: return .removed
        case .notApplicable, .unknown: return .other
        }
    }

    var label: String {
        switch self {
        case .prepareForSubmission: return "Prepare for Submission"
        case .readyForReview: return "Ready for Review"
        case .waitingForReview: return "Waiting for Review"
        case .inReview: return "In Review"
        case .pendingDeveloperRelease: return "Pending Developer Release"
        case .pendingAppleRelease: return "Pending Apple Release"
        case .processingForDistribution: return "Processing"
        case .readyForDistribution: return "Ready for Distribution"
        case .readyForSale: return "Ready for Sale"
        case .rejected: return "Rejected"
        case .metadataRejected: return "Metadata Rejected"
        case .developerRejected: return "Developer Rejected"
        case .invalidBinary: return "Invalid Binary"
        case .pendingContract: return "Pending Contract"
        case .waitingForExportCompliance: return "Waiting for Export Compliance"
        case .replacedWithNewVersion: return "Replaced by New Version"
        case .removedFromSale: return "Removed from Sale"
        case .developerRemovedFromSale: return "Removed by Developer"
        case .notApplicable: return "Not Applicable"
        case .accepted: return "Accepted"
        case .googleDraft: return "Draft"
        case .googleNotSentForReview: return "Ready to Send for Review"
        case .googleInReview: return "In Review"
        case .googleApprovedNotPublished: return "Approved · Not Published"
        case .googleNotApproved: return "Not Approved"
        case .googlePublished: return "Published"
        case .unknown: return "Unknown"
        }
    }

    var symbol: String {
        switch category {
        case .live: return "checkmark.seal.fill"
        case .inReview: return "hourglass"
        case .pending: return "clock.badge.checkmark"
        case .prepare: return "pencil.and.outline"
        case .problem: return "exclamationmark.triangle.fill"
        case .removed: return "minus.circle"
        case .other: return "questionmark.circle"
        }
    }
}

/// A single kind of time-series metric we persist for charts.
enum MetricKind: String, Codable, CaseIterable, Sendable {
    case proceeds        // developer proceeds (per currency, converted at read time)
    case units           // sales units (new + updates, non-IAP) from Sales report
    case updates         // app-update units (product type 7*) from Sales report
    case installs        // total downloads from Analytics
    case sessions        // sessions from Analytics
    case activeDevices   // active devices (DAU proxy) from Analytics
    case crashes         // crash count from Analytics
    case crashRate       // Google Play daily crash rate (fraction of active users)
    case anrRate         // Google Play daily ANR rate (fraction of active users)
    case impressions     // App Store impressions from Analytics
    case pageViews       // product page views from Analytics
    case grossSales      // Google Play buyer spend, before tax and Google fees
    case netEarnings     // Google Play finalized payout-oriented earnings
    case orders          // Google Play charged orders minus refunded orders

    var title: String {
        switch self {
        case .proceeds: return "Proceeds"
        case .units: return "Downloads"
        case .updates: return "Updates"
        case .installs: return "Downloads"
        case .sessions: return "Sessions"
        case .activeDevices: return "Active Devices"
        case .crashes: return "Crashes"
        case .crashRate: return "Crash Rate"
        case .anrRate: return "ANR Rate"
        case .impressions: return "Impressions"
        case .pageViews: return "Page Views"
        case .grossSales: return "Gross Sales"
        case .netEarnings: return "Finalized Earnings"
        case .orders: return "Orders"
        }
    }

    var symbol: String {
        switch self {
        case .proceeds: return "dollarsign.circle.fill"
        case .units: return "arrow.down.circle.fill"
        case .updates: return "arrow.triangle.2.circlepath.circle.fill"
        case .installs: return "square.and.arrow.down.fill"
        case .sessions: return "person.wave.2.fill"
        case .activeDevices: return "iphone.gen3"
        case .crashes: return "ant.fill"
        case .crashRate: return "exclamationmark.triangle.fill"
        case .anrRate: return "hourglass.badge.exclamationmark"
        case .impressions: return "eye.fill"
        case .pageViews: return "doc.text.image.fill"
        case .grossSales: return "cart.circle.fill"
        case .netEarnings: return "banknote.fill"
        case .orders: return "bag.fill"
        }
    }
}

/// Source that produced a metric, used to reconcile Sales vs Analytics.
enum MetricSource: String, Codable, Sendable {
    case sales
    case analytics
    case googleEstimatedSales
    case googleEarnings
    case googleStatistics
    case googleVitals
}

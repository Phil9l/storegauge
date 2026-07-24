//
//  DTOs.swift
//  StoreGauge
//
//  Codable mirrors of the App Store Connect JSON:API payloads we consume.
//  These are pure value types and are marked `nonisolated` so their Codable
//  conformances aren't tied to the app's default MainActor isolation (which would
//  otherwise conflict with the generic `Sendable` requirements below).
//

import Foundation

// MARK: - Envelopes

nonisolated struct ASCLinks: Codable, Sendable {
    let next: String?
    let `self`: String?
}

nonisolated struct ASCPaging: Codable, Sendable {
    let total: Int?
    let limit: Int?
}

nonisolated struct ASCMeta: Codable, Sendable {
    let paging: ASCPaging?
}

nonisolated struct ASCRelData: Codable, Sendable {
    let type: String
    let id: String
}

nonisolated struct ASCToOne: Codable, Sendable {
    let data: ASCRelData?
}

nonisolated struct ASCRelationships: Codable, Sendable {
    let response: ASCToOne?
    let app: ASCToOne?
}

nonisolated struct ASCResource<Attr: Codable & Sendable>: Codable, Sendable {
    let type: String
    let id: String
    let attributes: Attr?
    let relationships: ASCRelationships?
}

nonisolated struct ASCListResponse<Attr: Codable & Sendable>: Codable, Sendable {
    let data: [ASCResource<Attr>]
    let links: ASCLinks?
    let meta: ASCMeta?
}

nonisolated struct ASCSingleResponse<Attr: Codable & Sendable>: Codable, Sendable {
    let data: ASCResource<Attr>
}

// MARK: - Attribute payloads

nonisolated struct AppAttributes: Codable, Sendable {
    let name: String?
    let bundleId: String?
    let sku: String?
    let primaryLocale: String?
}

nonisolated struct AppStoreVersionAttributes: Codable, Sendable {
    let versionString: String?
    let appStoreState: String?
    let appVersionState: String?
    let platform: String?
    let createdDate: String?

    var stateRaw: String? { appVersionState ?? appStoreState }
}

nonisolated struct BuildAttributes: Codable, Sendable {
    let version: String?
    let processingState: String?
    let uploadedDate: String?
    let expired: Bool?
    let usesNonExemptEncryption: Bool?
}

nonisolated struct CustomerReviewAttributes: Codable, Sendable {
    let rating: Int?
    let title: String?
    let body: String?
    let reviewerNickname: String?
    let createdDate: String?
    let territory: String?
}

nonisolated struct CustomerReviewResponseAttributes: Codable, Sendable {
    let responseBody: String?
    let lastModifiedDate: String?
    let state: String?
}

/// A heterogeneous `included` entry (we only care about review responses here).
nonisolated struct ASCIncludedResource: Codable, Sendable {
    let type: String
    let id: String
    let attributes: CustomerReviewResponseAttributes?
}

nonisolated struct ReviewsResponse: Codable, Sendable {
    let data: [ASCResource<CustomerReviewAttributes>]
    let included: [ASCIncludedResource]?
    let links: ASCLinks?
    let meta: ASCMeta?
}

// MARK: - Analytics

nonisolated struct AnalyticsReportRequestAttributes: Codable, Sendable {
    let accessType: String?
    let stoppedDueToInactivity: Bool?
}

nonisolated struct AnalyticsReportAttributes: Codable, Sendable {
    let name: String?
    let category: String?
}

nonisolated struct AnalyticsReportInstanceAttributes: Codable, Sendable {
    let granularity: String?
    let processingDate: String?
}

nonisolated struct AnalyticsReportSegmentAttributes: Codable, Sendable {
    let checksum: String?
    let sizeInBytes: Int?
    let url: String?
}

// MARK: - Metadata (app listing)

nonisolated struct AppInfoLocalizationAttributes: Codable, Sendable {
    let locale: String?
    let name: String?
    let subtitle: String?
}

nonisolated struct AppStoreVersionLocalizationAttributes: Codable, Sendable {
    let locale: String?
    let description: String?
    let keywords: String?
    let promotionalText: String?
    let whatsNew: String?
    let marketingUrl: String?
    let supportUrl: String?
}

nonisolated struct AppScreenshotAttributes: Codable, Sendable {
    let fileName: String?
}

nonisolated struct ImageAssetDTO: Codable, Sendable {
    let templateUrl: String?
    let width: Int?
    let height: Int?
}

nonisolated struct ScreenshotFullAttributes: Codable, Sendable {
    let fileName: String?
    let imageAsset: ImageAssetDTO?
}

nonisolated struct AppScreenshotSetFullAttributes: Codable, Sendable {
    let screenshotDisplayType: String?
}

nonisolated struct ScreenshotSetsFullResponse: Codable, Sendable {
    nonisolated struct SetRes: Codable, Sendable {
        let id: String
        let attributes: AppScreenshotSetFullAttributes?
        let relationships: Rels?
        nonisolated struct Rels: Codable, Sendable { let appScreenshots: Rel? }
        nonisolated struct Rel: Codable, Sendable { let data: [ASCRelData]? }
    }
    nonisolated struct Inc: Codable, Sendable {
        let id: String
        let type: String
        let attributes: ScreenshotFullAttributes?
    }
    let data: [SetRes]
    let included: [Inc]?
}

nonisolated struct AppInfosResponse: Codable, Sendable {
    nonisolated struct Included: Codable, Sendable {
        let type: String
        let id: String
        let attributes: AppInfoLocalizationAttributes?
    }
    let data: [ASCResource<EmptyAttributes>]
    let included: [Included]?
}

nonisolated struct ScreenshotSetsResponse: Codable, Sendable {
    nonisolated struct Included: Codable, Sendable {
        let type: String
        let attributes: AppScreenshotAttributes?
    }
    let data: [ASCResource<EmptyAttributes>]
    let included: [Included]?
}

// MARK: - Phased release

nonisolated struct PhasedReleaseAttributes: Codable, Sendable {
    let phasedReleaseState: String?
    let currentDayNumber: Int?
    let startDate: String?
}

/// Single-resource envelope where `data` may be null (empty to-one relationship).
nonisolated struct ASCOptionalSingle<Attr: Codable & Sendable>: Codable, Sendable {
    let data: ASCResource<Attr>?
}

// MARK: - TestFlight

nonisolated struct BetaGroupAttributes: Codable, Sendable {
    let name: String?
    let isInternalGroup: Bool?
    let createdDate: String?
}

nonisolated struct BetaFeedbackAttributes: Codable, Sendable {
    let comment: String?
    let deviceModel: String?
    let osVersion: String?
    let createdDate: String?
}

/// Placeholder for endpoints where we only need `meta.paging.total`.
nonisolated struct EmptyAttributes: Codable, Sendable {}

// MARK: - Errors returned by the API

nonisolated struct ASCErrorResponse: Codable, Sendable {
    nonisolated struct Item: Codable, Sendable {
        let status: String?
        let code: String?
        let title: String?
        let detail: String?
    }
    let errors: [Item]?
}

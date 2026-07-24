//
//  ASCClient.swift
//  StoreGauge
//
//  Thin async client over the App Store Connect REST API. One instance is created
//  per account per sync, carrying that account's credentials.
//

import Foundation

// MARK: - Value results handed to the sync engine

struct AppSummary: Sendable {
    let appStoreID: String
    let bundleID: String
    let name: String
    let sku: String?
    let primaryLocale: String?
}

struct VersionInfo: Sendable {
    let id: String
    let versionString: String?
    let stateRaw: String?
    let platform: String?
    let createdDate: Date?
}

struct BuildInfo: Sendable {
    let id: String
    let version: String?
    let processingState: String?
    let uploadedDate: Date?
    let expired: Bool
}

struct LocaleMetadata: Sendable {
    let locale: String
    var name: String? = nil
    var subtitle: String? = nil
    var description: String? = nil
    var keywords: String? = nil
    var promotionalText: String? = nil
    var whatsNew: String? = nil
    var marketingURL: String? = nil
    var supportURL: String? = nil
    var screenshots: String? = nil

    func value(for field: MetadataField) -> String? {
        switch field {
        case .name: return name
        case .subtitle: return subtitle
        case .description: return description
        case .keywords: return keywords
        case .promotionalText: return promotionalText
        case .whatsNew: return whatsNew
        case .marketingURL: return marketingURL
        case .supportURL: return supportURL
        case .screenshots: return screenshots
        }
    }
}

/// One past App Store version's text metadata (for historical backfill).
struct VersionMetadata: Sendable {
    let version: String?
    let date: Date
    var localizations: [String: LocaleMetadata]   // keyed by locale
}

struct ScreenshotInfo: Sendable, Identifiable {
    let id: String
    let url: String
    let width: Int
    let height: Int
}

struct ScreenshotGroup: Sendable, Identifiable {
    let displayType: String
    let shots: [ScreenshotInfo]
    var id: String { displayType }
    /// "APP_IPHONE_67" -> "iPhone 6.7\"".
    var label: String {
        var s = displayType.replacingOccurrences(of: "APP_", with: "").replacingOccurrences(of: "_", with: " ")
        for (k, v) in ["IPHONE": "iPhone", "IPAD": "iPad", "WATCH": "Watch", "IMESSAGE": "iMessage", "MAC": "Mac", "APPLE TV": "Apple TV"] {
            s = s.replacingOccurrences(of: k, with: v)
        }
        // insert a dot in size codes: "67" -> "6.7\""
        let parts = s.split(separator: " ")
        if let last = parts.last, last.count == 2, Int(last) != nil {
            return parts.dropLast().joined(separator: " ") + " \(last.first!).\(last.last!)\""
        }
        return s
    }
}

struct PhasedReleaseInfo: Sendable {
    let state: String?          // ACTIVE / PAUSED / COMPLETE / INACTIVE
    let currentDay: Int?
    let startDate: Date?

    /// Apple's 7-day phased rollout percentages.
    var percent: Int {
        guard let d = currentDay, d >= 1 else { return 0 }
        let schedule = [1, 2, 5, 10, 20, 50, 100]
        return schedule[min(d, 7) - 1]
    }
    var isActive: Bool { state == "ACTIVE" || state == "PAUSED" }
}

struct BetaGroupInfo: Sendable, Identifiable {
    let id: String
    let name: String
    let isInternal: Bool
    let testerCount: Int
}

struct BetaFeedbackInfo: Sendable, Identifiable {
    let id: String
    let comment: String?
    let device: String?
    let os: String?
    let date: Date?
}

struct ReviewData: Sendable {
    let id: String
    let rating: Int
    let title: String
    let body: String
    let reviewer: String
    let territory: String
    let createdDate: Date
    let responseID: String?
    let responseBody: String?
    let responseState: String?
    let responseDate: Date?
}

// MARK: - Client

@MainActor
final class ASCClient {
    static let base = "https://api.appstoreconnect.apple.com"

    let credentials: ASCCredentials
    private let session: URLSession

    init(credentials: ASCCredentials) {
        self.credentials = credentials
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: Requests

    private func makeRequest(path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil) throws -> URLRequest {
        let url: URL
        if path.hasPrefix("http") {
            guard let u = URL(string: path) else { throw ASCError.message("Bad URL") }
            url = u
        } else {
            guard var comps = URLComponents(string: Self.base + path) else { throw ASCError.message("Bad URL") }
            if !query.isEmpty { comps.queryItems = query }
            guard let u = comps.url else { throw ASCError.message("Bad URL") }
            url = u
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        let token = try JWT.token(for: credentials)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    /// Performs a request, returning raw bytes. Handles 401 (token refresh), 429
    /// (backoff) and surfaces API error details.
    @discardableResult
    private func data(path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil, attempt: Int = 0) async throws -> (Data, HTTPURLResponse) {
        let req = try makeRequest(path: path, query: query, method: method, body: body)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw ASCError.message("Network error: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw ASCError.message("No HTTP response")
        }

        switch http.statusCode {
        case 200...299:
            return (data, http)
        case 401:
            JWT.invalidate(keyID: credentials.keyID)
            if attempt == 0 {
                return try await self.data(path: path, query: query, method: method, body: body, attempt: 1)
            }
            throw parseError(data, status: 401, fallback: "Authentication failed. Check the Issuer ID, Key ID and .p8 key.")
        case 429:
            if attempt < 3 {
                let retryAfter = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? Double(2 << attempt)
                try? await Task.sleep(for: .seconds(min(retryAfter, 30)))
                return try await self.data(path: path, query: query, method: method, body: body, attempt: attempt + 1)
            }
            throw parseError(data, status: 429, fallback: "Rate limited by App Store Connect. Try again shortly.")
        default:
            throw parseError(data, status: http.statusCode, fallback: "Request failed (HTTP \(http.statusCode)).")
        }
    }

    private func parseError(_ data: Data, status: Int, fallback: String) -> ASCError {
        if let decoded = try? JSONDecoder().decode(ASCErrorResponse.self, from: data),
           let first = decoded.errors?.first {
            let detail = first.detail ?? first.title ?? fallback
            return ASCError(statusCode: status, apiCode: first.code, detail: detail)
        }
        return ASCError(statusCode: status, apiCode: nil, detail: fallback)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ASCError.message("Could not parse response: \(error.localizedDescription)")
        }
    }

    private func getList<Attr: Codable & Sendable>(path: String, query: [URLQueryItem], _ attr: Attr.Type) async throws -> ASCListResponse<Attr> {
        let (data, _) = try await self.data(path: path, query: query)
        return try decode(ASCListResponse<Attr>.self, from: data)
    }

    /// Follows `links.next`, merging every page's `data` (capped for safety).
    private func getAll<Attr: Codable & Sendable>(path: String, query: [URLQueryItem], _ attr: Attr.Type, maxPages: Int = 50) async throws -> [ASCResource<Attr>] {
        var all: [ASCResource<Attr>] = []
        var page = try await getList(path: path, query: query, attr)
        all.append(contentsOf: page.data)
        var pages = 1
        while let next = page.links?.next, pages < maxPages {
            let (data, _) = try await self.data(path: next)
            page = try decode(ASCListResponse<Attr>.self, from: data)
            all.append(contentsOf: page.data)
            pages += 1
        }
        return all
    }

    // MARK: Endpoints

    func listApps() async throws -> [AppSummary] {
        let query = [
            URLQueryItem(name: "fields[apps]", value: "name,bundleId,sku,primaryLocale"),
            URLQueryItem(name: "limit", value: "200"),
        ]
        let resources = try await getAll(path: "/v1/apps", query: query, AppAttributes.self)
        return resources.map { r in
            AppSummary(appStoreID: r.id,
                       bundleID: r.attributes?.bundleId ?? "",
                       name: r.attributes?.name ?? "Unknown",
                       sku: r.attributes?.sku,
                       primaryLocale: r.attributes?.primaryLocale)
        }
    }

    /// Whether this key can reach the Users endpoint (a proxy for an all-apps admin key).
    func verifyConnection() async throws -> Int {
        let apps = try await listApps()
        return apps.count
    }

    func appVersions(appID: String, limit: Int = 10) async throws -> [VersionInfo] {
        let query = [
            URLQueryItem(name: "fields[appStoreVersions]", value: "versionString,appStoreState,appVersionState,platform,createdDate"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let resources = try await getList(path: "/v1/apps/\(appID)/appStoreVersions", query: query, AppStoreVersionAttributes.self).data
        return resources.map { r in
            VersionInfo(id: r.id,
                        versionString: r.attributes?.versionString,
                        stateRaw: r.attributes?.stateRaw,
                        platform: r.attributes?.platform,
                        createdDate: APIDate.parse(r.attributes?.createdDate))
        }
    }

    func latestBuilds(appID: String, limit: Int = 5) async throws -> [BuildInfo] {
        // Note: the app→builds relationship endpoint rejects `sort`, so we fetch a
        // page and order client-side by upload date.
        let query = [
            URLQueryItem(name: "fields[builds]", value: "version,processingState,uploadedDate,expired"),
            URLQueryItem(name: "limit", value: "20"),
        ]
        let resources = try await getList(path: "/v1/apps/\(appID)/builds", query: query, BuildAttributes.self).data
        return resources.map { r in
            BuildInfo(id: r.id,
                      version: r.attributes?.version,
                      processingState: r.attributes?.processingState,
                      uploadedDate: APIDate.parse(r.attributes?.uploadedDate),
                      expired: r.attributes?.expired ?? false)
        }
        .sorted { ($0.uploadedDate ?? .distantPast) > ($1.uploadedDate ?? .distantPast) }
        .prefix(limit).map { $0 }
    }

    /// Fetches newest reviews, stopping early once a whole page is already known.
    func reviews(appID: String, knownIDs: Set<String>, maxPages: Int = 8) async throws -> [ReviewData] {
        var out: [ReviewData] = []
        let firstQuery = [
            URLQueryItem(name: "sort", value: "-createdDate"),
            URLQueryItem(name: "include", value: "response"),
            URLQueryItem(name: "fields[customerReviews]", value: "rating,title,body,reviewerNickname,createdDate,territory,response"),
            URLQueryItem(name: "fields[customerReviewResponses]", value: "responseBody,lastModifiedDate,state"),
            URLQueryItem(name: "limit", value: "200"),
        ]
        var path = "/v1/apps/\(appID)/customerReviews"
        var query = firstQuery
        var pages = 0
        while pages < maxPages {
            let (data, _) = try await self.data(path: path, query: query)
            let resp = try decode(ReviewsResponse.self, from: data)
            let responseByID: [String: CustomerReviewResponseAttributes] = Dictionary(
                (resp.included ?? []).compactMap { inc in
                    inc.attributes.map { (inc.id, $0) }
                }, uniquingKeysWith: { a, _ in a })

            var pageIDs = Set<String>()
            for r in resp.data {
                pageIDs.insert(r.id)
                let responseID = r.relationships?.response?.data?.id
                let respAttr = responseID.flatMap { responseByID[$0] }
                out.append(ReviewData(
                    id: r.id,
                    rating: r.attributes?.rating ?? 0,
                    title: r.attributes?.title ?? "",
                    body: r.attributes?.body ?? "",
                    reviewer: r.attributes?.reviewerNickname ?? "",
                    territory: r.attributes?.territory ?? "",
                    createdDate: APIDate.parse(r.attributes?.createdDate) ?? Date(),
                    responseID: responseID,
                    responseBody: respAttr?.responseBody,
                    responseState: respAttr?.state,
                    responseDate: APIDate.parse(respAttr?.lastModifiedDate)))
            }
            pages += 1
            // Stop once we've reached reviews we already have.
            if !knownIDs.isEmpty, !pageIDs.isEmpty, pageIDs.isSubset(of: knownIDs) { break }
            guard let next = resp.links?.next else { break }
            path = next
            query = []
        }
        return out
    }

    // MARK: Metadata (all localizations)

    func appMetadata(appID: String, includeScreenshots: Bool) async -> (version: String?, locales: [LocaleMetadata]) {
        var byLocale: [String: LocaleMetadata] = [:]

        // Name + subtitle (one call, all locales via include).
        if let data = try? await rawGet(path: "/v1/apps/\(appID)/appInfos",
            query: [URLQueryItem(name: "include", value: "appInfoLocalizations"),
                    URLQueryItem(name: "fields[appInfoLocalizations]", value: "locale,name,subtitle"),
                    URLQueryItem(name: "limit", value: "5")]),
           let resp = try? JSONDecoder().decode(AppInfosResponse.self, from: data) {
            for inc in resp.included ?? [] where inc.type == "appInfoLocalizations" {
                guard let loc = inc.attributes?.locale else { continue }
                var m = byLocale[loc] ?? LocaleMetadata(locale: loc)
                m.name = inc.attributes?.name
                m.subtitle = inc.attributes?.subtitle
                byLocale[loc] = m
            }
        }

        // Newest version's localizations (description/keywords/promo/whatsNew/URLs).
        var version: String?
        if let vdata = try? await rawGet(path: "/v1/apps/\(appID)/appStoreVersions",
            query: [URLQueryItem(name: "fields[appStoreVersions]", value: "versionString,createdDate"),
                    URLQueryItem(name: "limit", value: "10")]),
           let vlist = try? JSONDecoder().decode(ASCListResponse<AppStoreVersionAttributes>.self, from: vdata),
           let newest = vlist.data.max(by: { (APIDate.parse($0.attributes?.createdDate) ?? .distantPast) < (APIDate.parse($1.attributes?.createdDate) ?? .distantPast) }) {
            version = newest.attributes?.versionString
            if let ldata = try? await rawGet(path: "/v1/appStoreVersions/\(newest.id)/appStoreVersionLocalizations",
                query: [URLQueryItem(name: "fields[appStoreVersionLocalizations]", value: "locale,description,keywords,promotionalText,whatsNew,marketingUrl,supportUrl"),
                        URLQueryItem(name: "limit", value: "50")]),
               let llist = try? JSONDecoder().decode(ASCListResponse<AppStoreVersionLocalizationAttributes>.self, from: ldata) {
                for r in llist.data {
                    guard let loc = r.attributes?.locale else { continue }
                    var m = byLocale[loc] ?? LocaleMetadata(locale: loc)
                    m.description = r.attributes?.description
                    m.keywords = r.attributes?.keywords
                    m.promotionalText = r.attributes?.promotionalText
                    m.whatsNew = r.attributes?.whatsNew
                    m.marketingURL = r.attributes?.marketingUrl
                    m.supportURL = r.attributes?.supportUrl
                    if includeScreenshots { m.screenshots = await screenshotFingerprint(localizationID: r.id) }
                    byLocale[loc] = m
                }
            }
        }
        return (version, Array(byLocale.values))
    }

    /// Reconstructs the metadata history from past App Store versions (ascending
    /// by creation date). Text fields only — screenshots aren't backfilled.
    func versionHistory(appID: String, maxVersions: Int = 30) async -> [VersionMetadata] {
        guard let vdata = try? await rawGet(path: "/v1/apps/\(appID)/appStoreVersions",
            query: [URLQueryItem(name: "fields[appStoreVersions]", value: "versionString,createdDate"),
                    URLQueryItem(name: "limit", value: "50")]),
              let vlist = try? JSONDecoder().decode(ASCListResponse<AppStoreVersionAttributes>.self, from: vdata) else { return [] }

        let versions = vlist.data
            .map { (id: $0.id, version: $0.attributes?.versionString, date: APIDate.parse($0.attributes?.createdDate) ?? .distantPast) }
            .sorted { $0.date < $1.date }
            .suffix(maxVersions)

        var out: [VersionMetadata] = []
        for v in versions {
            var byLocale: [String: LocaleMetadata] = [:]
            if let ldata = try? await rawGet(path: "/v1/appStoreVersions/\(v.id)/appStoreVersionLocalizations",
                query: [URLQueryItem(name: "fields[appStoreVersionLocalizations]", value: "locale,description,keywords,promotionalText,whatsNew,marketingUrl,supportUrl"),
                        URLQueryItem(name: "limit", value: "50")]),
               let llist = try? JSONDecoder().decode(ASCListResponse<AppStoreVersionLocalizationAttributes>.self, from: ldata) {
                for r in llist.data {
                    guard let loc = r.attributes?.locale else { continue }
                    var m = LocaleMetadata(locale: loc)
                    m.description = r.attributes?.description
                    m.keywords = r.attributes?.keywords
                    m.promotionalText = r.attributes?.promotionalText
                    m.whatsNew = r.attributes?.whatsNew
                    m.marketingURL = r.attributes?.marketingUrl
                    m.supportURL = r.attributes?.supportUrl
                    byLocale[loc] = m
                }
            }
            out.append(VersionMetadata(version: v.version, date: v.date, localizations: byLocale))
        }
        return out
    }

    /// Current screenshots for an app + locale, grouped by device display type.
    func screenshots(appID: String, locale: String) async -> [ScreenshotGroup] {
        guard let vdata = try? await rawGet(path: "/v1/apps/\(appID)/appStoreVersions",
                query: [URLQueryItem(name: "fields[appStoreVersions]", value: "versionString,createdDate"),
                        URLQueryItem(name: "limit", value: "10")]),
              let vlist = try? JSONDecoder().decode(ASCListResponse<AppStoreVersionAttributes>.self, from: vdata),
              let newest = vlist.data.max(by: { (APIDate.parse($0.attributes?.createdDate) ?? .distantPast) < (APIDate.parse($1.attributes?.createdDate) ?? .distantPast) })
        else { return [] }

        guard let ldata = try? await rawGet(path: "/v1/appStoreVersions/\(newest.id)/appStoreVersionLocalizations",
                query: [URLQueryItem(name: "filter[locale]", value: locale),
                        URLQueryItem(name: "fields[appStoreVersionLocalizations]", value: "locale"),
                        URLQueryItem(name: "limit", value: "5")]),
              let llist = try? JSONDecoder().decode(ASCListResponse<AppStoreVersionLocalizationAttributes>.self, from: ldata),
              let loc = llist.data.first else { return [] }

        guard let sdata = try? await rawGet(path: "/v1/appStoreVersionLocalizations/\(loc.id)/appScreenshotSets",
                query: [URLQueryItem(name: "include", value: "appScreenshots"),
                        URLQueryItem(name: "fields[appScreenshotSets]", value: "screenshotDisplayType,appScreenshots"),
                        URLQueryItem(name: "fields[appScreenshots]", value: "fileName,imageAsset"),
                        URLQueryItem(name: "limit", value: "50")]),
              let resp = try? JSONDecoder().decode(ScreenshotSetsFullResponse.self, from: sdata) else { return [] }

        let byID = Dictionary((resp.included ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var groups: [ScreenshotGroup] = []
        for set in resp.data {
            let ids = set.relationships?.appScreenshots?.data?.map(\.id) ?? []
            let shots: [ScreenshotInfo] = ids.compactMap { id in
                guard let asset = byID[id]?.attributes?.imageAsset, let tmpl = asset.templateUrl,
                      let w = asset.width, let h = asset.height, w > 0 else { return nil }
                let tw = 320
                let th = Int(320.0 * Double(h) / Double(w))
                let url = tmpl.replacingOccurrences(of: "{w}", with: "\(tw)")
                    .replacingOccurrences(of: "{h}", with: "\(th)")
                    .replacingOccurrences(of: "{f}", with: "png")
                return ScreenshotInfo(id: id, url: url, width: tw, height: th)
            }
            if !shots.isEmpty {
                groups.append(ScreenshotGroup(displayType: set.attributes?.screenshotDisplayType ?? "", shots: shots))
            }
        }
        return groups
    }

    private func screenshotFingerprint(localizationID: String) async -> String? {
        guard let data = try? await rawGet(path: "/v1/appStoreVersionLocalizations/\(localizationID)/appScreenshotSets",
            query: [URLQueryItem(name: "include", value: "appScreenshots"),
                    URLQueryItem(name: "fields[appScreenshots]", value: "fileName"),
                    URLQueryItem(name: "limit", value: "50")]),
              let resp = try? JSONDecoder().decode(ScreenshotSetsResponse.self, from: data) else { return nil }
        let names = (resp.included ?? []).filter { $0.type == "appScreenshots" }
            .compactMap { $0.attributes?.fileName }.sorted()
        return "\(names.count)#\(Self.stableHash(names.joined(separator: ",")))"
    }

    /// Deterministic FNV-1a hash (unlike Hasher, stable across launches).
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }

    // MARK: Phased release

    func phasedRelease(versionID: String) async -> PhasedReleaseInfo? {
        let data: Data
        do {
            data = try await rawGet(path: "/v1/appStoreVersions/\(versionID)/appStoreVersionPhasedRelease",
                query: [URLQueryItem(name: "fields[appStoreVersionPhasedReleases]", value: "phasedReleaseState,currentDayNumber,startDate")])
        } catch { return nil }
        guard let single = try? JSONDecoder().decode(ASCOptionalSingle<PhasedReleaseAttributes>.self, from: data),
              let res = single.data else { return nil }
        return PhasedReleaseInfo(state: res.attributes?.phasedReleaseState,
                                 currentDay: res.attributes?.currentDayNumber,
                                 startDate: APIDate.parse(res.attributes?.startDate))
    }

    // MARK: TestFlight

    func betaGroups(appID: String) async throws -> [BetaGroupInfo] {
        let list = try await getList(path: "/v1/apps/\(appID)/betaGroups",
            query: [URLQueryItem(name: "fields[betaGroups]", value: "name,isInternalGroup"),
                    URLQueryItem(name: "limit", value: "50")], BetaGroupAttributes.self)
        var out: [BetaGroupInfo] = []
        for g in list.data {
            let count = (try? await getList(path: "/v1/betaGroups/\(g.id)/betaTesters",
                query: [URLQueryItem(name: "limit", value: "1")], EmptyAttributes.self))?.meta?.paging?.total ?? 0
            out.append(BetaGroupInfo(id: g.id, name: g.attributes?.name ?? "Group",
                                     isInternal: g.attributes?.isInternalGroup ?? false, testerCount: count))
        }
        return out
    }

    func betaFeedback(appID: String, limit: Int = 25) async throws -> [BetaFeedbackInfo] {
        let list = try await getList(path: "/v1/apps/\(appID)/betaFeedbackCrashSubmissions",
            query: [URLQueryItem(name: "limit", value: String(limit))], BetaFeedbackAttributes.self)
        return list.data.map { r in
            BetaFeedbackInfo(id: r.id, comment: r.attributes?.comment, device: r.attributes?.deviceModel,
                             os: r.attributes?.osVersion, date: APIDate.parse(r.attributes?.createdDate))
        }
    }

    // MARK: Review responses (reply to a review)

    @discardableResult
    func replyToReview(reviewID: String, body: String) async throws -> String? {
        let payload: [String: Any] = [
            "data": [
                "type": "customerReviewResponses",
                "attributes": ["responseBody": body],
                "relationships": [
                    "review": ["data": ["type": "customerReviews", "id": reviewID]]
                ],
            ]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await self.data(path: "/v1/customerReviewResponses", method: "POST", body: body)
        return (try? JSONDecoder().decode(ASCSingleResponse<CustomerReviewResponseAttributes>.self, from: data))?.data.id
    }

    func editReviewResponse(responseID: String, body: String) async throws {
        let payload: [String: Any] = [
            "data": [
                "type": "customerReviewResponses",
                "id": responseID,
                "attributes": ["responseBody": body],
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        _ = try await self.data(path: "/v1/customerReviewResponses/\(responseID)", method: "PATCH", body: data)
    }

    func deleteReviewResponse(responseID: String) async throws {
        _ = try await self.data(path: "/v1/customerReviewResponses/\(responseID)", method: "DELETE")
    }

    // MARK: Sales & Trends report -> decompressed TSV text

    /// Returns the decompressed TSV, or nil when Apple has no report for that date.
    func salesReportTSV(vendorNumber: String, date: Date, frequency: String = "DAILY") async throws -> String? {
        let query = [
            URLQueryItem(name: "filter[frequency]", value: frequency),
            URLQueryItem(name: "filter[reportType]", value: "SALES"),
            URLQueryItem(name: "filter[reportSubType]", value: "SUMMARY"),
            URLQueryItem(name: "filter[vendorNumber]", value: vendorNumber),
            URLQueryItem(name: "filter[reportDate]", value: DayFormatter.string(from: date)),
            URLQueryItem(name: "filter[version]", value: "1_0"),
        ]
        do {
            let (raw, _) = try await self.data(path: "/v1/salesReports", query: query)
            let text = String(data: Gzip.decompress(raw), encoding: .utf8)
            return text
        } catch let e as ASCError {
            if e.isNotFound { return nil } // no sales that day
            throw e
        }
    }

    /// Daily SUBSCRIPTION report (snapshot of active subscriptions). Returns nil
    /// when Apple has no report for that date.
    func subscriptionReportTSV(vendorNumber: String, date: Date) async throws -> String? {
        let query = [
            URLQueryItem(name: "filter[frequency]", value: "DAILY"),
            URLQueryItem(name: "filter[reportType]", value: "SUBSCRIPTION"),
            URLQueryItem(name: "filter[reportSubType]", value: "SUMMARY"),
            URLQueryItem(name: "filter[vendorNumber]", value: vendorNumber),
            URLQueryItem(name: "filter[reportDate]", value: DayFormatter.string(from: date)),
            URLQueryItem(name: "filter[version]", value: "1_4"),
        ]
        do {
            let (raw, _) = try await self.data(path: "/v1/salesReports", query: query)
            return String(data: Gzip.decompress(raw), encoding: .utf8)
        } catch let e as ASCError {
            if e.isNotFound { return nil }
            throw e
        }
    }

    /// Daily SUBSCRIPTION_EVENT report (subscribe/cancel/renew/refund events).
    func subscriptionEventReportTSV(vendorNumber: String, date: Date) async throws -> String? {
        let query = [
            URLQueryItem(name: "filter[frequency]", value: "DAILY"),
            URLQueryItem(name: "filter[reportType]", value: "SUBSCRIPTION_EVENT"),
            URLQueryItem(name: "filter[reportSubType]", value: "SUMMARY"),
            URLQueryItem(name: "filter[vendorNumber]", value: vendorNumber),
            URLQueryItem(name: "filter[reportDate]", value: DayFormatter.string(from: date)),
            URLQueryItem(name: "filter[version]", value: "1_4"),
        ]
        do {
            let (raw, _) = try await self.data(path: "/v1/salesReports", query: query)
            return String(data: Gzip.decompress(raw), encoding: .utf8)
        } catch let e as ASCError {
            if e.isNotFound { return nil }
            throw e
        }
    }

    // MARK: Generic helpers used by AnalyticsService

    func rawGet(path: String, query: [URLQueryItem] = []) async throws -> Data {
        let (data, _) = try await self.data(path: path, query: query)
        return data
    }

    func rawPost(path: String, json: [String: Any]) async throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: json)
        let (data, _) = try await self.data(path: path, method: "POST", body: body)
        return data
    }

    /// Downloads a pre-signed report segment URL (no auth header).
    func downloadSegment(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw ASCError.message("Bad segment URL") }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ASCError.message("Segment download failed")
        }
        return Gzip.decompress(data)
    }
}

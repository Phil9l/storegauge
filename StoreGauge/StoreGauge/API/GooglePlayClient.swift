//
//  GooglePlayClient.swift
//  StoreGauge
//
//  Dependency-free clients for Google Play Developer Reporting (app discovery)
//  and Android Publisher (production releases, reviews, and replies).
//

import Foundation

struct GooglePlayError: LocalizedError, Sendable {
    let statusCode: Int?
    let detail: String

    var errorDescription: String? { detail }
    var isAuth: Bool { statusCode == 401 || statusCode == 403 }
    var isTransient: Bool {
        if let statusCode, [408, 429, 500, 502, 503, 504].contains(statusCode) {
            return true
        }
        return detail.hasPrefix("Google Play network error:")
    }

    static func message(_ detail: String, statusCode: Int? = nil) -> Self {
        Self(statusCode: statusCode, detail: detail)
    }

    static func from(data: Data, statusCode: Int, fallback: String) -> Self {
        struct Envelope: Decodable {
            struct APIError: Decodable { let message: String?; let status: String? }
            let error: APIError?
        }
        let decoded = try? JSONDecoder().decode(Envelope.self, from: data)
        let raw = decoded?.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = (raw?.isEmpty == false) ? raw! : fallback
        return Self(statusCode: statusCode, detail: detail)
    }
}

struct GooglePlayAppSummary: Decodable, Sendable {
    let name: String
    let packageName: String
    let displayName: String
}

struct GooglePlayReleaseSummary: Sendable {
    let name: String
    let versionCode: Int?
    let lifecycleState: String
}

struct GooglePlayReviewSummary: Sendable {
    let id: String
    let rating: Int
    let body: String
    let reviewer: String
    let language: String?
    let createdDate: Date
    let responseBody: String?
    let responseDate: Date?
}

struct GooglePlayReplyResult: Sendable {
    let body: String
    let editedAt: Date
}

struct GooglePlayVitalPoint: Equatable, Sendable {
    let date: Date
    /// Fraction of active users affected on this day (for example 0.012 = 1.2%).
    let value: Double
}

struct GooglePlayVitals: Sendable {
    let crashRate: [GooglePlayVitalPoint]
    let anrRate: [GooglePlayVitalPoint]
}

struct GooglePlayVitalMetricSet: Decodable, Sendable {
    struct FreshnessInfo: Decodable, Sendable {
        struct Freshness: Decodable, Sendable {
            struct DateTime: Decodable, Sendable {
                let year: Int?
                let month: Int?
                let day: Int?
            }

            let aggregationPeriod: String?
            let latestEndTime: DateTime?
        }

        let freshnesses: [Freshness]?
    }

    let freshnessInfo: FreshnessInfo?

    func latestDailyEndDate(calendar: Calendar) -> Date? {
        guard let time = freshnessInfo?.freshnesses?.first(where: {
            $0.aggregationPeriod == "DAILY"
        })?.latestEndTime,
              let year = time.year, let month = time.month, let day = time.day else {
            return nil
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

private struct GoogleFlexibleDecimal: Decodable, Sendable {
    let value: Double

    private enum CodingKeys: CodingKey { case value }

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let value = try? single.decode(Double.self) {
            self.value = value
            return
        }
        if let string = try? single.decode(String.self), let value = Double(string) {
            self.value = value
            return
        }
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        if let string = try? keyed.decode(String.self, forKey: .value), let value = Double(string) {
            self.value = value
        } else if let value = try? keyed.decode(Double.self, forKey: .value) {
            self.value = value
        } else {
            throw DecodingError.dataCorruptedError(forKey: .value, in: keyed,
                                                   debugDescription: "Expected a Google decimal value.")
        }
    }
}

struct GooglePlayVitalRateResponse: Decodable, Sendable {
    struct Row: Decodable, Sendable {
        struct DateTime: Decodable, Sendable {
            let year: Int?
            let month: Int?
            let day: Int?
        }
        struct Metric: Decodable, Sendable {
            let metric: String
            fileprivate let decimalValue: GoogleFlexibleDecimal?
        }

        let startTime: DateTime?
        let metrics: [Metric]?
    }

    let rows: [Row]?
    let nextPageToken: String?

    func points(metric expectedMetric: String) -> [GooglePlayVitalPoint] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return (rows ?? []).compactMap { row in
            guard let time = row.startTime,
                  let year = time.year, let month = time.month, let day = time.day,
                  let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  let metric = row.metrics?.first(where: { $0.metric == expectedMetric }),
                  let value = metric.decimalValue?.value else { return nil }
            return GooglePlayVitalPoint(date: calendar.startOfDay(for: date), value: value)
        }
        .sorted { $0.date < $1.date }
    }
}

/// Google APIs usually follow their published JSON scalar representation, but
/// older Publisher responses sometimes encode integral values as strings.
private struct GoogleFlexibleInteger: Decodable, Sendable {
    let value: Int64

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int64.self) {
            self.value = value
        } else if let string = try? container.decode(String.self), let value = Int64(string) {
            self.value = value
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an integer or numeric string.")
        }
    }
}

enum GooglePlayResponseDecoder {
    nonisolated static func decode<Response: Decodable>(
        _ type: Response.Type,
        from data: Data,
        emptyResponse: Response? = nil
    ) throws -> Response {
        if data.isEmpty, let emptyResponse { return emptyResponse }
        return try JSONDecoder().decode(type, from: data)
    }
}

@MainActor
final class GooglePlayClient {
    private static let publisherBase = "https://androidpublisher.googleapis.com/androidpublisher/v3"
    private static let reportingBase = "https://playdeveloperreporting.googleapis.com/v1beta1"
    private static let maximumTransientRetries = 3

    let credentials: GoogleServiceAccountCredentials
    private let session: URLSession
    private let scopes = [GoogleOAuthScope.androidPublisher, GoogleOAuthScope.developerReporting]

    init(credentials: GoogleServiceAccountCredentials, session: URLSession? = nil) {
        self.credentials = credentials
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 45
            configuration.waitsForConnectivity = true
            self.session = URLSession(configuration: configuration)
        }
    }

    func verifyConnection() async throws -> Int {
        let apps = try await listApps()
        // App discovery uses Developer Reporting, while releases/reviews use
        // Android Publisher. Probe both so setup errors appear before saving.
        if let first = apps.first {
            _ = try await productionRelease(packageName: first.packageName)
            do {
                _ = try await vitals(packageName: first.packageName, historyDays: 7)
            } catch let error as GooglePlayError where error.statusCode == 404 {
                // A newly created or never-published app legitimately has no
                // Android-vitals metric set yet.
            }
        }
        return apps.count
    }

    func listApps() async throws -> [GooglePlayAppSummary] {
        struct Response: Decodable {
            let apps: [GooglePlayAppSummary]?
            let nextPageToken: String?
        }

        var output: [GooglePlayAppSummary] = []
        var pageToken: String?
        repeat {
            let response: Response = try await request(
                base: Self.reportingBase,
                path: "/apps:search",
                query: [
                    URLQueryItem(name: "pageSize", value: "1000"),
                    URLQueryItem(name: "pageToken", value: pageToken),
                ].filter { $0.value != nil }
            )
            output.append(contentsOf: response.apps ?? [])
            pageToken = response.nextPageToken
        } while pageToken?.isEmpty == false
        DiagnosticLog.record("Google Play · App discovery completed · \(output.count) apps")
        return output.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func productionRelease(packageName: String) async throws -> GooglePlayReleaseSummary? {
        struct Artifact: Decodable { let versionCode: GoogleFlexibleInteger? }
        struct Release: Decodable {
            let releaseName: String?
            let activeArtifacts: [Artifact]?
            let releaseLifecycleState: String?
        }
        struct Response: Decodable { let releases: [Release]? }

        let package = Self.pathSegment(packageName)
        let response: Response = try await request(
            base: Self.publisherBase,
            path: "/applications/\(package)/tracks/production/releases",
            emptyResponse: Response(releases: nil)
        )
        let candidates = response.releases ?? []
        DiagnosticLog.record("Google Play · Production release · \(packageName) · \(candidates.count) active releases")
        guard let release = candidates.max(by: { lhs, rhs in
            (lhs.activeArtifacts?.compactMap { $0.versionCode?.value }.max() ?? -1) <
            (rhs.activeArtifacts?.compactMap { $0.versionCode?.value }.max() ?? -1)
        }) else { return nil }
        let rawVersionCode = release.activeArtifacts?.compactMap { $0.versionCode?.value }.max()
        let versionCode = rawVersionCode.flatMap(Int.init(exactly:))
        return GooglePlayReleaseSummary(
            name: release.releaseName ?? versionCode.map(String.init) ?? "",
            versionCode: versionCode,
            lifecycleState: release.releaseLifecycleState ?? "RELEASE_LIFECYCLE_STATE_UNSPECIFIED"
        )
    }

    /// Daily Android-vitals rates for public OS users. Google aggregates daily
    /// rate metrics in America/Los_Angeles, so those calendar dates are preserved
    /// as UTC day keys for StoreGauge charts instead of being timezone-shifted.
    func vitals(packageName: String, historyDays: Int) async throws -> GooglePlayVitals {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let crash = try await vitalRate(
            packageName: packageName,
            metricSet: "crashRateMetricSet",
            metric: "crashRate",
            historyDays: historyDays,
            calendar: calendar
        )
        let anr = try await vitalRate(
            packageName: packageName,
            metricSet: "anrRateMetricSet",
            metric: "anrRate",
            historyDays: historyDays,
            calendar: calendar
        )
        DiagnosticLog.record("Google Play · Android vitals · \(packageName) · \(crash.count) crash days · \(anr.count) ANR days")
        return GooglePlayVitals(crashRate: crash, anrRate: anr)
    }

    private func vitalRate(packageName: String,
                           metricSet: String,
                           metric: String,
                           historyDays: Int,
                           calendar: Calendar) async throws -> [GooglePlayVitalPoint] {
        let path = "/apps/\(Self.pathSegment(packageName))/\(metricSet)"
        let metadata: GooglePlayVitalMetricSet = try await request(
            base: Self.reportingBase,
            path: path
        )
        guard let end = metadata.latestDailyEndDate(calendar: calendar) else {
            DiagnosticLog.record("Google Play · \(metric) · \(packageName) · no daily freshness available")
            return []
        }
        let start = calendar.date(byAdding: .day, value: -max(1, historyDays), to: end) ?? end

        func dateTime(_ date: Date) -> [String: Any] {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return [
                "year": parts.year ?? 1,
                "month": parts.month ?? 1,
                "day": parts.day ?? 1,
                "timeZone": ["id": "America/Los_Angeles"],
            ]
        }

        var pageToken: String?
        var output: [GooglePlayVitalPoint] = []
        repeat {
            var payload: [String: Any] = [
                "timelineSpec": [
                    "aggregationPeriod": "DAILY",
                    "startTime": dateTime(start),
                    "endTime": dateTime(end),
                ],
                "metrics": [metric],
                "pageSize": 1_000,
                "userCohort": "OS_PUBLIC",
            ]
            if let pageToken { payload["pageToken"] = pageToken }
            let body = try JSONSerialization.data(withJSONObject: payload)
            let response: GooglePlayVitalRateResponse = try await request(
                base: Self.reportingBase,
                path: path + ":query",
                method: "POST",
                body: body
            )
            output.append(contentsOf: response.points(metric: metric))
            pageToken = response.nextPageToken
        } while pageToken?.isEmpty == false
        return output.sorted { $0.date < $1.date }
    }

    func reviews(packageName: String) async throws -> [GooglePlayReviewSummary] {
        struct Timestamp: Decodable {
            let seconds: Int64

            enum CodingKeys: CodingKey { case seconds }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let string = try? container.decode(String.self, forKey: .seconds), let value = Int64(string) {
                    seconds = value
                } else if let value = try? container.decode(Int64.self, forKey: .seconds) {
                    seconds = value
                } else {
                    seconds = 0
                }
            }

            var date: Date { Date(timeIntervalSince1970: TimeInterval(seconds)) }
        }
        struct UserComment: Decodable {
            let text: String?
            let lastModified: Timestamp?
            let starRating: GoogleFlexibleInteger?
            let reviewerLanguage: String?
        }
        struct DeveloperComment: Decodable { let text: String?; let lastModified: Timestamp? }
        struct Comment: Decodable { let userComment: UserComment?; let developerComment: DeveloperComment? }
        struct APIReview: Decodable { let reviewId: String; let authorName: String?; let comments: [Comment]? }
        struct Pagination: Decodable { let nextPageToken: String? }
        struct Response: Decodable {
            let reviews: [APIReview]?
            let tokenPagination: Pagination?
        }

        let package = Self.pathSegment(packageName)
        var token: String?
        var output: [GooglePlayReviewSummary] = []
        repeat {
            let response: Response = try await request(
                base: Self.publisherBase,
                path: "/applications/\(package)/reviews",
                query: [
                    URLQueryItem(name: "maxResults", value: "100"),
                    URLQueryItem(name: "token", value: token),
                ].filter { $0.value != nil }
            )
            for review in response.reviews ?? [] {
                let comments = review.comments ?? []
                guard let user = comments.compactMap(\.userComment).max(by: {
                    ($0.lastModified?.seconds ?? 0) < ($1.lastModified?.seconds ?? 0)
                }) else { continue }
                let developer = comments.compactMap(\.developerComment).max(by: {
                    ($0.lastModified?.seconds ?? 0) < ($1.lastModified?.seconds ?? 0)
                })
                output.append(GooglePlayReviewSummary(
                    id: review.reviewId,
                    rating: min(5, max(1, Int(user.starRating?.value ?? 1))),
                    body: user.text ?? "",
                    reviewer: review.authorName ?? "Google Play user",
                    language: user.reviewerLanguage,
                    createdDate: user.lastModified?.date ?? .distantPast,
                    responseBody: developer?.text,
                    responseDate: developer?.lastModified?.date
                ))
            }
            token = response.tokenPagination?.nextPageToken
        } while token?.isEmpty == false
        DiagnosticLog.record("Google Play · Reviews · \(packageName) · \(output.count) written reviews")
        return output
    }

    func reply(packageName: String, reviewID: String, body: String) async throws -> GooglePlayReplyResult {
        struct Timestamp: Decodable {
            let seconds: GoogleFlexibleInteger?
            var date: Date { Date(timeIntervalSince1970: TimeInterval(seconds?.value ?? 0)) }
        }
        struct Result: Decodable { let replyText: String; let lastEdited: Timestamp? }
        struct Response: Decodable { let result: Result }

        guard body.count <= 350 else {
            throw GooglePlayError.message("Google Play replies can be at most 350 characters.")
        }
        let payload = try JSONEncoder().encode(["replyText": body])
        let response: Response = try await request(
            base: Self.publisherBase,
            path: "/applications/\(Self.pathSegment(packageName))/reviews/\(Self.pathSegment(reviewID)):reply",
            method: "POST",
            body: payload
        )
        return GooglePlayReplyResult(body: response.result.replyText,
                                     editedAt: response.result.lastEdited?.date ?? Date())
    }

    private func request<Response: Decodable>(base: String,
                                               path: String,
                                               query: [URLQueryItem] = [],
                                               method: String = "GET",
                                               body: Data? = nil,
                                               emptyResponse: Response? = nil,
                                               authRetried: Bool = false,
                                               transientAttempt: Int = 0) async throws -> Response {
        guard var components = URLComponents(string: base + path) else {
            throw GooglePlayError.message("StoreGauge produced an invalid Google API URL.")
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw GooglePlayError.message("StoreGauge produced an invalid Google API URL.")
        }

        let operation = Self.responseContext(for: path)
        let token: String
        do {
            token = try await GoogleOAuth.accessToken(for: credentials, scopes: scopes)
        } catch {
            DiagnosticLog.record("Google Play · \(operation) · OAuth failed · \(error.localizedDescription)")
            throw error
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if !Task.isCancelled, transientAttempt < Self.maximumTransientRetries {
                let delay = Self.retryDelay(attempt: transientAttempt, response: nil)
                DiagnosticLog.record("Google Play · \(operation) · Network failed · retrying in \(Int(delay))s · \(error.localizedDescription)")
                try await Task.sleep(for: .seconds(delay))
                return try await self.request(base: base, path: path, query: query,
                                              method: method, body: body,
                                              emptyResponse: emptyResponse,
                                              authRetried: authRetried,
                                              transientAttempt: transientAttempt + 1)
            }
            DiagnosticLog.record("Google Play · \(operation) · Network failed after retries · \(error.localizedDescription)")
            throw GooglePlayError.message(Self.automaticRetryDetail(
                "Google Play network error: \(error.localizedDescription)"
            ))
        }
        guard let http = response as? HTTPURLResponse else {
            DiagnosticLog.record("Google Play · \(operation) · No HTTP response")
            throw GooglePlayError.message("Google Play returned no HTTP response.")
        }

        switch http.statusCode {
        case 200...299:
            do {
                let decoded = try GooglePlayResponseDecoder.decode(Response.self, from: data,
                                                                   emptyResponse: emptyResponse)
                if data.isEmpty {
                    DiagnosticLog.record("Google Play · \(operation) · HTTP \(http.statusCode) · no content")
                } else {
                    DiagnosticLog.record("Google Play · \(operation) · HTTP \(http.statusCode) · decoded \(data.count) bytes")
                }
                return decoded
            }
            catch {
                let detail = Self.decodingDetail(error)
                let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "unknown content type"
                DiagnosticLog.record("Google Play · \(operation) · HTTP \(http.statusCode) · Decode failed · \(detail) · \(data.count) bytes · \(contentType)")
                throw GooglePlayError.message(
                    "Google Play couldn’t read the \(Self.responseName(for: path)) response: \(detail)"
                )
            }
        case 401:
            DiagnosticLog.record("Google Play · \(operation) · HTTP 401 · refreshing OAuth token")
            GoogleOAuth.invalidate(clientEmail: credentials.clientEmail)
            if !authRetried {
                return try await self.request(base: base, path: path, query: query,
                                              method: method, body: body,
                                              emptyResponse: emptyResponse,
                                              authRetried: true,
                                              transientAttempt: transientAttempt)
            }
            throw GooglePlayError.from(data: data, statusCode: 401,
                                       fallback: "Google authentication failed. Check the service-account key.")
        case 408, 429, 500, 502, 503, 504:
            let error = GooglePlayError.from(data: data, statusCode: http.statusCode,
                                             fallback: "Google Play request failed (HTTP \(http.statusCode)).")
            if transientAttempt < Self.maximumTransientRetries {
                let delay = Self.retryDelay(attempt: transientAttempt, response: http)
                DiagnosticLog.record("Google Play · \(operation) · HTTP \(http.statusCode) · retrying in \(Int(delay))s · \(error.detail)")
                try await Task.sleep(for: .seconds(delay))
                return try await self.request(base: base, path: path, query: query,
                                              method: method, body: body,
                                              emptyResponse: emptyResponse,
                                              authRetried: authRetried,
                                              transientAttempt: transientAttempt + 1)
            }
            DiagnosticLog.record("Google Play · \(operation) · HTTP \(http.statusCode) · failed after retries · \(error.detail)")
            throw GooglePlayError.message(
                Self.automaticRetryDetail(error.detail),
                statusCode: http.statusCode
            )
        default:
            let error = GooglePlayError.from(data: data, statusCode: http.statusCode,
                                             fallback: "Google Play request failed (HTTP \(http.statusCode)).")
            DiagnosticLog.record("Google Play · \(operation) · HTTP \(http.statusCode) · \(error.detail)")
            throw error
        }
    }

    private static func pathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func retryDelay(attempt: Int, response: HTTPURLResponse?) -> Double {
        if let retryAfter = response?.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(retryAfter) {
            return min(max(seconds, 1), 30)
        }
        return min(pow(2, Double(attempt)), 30)
    }

    private static func automaticRetryDetail(_ detail: String) -> String {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = trimmed.last.map { ".!?".contains($0) } == true ? "" : "."
        return "\(trimmed)\(separator) StoreGauge will retry automatically."
    }

    private static func responseName(for path: String) -> String {
        if path.hasSuffix("/reviews") { return "reviews" }
        if path.contains("/tracks/") { return "production release" }
        if path == "/apps:search" { return "app discovery" }
        if path.contains("crashRateMetricSet") { return "crash rate" }
        if path.contains("anrRateMetricSet") { return "ANR rate" }
        if path.hasSuffix(":reply") { return "review reply" }
        return "API"
    }

    private static func responseContext(for path: String) -> String {
        let name = responseName(for: path)
        let parts = path.split(separator: "/")
        if parts.count >= 2, parts[0] == "apps" {
            let package = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            return "\(name) · \(package)"
        }
        guard parts.count >= 2, parts[0] == "applications" else { return name }
        let package = String(parts[1]).removingPercentEncoding ?? String(parts[1])
        return "\(name) · \(package)"
    }

    private static func decodingDetail(_ error: Error) -> String {
        guard let error = error as? DecodingError else {
            return error.localizedDescription
        }
        let context: DecodingError.Context
        let description: String
        switch error {
        case .typeMismatch(let type, let value):
            context = value
            description = "expected \(type)"
        case .valueNotFound(let type, let value):
            context = value
            description = "missing \(type) value"
        case .keyNotFound(let key, let value):
            context = value
            description = "missing field ‘\(key.stringValue)’"
        case .dataCorrupted(let value):
            context = value
            description = value.debugDescription
        default:
            return error.localizedDescription
        }
        let path = context.codingPath.map { key in
            key.intValue.map { "[\($0)]" } ?? key.stringValue
        }.joined(separator: ".")
        return path.isEmpty ? description : "\(path): \(description)"
    }
}

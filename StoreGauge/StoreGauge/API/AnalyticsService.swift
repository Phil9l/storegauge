//
//  AnalyticsService.swift
//  StoreGauge
//
//  Best-effort access to App Store Connect Analytics Reports (downloads, sessions,
//  active devices). This API is asynchronous: you register a report request and
//  Apple generates the data over the following hours/days, so results populate
//  progressively. Everything here is defensive and non-fatal — a failure never
//  breaks the primary sync.
//

import Foundation

struct AnalyticsPoint: Sendable {
    let date: Date
    let kind: MetricKind
    let value: Double
}

@MainActor
final class AnalyticsService {
    let client: ASCClient
    init(client: ASCClient) { self.client = client }

    /// Finds an existing ONE_TIME_SNAPSHOT report request for the app, creating one
    /// if needed (which asks Apple to start generating ~a year of history).
    @discardableResult
    func ensureSnapshotRequest(appID: String) async throws -> String? {
        let existing = try await client.rawGet(
            path: "/v1/apps/\(appID)/analyticsReportRequests",
            query: [URLQueryItem(name: "filter[accessType]", value: "ONE_TIME_SNAPSHOT")])
        if let list = try? JSONDecoder().decode(ASCListResponse<AnalyticsReportRequestAttributes>.self, from: existing),
           let first = list.data.first(where: { $0.attributes?.stoppedDueToInactivity != true }) ?? list.data.first {
            return first.id
        }
        // Create one.
        let created = try await client.rawPost(path: "/v1/analyticsReportRequests", json: [
            "data": [
                "type": "analyticsReportRequests",
                "attributes": ["accessType": "ONE_TIME_SNAPSHOT"],
                "relationships": ["app": ["data": ["type": "apps", "id": appID]]],
            ]
        ])
        let single = try? JSONDecoder().decode(ASCSingleResponse<AnalyticsReportRequestAttributes>.self, from: created)
        return single?.data.id
    }

    private struct ReportMatch { let id: String; let kinds: [MetricKind]; let columns: [MetricKind: [String]]; var isEngagement = false }

    /// Fetches recent daily metrics. Returns [] when Apple hasn't generated data yet.
    func recentMetrics(appID: String, maxInstancesPerReport: Int = 8) async throws -> [AnalyticsPoint] {
        guard let requestID = try await ensureSnapshotRequest(appID: appID) else { return [] }

        let reportsData = try await client.rawGet(
            path: "/v1/analyticsReportRequests/\(requestID)/reports",
            query: [URLQueryItem(name: "fields[analyticsReports]", value: "name,category"),
                    URLQueryItem(name: "limit", value: "200")])
        guard let reports = try? JSONDecoder().decode(ASCListResponse<AnalyticsReportAttributes>.self, from: reportsData) else {
            return []
        }

        var matches: [ReportMatch] = []
        for r in reports.data {
            let name = (r.attributes?.name ?? "").lowercased()
            if name.contains("install") || name.contains("download") {
                matches.append(ReportMatch(id: r.id, kinds: [.installs],
                    columns: [.installs: ["counts", "installations", "total downloads", "downloads", "units"]]))
            } else if name.contains("session") {
                matches.append(ReportMatch(id: r.id, kinds: [.sessions, .activeDevices],
                    columns: [.sessions: ["sessions", "counts"], .activeDevices: ["unique devices", "active devices", "devices"]]))
            } else if name.contains("discovery") || name.contains("engagement") {
                matches.append(ReportMatch(id: r.id, kinds: [.impressions, .pageViews], columns: [:], isEngagement: true))
            }
        }

        var points: [AnalyticsPoint] = []
        for match in matches {
            let instData = try await client.rawGet(
                path: "/v1/analyticsReports/\(match.id)/instances",
                query: [URLQueryItem(name: "filter[granularity]", value: "DAILY"),
                        URLQueryItem(name: "limit", value: String(maxInstancesPerReport))])
            guard let instances = try? JSONDecoder().decode(ASCListResponse<AnalyticsReportInstanceAttributes>.self, from: instData) else { continue }

            for inst in instances.data {
                let segData = try await client.rawGet(path: "/v1/analyticsReportInstances/\(inst.id)/segments",
                    query: [URLQueryItem(name: "fields[analyticsReportSegments]", value: "url,sizeInBytes,checksum")])
                guard let segs = try? JSONDecoder().decode(ASCListResponse<AnalyticsReportSegmentAttributes>.self, from: segData) else { continue }
                for seg in segs.data {
                    guard let urlStr = seg.attributes?.url,
                          let csv = try? await client.downloadSegment(urlStr),
                          let text = String(data: csv, encoding: .utf8) else { continue }
                    points.append(contentsOf: match.isEngagement ? parseEngagement(text) : parse(text, match: match))
                }
            }
        }
        return points
    }

    private func parse(_ text: String, match: ReportMatch) -> [AnalyticsPoint] {
        var lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }
        let delim: Character = lines[0].contains("\t") ? "\t" : ","
        let header = lines.removeFirst().split(separator: delim, omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        guard let dateIdx = header.firstIndex(where: { $0 == "date" }) else { return [] }

        // Resolve a column index for each metric this report can supply.
        var metricCols: [(MetricKind, Int)] = []
        for kind in match.kinds {
            let candidates = match.columns[kind] ?? []
            if let col = header.firstIndex(where: { h in candidates.contains(h) }) {
                metricCols.append((kind, col))
            }
        }
        guard !metricCols.isEmpty else { return [] }

        var totals: [MetricKind: [Date: Double]] = [:]
        for line in lines {
            let cols = line.split(separator: delim, omittingEmptySubsequences: false).map { String($0) }
            guard cols.count > dateIdx else { continue }
            guard let day = DayFormatter.date(from: cols[dateIdx].trimmingCharacters(in: .whitespaces)) else { continue }
            for (kind, idx) in metricCols where cols.count > idx {
                let v = Double(cols[idx].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")) ?? 0
                totals[kind, default: [:]][day, default: 0] += v
            }
        }
        return totals.flatMap { kind, byDay in
            byDay.map { AnalyticsPoint(date: $0.key, kind: kind, value: $0.value) }
        }
    }

    /// Parses the App Store Discovery & Engagement report (impressions / page views),
    /// which may express those either as an "Event" dimension or as columns.
    private func parseEngagement(_ text: String) -> [AnalyticsPoint] {
        var lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }
        let delim: Character = lines[0].contains("\t") ? "\t" : ","
        let header = lines.removeFirst().split(separator: delim, omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        guard let dateIdx = header.firstIndex(of: "date") else { return [] }
        let countsIdx = header.firstIndex { ["counts", "count", "value"].contains($0) }
        let eventIdx = header.firstIndex { $0.contains("event") || $0.contains("engagement") || $0 == "page type" }
        let impCol = header.firstIndex { $0 == "impressions" || $0 == "impressions total" || $0 == "unique impressions" }
        let pvCol = header.firstIndex { $0.contains("product page view") || $0 == "page views" }

        func num(_ cols: [String], _ i: Int?) -> Double {
            guard let i, cols.count > i else { return 0 }
            return Double(cols[i].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")) ?? 0
        }

        var totals: [MetricKind: [Date: Double]] = [:]
        for line in lines {
            let cols = line.split(separator: delim, omittingEmptySubsequences: false).map { String($0) }
            guard cols.count > dateIdx,
                  let day = DayFormatter.date(from: cols[dateIdx].trimmingCharacters(in: .whitespaces)) else { continue }
            if impCol != nil || pvCol != nil {
                if impCol != nil { totals[.impressions, default: [:]][day, default: 0] += num(cols, impCol) }
                if pvCol != nil { totals[.pageViews, default: [:]][day, default: 0] += num(cols, pvCol) }
            } else if let eventIdx, cols.count > eventIdx {
                let ev = cols[eventIdx].lowercased()
                let c = num(cols, countsIdx)
                if ev.contains("impression") { totals[.impressions, default: [:]][day, default: 0] += c }
                else if ev.contains("page view") { totals[.pageViews, default: [:]][day, default: 0] += c }
            }
        }
        return totals.flatMap { kind, byDay in
            byDay.map { AnalyticsPoint(date: $0.key, kind: kind, value: $0.value) }
        }
    }
}

//
//  Aggregations.swift
//  StoreGauge
//
//  Turns stored MetricPoints into chart-ready series and totals across a set of
//  apps, converting proceeds into a single display currency.
//

import Foundation

struct DatedValue: Identifiable, Sendable {
    let date: Date
    let value: Double
    var id: Date { date }
}

struct AppValue: Identifiable {
    let app: TrackedApp
    let value: Double
    var id: UUID { app.id }
}

@MainActor
struct MetricsAggregator {
    let apps: [TrackedApp]
    let fx: FXService
    let currency: String

    static func dayBuckets(days: Int) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    /// Converts one monetary point into the display currency.
    private func converted(_ point: MetricPoint) -> Double {
        guard point.kind == .proceeds || point.kind == .grossSales || point.kind == .netEarnings else {
            return point.value
        }
        let from = point.currency ?? currency
        return fx.convert(point.value, from: from, to: currency) ?? (from == currency ? point.value : 0)
    }

    // MARK: Series

    func series(_ kind: MetricKind, days: Int) -> [DatedValue] {
        let buckets = Self.dayBuckets(days: days)
        var map: [Date: Double] = [:]
        let cutoff = buckets.first ?? Date.daysAgo(days)
        for app in apps {
            for m in app.metrics where m.kind == kind && m.date >= cutoff {
                map[m.date.startOfDayUTC, default: 0] += converted(m)
            }
        }
        return buckets.map { DatedValue(date: $0, value: map[$0] ?? 0) }
    }

    /// Per-day mean across apps that actually reported a point. Rates cannot be
    /// summed across apps, and Google does not expose enough detail here for a
    /// user-weighted aggregate.
    func averageSeries(_ kind: MetricKind, days: Int) -> [DatedValue] {
        let buckets = Self.dayBuckets(days: days)
        let cutoff = buckets.first ?? Date.daysAgo(days)
        var valuesByDay: [Date: [Double]] = [:]
        for app in apps {
            var appByDay: [Date: Double] = [:]
            for metric in app.metrics where metric.kind == kind && metric.date >= cutoff {
                appByDay[metric.date.startOfDayUTC, default: 0] += converted(metric)
            }
            for (day, value) in appByDay { valuesByDay[day, default: []].append(value) }
        }
        return buckets.map { day in
            let values = valuesByDay[day] ?? []
            return DatedValue(date: day,
                              value: values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count))
        }
    }

    func reportedAverageSeries(_ kind: MetricKind, days: Int) -> [DatedValue] {
        let series = averageSeries(kind, days: days)
        let latest = apps.flatMap(\.metrics)
            .filter { $0.kind == kind }
            .map { $0.date.startOfDayUTC }
            .max()
        guard let latest else { return [] }
        return series.filter { $0.date <= latest }
    }

    // MARK: Totals & deltas

    private func sum(_ kind: MetricKind, start: Date, endExclusive: Date) -> Double {
        var total = 0.0
        for app in apps {
            for m in app.metrics where m.kind == kind && m.date >= start && m.date < endExclusive {
                total += converted(m)
            }
        }
        return total
    }

    func total(_ kind: MetricKind, days: Int) -> Double {
        let buckets = Self.dayBuckets(days: days)
        guard let start = buckets.first else { return 0 }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let end = cal.date(byAdding: .day, value: 1, to: buckets.last ?? start) ?? Date()
        return sum(kind, start: start, endExclusive: end)
    }

    /// Fractional change of the most recent `days` window vs the preceding one.
    func delta(_ kind: MetricKind, days: Int) -> Double? {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.startOfDay(for: Date())
        guard let recentStart = cal.date(byAdding: .day, value: -(days - 1), to: today),
              let prevStart = cal.date(byAdding: .day, value: -(2 * days - 1), to: today),
              let end = cal.date(byAdding: .day, value: 1, to: today) else { return nil }
        let recent = sum(kind, start: recentStart, endExclusive: end)
        let previous = sum(kind, start: prevStart, endExclusive: recentStart)
        guard previous > 0 else { return nil }
        return (recent - previous) / previous
    }

    /// Two 7-day totals (recent, previous) for a sales metric, anchored to the last
    /// *reported* day rather than today — so the 1–2 day reporting lag (trailing days
    /// still missing) doesn't masquerade as a downturn. `nil` if there's no data yet.
    func weekOverWeekSales(_ kind: MetricKind) -> (recent: Double, previous: Double)? {
        guard let anchor = lastSalesDay else { return nil }
        let points = apps.flatMap(\.metrics)
            .filter { $0.kind == kind }
            .map { (date: $0.date.startOfDayUTC, value: converted($0)) }
        return SalesWindows.weekOverWeek(points, anchor: anchor)
    }

    // MARK: Per-app breakdown

    func byApp(_ kind: MetricKind, days: Int) -> [AppValue] {
        let buckets = Self.dayBuckets(days: days)
        let cutoff = buckets.first ?? Date.daysAgo(days)
        return apps.map { app in
            let v = app.metrics.filter { $0.kind == kind && $0.date >= cutoff }.reduce(0.0) { $0 + converted($1) }
            return AppValue(app: app, value: v)
        }
        .sorted { $0.value > $1.value }
    }

    func hasAny(_ kind: MetricKind) -> Bool {
        apps.contains { app in app.metrics.contains { $0.kind == kind } }
    }

    var hasDownloads: Bool {
        hasAny(.units) || hasAny(.installs)
    }

    /// A store-neutral downloads series. Apple Sales units already include app
    /// updates; Google statistics export new user installs and device upgrades
    /// separately, so the latter are combined here.
    func downloadSeries(days: Int) -> [DatedValue] {
        let (new, updates) = installBreakdown(days: days)
        let updatesByDay = Dictionary(updates.map { ($0.date, $0.value) },
                                      uniquingKeysWith: +)
        return new.map { point in
            DatedValue(date: point.date, value: point.value + (updatesByDay[point.date] ?? 0))
        }
    }

    func downloadTotal(days: Int) -> Double {
        downloadSeries(days: days).reduce(0) { $0 + $1.value }
    }

    func downloadDelta(days: Int) -> Double? {
        // Request spare leading days because both stores can publish with a lag;
        // compare the latest two complete windows rather than ending at today.
        let values = downloadSeries(days: days * 2 + 14).map(\.value)
        guard values.count >= days * 2 else { return nil }
        let previous = values.prefix(days).reduce(0, +)
        let recent = values.suffix(days).reduce(0, +)
        guard previous > 0 else { return nil }
        return (recent - previous) / previous
    }

    func weekOverWeekDownloads() -> (recent: Double, previous: Double)? {
        let values = downloadSeries(days: 30).map(\.value)
        guard values.count >= 14 else { return nil }
        let window = values.suffix(14)
        return (window.suffix(7).reduce(0, +), window.prefix(7).reduce(0, +))
    }

    /// The most recent day for which Apple has actually reported sales. Trailing
    /// days beyond this haven't been published yet and shouldn't be drawn as 0.
    var lastSalesDay: Date? {
        var latest: Date?
        for app in apps {
            for m in app.metrics where m.kind == .units || m.kind == .proceeds {
                let d = m.date.startOfDayUTC
                if latest == nil || d > latest! { latest = d }
            }
        }
        return latest
    }

    /// A sales-based series trimmed to the last reported day (no phantom trailing 0s).
    func salesSeries(_ kind: MetricKind, days: Int) -> [DatedValue] {
        let s = series(kind, days: days)
        guard let cutoff = lastSalesDay else { return s }
        return s.filter { $0.date <= cutoff }
    }

    /// A report-backed series trimmed to its most recent imported day.
    func reportedSeries(_ kind: MetricKind, days: Int) -> [DatedValue] {
        let s = series(kind, days: days)
        let latest = apps.flatMap(\.metrics)
            .filter { $0.kind == kind }
            .map { $0.date.startOfDayUTC }
            .max()
        guard let latest else { return s }
        return s.filter { $0.date <= latest }
    }

    /// Splits downloads into installs vs updates. Apple Sales reports total units,
    /// so updates are subtracted; Google's export supplies the two values directly.
    func installBreakdown(days: Int) -> (new: [DatedValue], updates: [DatedValue]) {
        let buckets = Self.dayBuckets(days: days)
        let cutoff = buckets.first ?? Date.daysAgo(days)
        var newByDay: [Date: Double] = [:]
        var updatesByDay: [Date: Double] = [:]
        var latest: Date?

        for app in apps {
            let usesGoogleStatistics = app.metrics.contains {
                $0.kind == .installs && $0.sourceRaw == MetricSource.googleStatistics.rawValue
            }
            let units = app.metrics.filter { $0.kind == .units && $0.date >= cutoff }
            let installs = app.metrics.filter { $0.kind == .installs && $0.date >= cutoff }
            let updates = app.metrics.filter { $0.kind == .updates && $0.date >= cutoff }
            let updateMap = Dictionary(grouping: updates, by: { $0.date.startOfDayUTC })
                .mapValues { $0.reduce(0) { $0 + converted($1) } }

            if usesGoogleStatistics {
                for point in installs {
                    let day = point.date.startOfDayUTC
                    newByDay[day, default: 0] += converted(point)
                    if latest == nil || day > latest! { latest = day }
                }
                for (day, value) in updateMap {
                    updatesByDay[day, default: 0] += value
                    if latest == nil || day > latest! { latest = day }
                }
            } else if !units.isEmpty {
                let unitMap = Dictionary(grouping: units, by: { $0.date.startOfDayUTC })
                    .mapValues { $0.reduce(0) { $0 + converted($1) } }
                for (day, value) in unitMap {
                    let updateValue = updateMap[day] ?? 0
                    newByDay[day, default: 0] += max(0, value - updateValue)
                    updatesByDay[day, default: 0] += updateValue
                    if latest == nil || day > latest! { latest = day }
                }
            } else {
                for point in installs {
                    let day = point.date.startOfDayUTC
                    newByDay[day, default: 0] += converted(point)
                    if latest == nil || day > latest! { latest = day }
                }
            }
        }

        var new = buckets.map { DatedValue(date: $0, value: newByDay[$0] ?? 0) }
        var updates = buckets.map { DatedValue(date: $0, value: updatesByDay[$0] ?? 0) }
        if let latest {
            new = new.filter { $0.date <= latest }
            updates = updates.filter { $0.date <= latest }
        }
        return (new, updates)
    }
}

/// Pure week-over-week window math, split out from `MetricsAggregator` so the boundary
/// logic is unit-testable without a SwiftData store.
enum SalesWindows {
    /// Sums pre-converted dated values into two adjacent 7-day windows:
    /// `recent` = [anchor−6 … anchor], `previous` = [anchor−13 … anchor−7]. Anchoring to
    /// the last *reported* day (not today) stops the reporting lag looking like a slump.
    nonisolated static func weekOverWeek(_ points: [(date: Date, value: Double)],
                                         anchor: Date) -> (recent: Double, previous: Double) {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        guard let recentStart = cal.date(byAdding: .day, value: -6, to: anchor),
              let recentEnd = cal.date(byAdding: .day, value: 1, to: anchor),      // exclusive
              let prevStart = cal.date(byAdding: .day, value: -13, to: anchor) else { return (0, 0) }
        var recent = 0.0, previous = 0.0
        for p in points {
            if p.date >= recentStart && p.date < recentEnd { recent += p.value }
            else if p.date >= prevStart && p.date < recentStart { previous += p.value }
        }
        return (recent, previous)
    }
}

/// Monthly average rating from a set of reviews, oldest → newest.
@MainActor
func ratingTrend(_ reviews: [Review]) -> [DatedValue] {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let byMonth = Dictionary(grouping: reviews.filter { $0.rating > 0 }) { r -> Date in
        cal.date(from: cal.dateComponents([.year, .month], from: r.createdDate)) ?? r.createdDate
    }
    return byMonth.map { month, revs in
        DatedValue(date: month, value: Double(revs.reduce(0) { $0 + $1.rating }) / Double(revs.count))
    }
    .sorted { $0.date < $1.date }
}

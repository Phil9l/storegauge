//
//  OverviewView.swift
//  StoreGauge
//
//  Aggregated dashboard across the selected apps: KPIs, charts, status & reviews.
//

import SwiftUI
import SwiftData

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \TrackedApp.name) private var allApps: [TrackedApp]
    @State private var rangeDays = 30

    private var settings: AppSettings { model.settings }
    private var visibleApps: [TrackedApp] { allApps.filter { !$0.isArchived } }
    private var selectedApps: [TrackedApp] { visibleApps.filter { $0.isSelected } }
    private var hasAppleSales: Bool { selectedApps.contains { $0.capabilities.contains(.sales) } }
    private var hasStabilityData: Bool { agg.hasAny(.crashRate) || agg.hasAny(.anrRate) }
    private var hasGoogleFinancialData: Bool {
        agg.hasAny(.grossSales) || agg.hasAny(.netEarnings) || agg.hasAny(.orders)
    }
    private var agg: MetricsAggregator {
        MetricsAggregator(apps: selectedApps, fx: model.fx, currency: settings.displayCurrency)
    }
    private var reviews: [Review] { selectedApps.flatMap { $0.reviews } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                appFilter
                if selectedApps.isEmpty {
                    EmptyStateView(symbol: "line.3.horizontal.decrease.circle",
                                   title: "No apps selected",
                                   message: "Pick one or more apps above to see combined stats.")
                        .frame(height: 300)
                } else {
                    kpiGrid
                    if hasAppleSales { proceedsCard }
                    if agg.hasDownloads {
                        HStack(alignment: .top, spacing: 14) {
                            downloadsCard
                            statusCard
                        }
                    } else {
                        statusCard
                    }
                    if hasGoogleFinancialData { googleFinancialCard }
                    if hasStabilityData { stabilityCard }
                    if agg.hasAny(.activeDevices) || agg.hasAny(.sessions) {
                        HStack(alignment: .top, spacing: 14) {
                            if agg.hasAny(.activeDevices) { usageCard(.activeDevices) }
                            if agg.hasAny(.sessions) { usageCard(.sessions) }
                        }
                    }
                    if agg.hasAny(.impressions) {
                        FunnelCard(impressions: agg.total(.impressions, days: rangeDays),
                                   pageViews: agg.total(.pageViews, days: rangeDays),
                                   downloads: agg.downloadTotal(days: rangeDays))
                    }
                    HStack(alignment: .top, spacing: 14) {
                        ratingsCard
                        if hasAppleSales { topAppsCard }
                        else { reviewVolumeCard }
                    }
                    if ratingTrendData.count >= 2 { ratingTrendCard }
                    if !territoryStats.isEmpty { territoriesCard }
                    activityCard
                }
            }
            .padding(20)
        }
        .background(.windowFill)
        .navigationTitle("Overview")
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Overview").font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("\(selectedApps.count) of \(visibleApps.count) apps · \(settings.displayCurrency) · \(model.fx.usingLiveRates ? "live rates" : "approx. rates")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $rangeDays) {
                Text("7D").tag(7)
                Text("30D").tag(30)
                Text("90D").tag(90)
            }
            .pickerStyle(.segmented).fixedSize()
        }
    }

    // MARK: App filter chips

    private var appFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button("All") { setAll(true) }.buttonStyle(.link).font(.caption)
                Button("None") { setAll(false) }.buttonStyle(.link).font(.caption)
                Divider().frame(height: 16)
                ForEach(visibleApps) { app in
                    FilterChip(title: app.name, isOn: app.isSelected, color: app.state.color) {
                        app.isSelected.toggle()
                        try? model.context.save()
                        model.recomputeBadges()
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func setAll(_ on: Bool) {
        for app in visibleApps { app.isSelected = on }
        try? model.context.save()
        model.recomputeBadges()
    }

    // MARK: KPIs

    private var avgRating: Double {
        let rated = reviews.filter { $0.rating > 0 }
        guard !rated.isEmpty else { return 0 }
        return Double(rated.reduce(0) { $0 + $1.rating }) / Double(rated.count)
    }

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
            if hasAppleSales {
                KPITile(title: "Proceeds", value: Format.currency(agg.total(.proceeds, days: rangeDays), code: settings.displayCurrency),
                        delta: agg.delta(.proceeds, days: rangeDays), symbol: "dollarsign.circle.fill", tint: .green,
                        spark: sparkValues(.proceeds))
            }
            if agg.hasDownloads {
                KPITile(title: "Downloads", value: Format.int(agg.downloadTotal(days: rangeDays)),
                        delta: agg.downloadDelta(days: rangeDays), symbol: "arrow.down.circle.fill", tint: .blue,
                        spark: Array(agg.downloadSeries(days: min(rangeDays, 14)).map(\.value)))
            }
            if hasGoogleFinancialData {
                KPITile(title: "Google Play Gross Sales",
                        value: Format.currency(agg.total(.grossSales, days: rangeDays), code: settings.displayCurrency),
                        delta: agg.delta(.grossSales, days: rangeDays), symbol: MetricKind.grossSales.symbol,
                        tint: .mint, spark: sparkValues(.grossSales))
                KPITile(title: "Google Play Earnings",
                        value: Format.currency(agg.total(.netEarnings, days: rangeDays), code: settings.displayCurrency),
                        subtitle: "finalized monthly", symbol: MetricKind.netEarnings.symbol, tint: .green)
            }
            if agg.hasAny(.activeDevices) {
                KPITile(title: "Active Devices", value: Format.compact(latest(.activeDevices)),
                        subtitle: "most recent day", symbol: "iphone.gen3", tint: .purple,
                        spark: sparkValues(.activeDevices))
            }
            if agg.hasAny(.crashRate) {
                KPITile(title: "Crash Rate", value: latestRate(.crashRate),
                        subtitle: "latest reported day", symbol: MetricKind.crashRate.symbol, tint: .red,
                        spark: Array(agg.reportedAverageSeries(.crashRate, days: min(rangeDays, 14)).map(\.value)))
            }
            if agg.hasAny(.anrRate) {
                KPITile(title: "ANR Rate", value: latestRate(.anrRate),
                        subtitle: "latest reported day", symbol: MetricKind.anrRate.symbol, tint: .orange,
                        spark: Array(agg.reportedAverageSeries(.anrRate, days: min(rangeDays, 14)).map(\.value)))
            }
            KPITile(title: "Avg Rating", value: avgRating > 0 ? String(format: "%.2f", avgRating) : "—",
                    subtitle: "\(reviews.count) reviews", symbol: "star.fill", tint: .yellow)
            KPITile(title: "Needs Reply", value: "\(model.untriagedCount)",
                    subtitle: "unanswered reviews", symbol: "exclamationmark.bubble.fill", tint: .orange)
            KPITile(title: "Response Rate", value: reviews.isEmpty ? "—" : Format.percentPlain(responseRate),
                    subtitle: "\(answeredCount) answered", symbol: "arrowshape.turn.up.left.fill", tint: .green)
        }
    }

    private var answeredCount: Int { reviews.filter { $0.hasResponse }.count }
    private var responseRate: Double { reviews.isEmpty ? 0 : Double(answeredCount) / Double(reviews.count) }

    private func sparkValues(_ kind: MetricKind) -> [Double] {
        Array(agg.series(kind, days: min(rangeDays, 14)).map(\.value))
    }

    private func latest(_ kind: MetricKind) -> Double {
        agg.series(kind, days: rangeDays).last(where: { $0.value > 0 })?.value ?? 0
    }

    private func latestRate(_ kind: MetricKind) -> String {
        guard let value = agg.reportedAverageSeries(kind, days: rangeDays).last?.value else { return "—" }
        return Format.percentRate(value)
    }

    // MARK: Cards

    private var proceedsCard: some View {
        ChartCard(title: "Proceeds", symbol: "dollarsign.circle.fill",
                  subtitle: Format.currency(agg.total(.proceeds, days: rangeDays), code: settings.displayCurrency)) {
            TrendChart(series: agg.salesSeries(.proceeds, days: rangeDays), tint: .green,
                       isCurrency: true, currencyCode: settings.displayCurrency)
                .frame(height: 200)
            if !agg.hasAny(.proceeds) { incomeHint }
        }
    }

    private var googleFinancialCard: some View {
        HStack(alignment: .top, spacing: 14) {
            ChartCard(title: "Google Play Gross Sales", symbol: "cart.circle.fill",
                      subtitle: "buyer spend before taxes and fees") {
                TrendChart(series: agg.reportedSeries(.grossSales, days: rangeDays), tint: .mint,
                           isCurrency: true, currencyCode: settings.displayCurrency).frame(height: 180)
            }
            ChartCard(title: "Google Play Finalized Earnings", symbol: "banknote.fill",
                      subtitle: "monthly earnings report") {
                TrendChart(series: agg.reportedSeries(.netEarnings, days: rangeDays), tint: .green,
                           isCurrency: true, currencyCode: settings.displayCurrency).frame(height: 180)
            }
        }
    }

    private var hasVendor: Bool {
        model.accounts().contains { ($0.vendorNumber?.trimmingCharacters(in: .whitespaces).isEmpty == false) }
    }

    @ViewBuilder private var incomeHint: some View {
        if hasVendor {
            Label("No proceeds in this period. Free apps report downloads (not revenue) — see the Downloads card.",
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Label("Add a vendor number to your account in Settings to see income.",
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var downloadsCard: some View {
        let (newS, upd) = agg.installBreakdown(days: rangeDays)
        let updTotal = upd.reduce(0) { $0 + $1.value }
        let newTotal = newS.reduce(0) { $0 + $1.value }
        return ChartCard(title: "Downloads", symbol: "arrow.down.circle.fill",
                         subtitle: Format.int(agg.downloadTotal(days: rangeDays))) {
            if updTotal > 0 {
                StackedBarChart(series: [
                    .init(id: "new", name: "New installs (\(Format.compact(newTotal)))", color: .blue, points: newS),
                    .init(id: "updates", name: "Updates (\(Format.compact(updTotal)))", color: .teal, points: upd),
                ]).frame(height: 180)
            } else {
                BarTrendChart(series: agg.downloadSeries(days: rangeDays), tint: .blue).frame(height: 180)
            }
        }
    }

    private var stabilityCard: some View {
        HStack(alignment: .top, spacing: 14) {
            if agg.hasAny(.crashRate) {
                ChartCard(title: "Crash Rate", symbol: MetricKind.crashRate.symbol,
                          subtitle: "average across reporting apps") {
                    TrendChart(series: agg.reportedAverageSeries(.crashRate, days: rangeDays),
                               tint: .red, isPercentage: true).frame(height: 180)
                }
            }
            if agg.hasAny(.anrRate) {
                ChartCard(title: "ANR Rate", symbol: MetricKind.anrRate.symbol,
                          subtitle: "average across reporting apps") {
                    TrendChart(series: agg.reportedAverageSeries(.anrRate, days: rangeDays),
                               tint: .orange, isPercentage: true).frame(height: 180)
                }
            }
        }
    }

    private func usageCard(_ kind: MetricKind) -> some View {
        ChartCard(title: kind.title, symbol: kind.symbol,
                  subtitle: Format.compact(agg.total(kind, days: rangeDays))) {
            TrendChart(series: agg.series(kind, days: rangeDays), tint: kind.color)
                .frame(height: 180)
        }
    }

    private var statusCard: some View {
        ChartCard(title: "App Status", symbol: "circle.badge.checkmark") {
            let slices = statusSlices
            HStack(spacing: 16) {
                StatusDonut(slices: slices).frame(width: 130, height: 130)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(slices) { slice in
                        HStack(spacing: 6) {
                            Circle().fill(slice.category.color).frame(width: 8, height: 8)
                            Text(categoryLabel(slice.category)).font(.caption)
                            Spacer()
                            Text("\(slice.count)").font(.caption.monospacedDigit().weight(.medium))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150)
        }
    }

    private var statusSlices: [StatusDonut.Slice] {
        let groups = Dictionary(grouping: selectedApps) { $0.state.category }
        return groups.map { StatusDonut.Slice(category: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    private func categoryLabel(_ c: AppStoreState.Category) -> String {
        switch c {
        case .live: return "Live"
        case .inReview: return "In Review"
        case .pending: return "Pending"
        case .prepare: return "Preparing"
        case .problem: return "Needs Attention"
        case .removed: return "Removed"
        case .other: return "Other"
        }
    }

    private var ratingsCard: some View {
        ChartCard(title: "Ratings", symbol: "star.fill") {
            HStack(spacing: 18) {
                VStack(spacing: 2) {
                    Text(avgRating > 0 ? String(format: "%.1f", avgRating) : "—")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    StarsView(rating: Int(avgRating.rounded()), size: 11)
                    Text("\(reviews.count) reviews").font(.caption2).foregroundStyle(.secondary)
                }
                RatingBars(counts: ratingCounts).frame(maxWidth: .infinity)
            }
            .frame(minHeight: 130)
        }
    }

    private var ratingCounts: [Int: Int] {
        var c: [Int: Int] = [:]
        for r in reviews where r.rating > 0 { c[r.rating, default: 0] += 1 }
        return c
    }

    private var topAppsCard: some View {
        ChartCard(title: "Top Apps", symbol: "trophy.fill",
                  subtitle: "by proceeds") {
            let rows = agg.byApp(.proceeds, days: rangeDays).filter { $0.value > 0 }.prefix(6)
            if rows.isEmpty {
                Text("No proceeds in this period.").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 130, alignment: .center)
            } else {
                let maxV = rows.map(\.value).max() ?? 1
                VStack(spacing: 8) {
                    ForEach(Array(rows)) { row in
                        HStack(spacing: 8) {
                            AppIconView(app: row.app, size: 22)
                            Text(row.app.name).font(.caption).lineLimit(1).frame(width: 90, alignment: .leading)
                            GeometryReader { geo in
                                Capsule().fill(.green.gradient)
                                    .frame(width: max(3, geo.size.width * CGFloat(row.value / maxV)))
                                    .frame(maxHeight: .infinity, alignment: .leading)
                            }
                            .frame(height: 12)
                            Text(Format.currency(row.value, code: settings.displayCurrency, compact: true))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                }
                .frame(minHeight: 130)
            }
        }
    }

    private var reviewVolumeCard: some View {
        ChartCard(title: "Review Volume", symbol: "bubble.left.and.bubble.right.fill") {
            let rows = selectedApps
                .map { ReviewVolumeRow(app: $0, count: $0.reviews.count) }
                .sorted { $0.count > $1.count }
                .prefix(6)
            if rows.allSatisfy({ $0.count == 0 }) {
                Text("No written reviews synced yet.").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 130, alignment: .center)
            } else {
                let maxCount = max(rows.map(\.count).max() ?? 1, 1)
                VStack(spacing: 8) {
                    ForEach(Array(rows)) { row in
                        HStack(spacing: 8) {
                            AppIconView(app: row.app, size: 22, showsStoreBadge: true)
                            Text(row.app.name).font(.caption).lineLimit(1).frame(width: 90, alignment: .leading)
                            GeometryReader { geo in
                                Capsule().fill(.blue.gradient)
                                    .frame(width: max(3, geo.size.width * CGFloat(row.count) / CGFloat(maxCount)))
                                    .frame(maxHeight: .infinity, alignment: .leading)
                            }
                            .frame(height: 12)
                            Text("\(row.count)")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                }
                .frame(minHeight: 130)
            }
        }
    }

    private struct ReviewVolumeRow: Identifiable {
        let app: TrackedApp
        let count: Int
        var id: UUID { app.id }
    }

    private struct TerritoryStat: Identifiable {
        let code: String; let count: Int; let avg: Double
        var id: String { code }
    }
    private var territoryStats: [TerritoryStat] {
        Dictionary(grouping: reviews.filter { !$0.territory.isEmpty }, by: { $0.territory }).map { code, revs in
            let rated = revs.filter { $0.rating > 0 }
            let avg = rated.isEmpty ? 0 : Double(rated.reduce(0) { $0 + $1.rating }) / Double(rated.count)
            return TerritoryStat(code: code, count: revs.count, avg: avg)
        }
        .sorted { $0.count > $1.count }
    }

    private var territoriesCard: some View {
        ChartCard(title: "Reviews by Country", symbol: "globe",
                  subtitle: "\(territoryStats.count) countries") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 8) {
                ForEach(territoryStats.prefix(12)) { t in
                    HStack(spacing: 8) {
                        Text(flagEmoji(for: t.code)).font(.title3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.code).font(.caption.weight(.medium))
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill").font(.system(size: 7)).foregroundStyle(Int(t.avg.rounded()).ratingColor)
                                Text(String(format: "%.1f", t.avg)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(t.count)").font(.callout.monospacedDigit().weight(.semibold))
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
                }
            }
        }
    }

    private var ratingTrendData: [DatedValue] { ratingTrend(reviews) }
    private var ratingTrendCard: some View {
        ChartCard(title: "Rating Trend", symbol: "chart.line.uptrend.xyaxis", subtitle: "monthly average") {
            TrendChart(series: ratingTrendData, tint: .yellow, yDomain: 1...5).frame(height: 150)
        }
    }

    private var activityCard: some View {
        ChartCard(title: "Recent Activity", symbol: "clock.arrow.circlepath") {
            let items = recentActivity
            if items.isEmpty {
                Text("Nothing yet — sync to pull the latest.").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        ActivityRow(item: item)
                        if item.id != items.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var recentActivity: [ActivityItem] {
        var items: [ActivityItem] = []
        for app in selectedApps {
            for r in app.reviews.sorted(by: { $0.createdDate > $1.createdDate }).prefix(6) {
                items.append(ActivityItem(id: "r-\(r.id)", date: r.createdDate, kind: .review(r), appName: app.name))
            }
            for e in app.statusEvents.sorted(by: { $0.date > $1.date }).prefix(3) {
                items.append(ActivityItem(id: "s-\(e.persistentModelID.hashValue)", date: e.date, kind: .status(e), appName: app.name))
            }
        }
        return Array(items.sorted { $0.date > $1.date }.prefix(10))
    }
}

// MARK: - Chart card container

struct ChartCard<Content: View>: View {
    let title: String
    var symbol: String? = nil
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: title, symbol: symbol)
                Spacer()
                if let subtitle {
                    Text(subtitle).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Activity

struct ActivityItem: Identifiable {
    enum Kind { case review(Review); case status(StatusEvent) }
    let id: String
    let date: Date
    let kind: Kind
    let appName: String
}

struct ActivityRow: View {
    let item: ActivityItem
    var body: some View {
        HStack(spacing: 10) {
            switch item.kind {
            case .review(let r):
                Image(systemName: "star.bubble.fill").foregroundStyle(r.rating.ratingColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        StarsView(rating: r.rating, size: 9)
                        Text(item.appName).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(r.title.isEmpty ? r.body : r.title).font(.caption).lineLimit(1)
                }
            case .status(let e):
                Image(systemName: e.toState.symbol).foregroundStyle(e.toState.color).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.appName).font(.caption2).foregroundStyle(.secondary)
                    Text("Now \(e.toState.label)").font(.caption).lineLimit(1)
                }
            }
            Spacer()
            Text(Format.relativeDate(item.date)).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}

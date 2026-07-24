//
//  IncomeView.swift
//  StoreGauge
//
//  Income deep-dive: proceeds by app & country, IAP vs paid, refunds, trend.
//  Data is cached in AppModel so switching tabs doesn't re-fetch every time.
//

import SwiftUI
import SwiftData

struct IncomeView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \TrackedApp.name) private var apps: [TrackedApp]
    @Query(sort: \Account.sortIndex) private var accounts: [Account]

    @State private var rangeDays = 30
    @State private var appFilter: String?   // TrackedApp UUID string, nil == all apps

    private var settings: AppSettings { model.settings }
    private var currency: String { settings.displayCurrency }
    private var hasVendor: Bool {
        accounts.contains {
            $0.platform == .appleAppStore && ($0.vendorNumber?.trimmingCharacters(in: .whitespaces).isEmpty == false)
        }
    }
    private var hasGoogleFinancials: Bool {
        accounts.contains {
            $0.platform == .googlePlay && ($0.googleFinancialBucket?.trimmingCharacters(in: .whitespaces).isEmpty == false)
        }
    }
    private var appleIncomeApps: [TrackedApp] {
        apps.filter {
            !$0.isArchived && $0.platform == .appleAppStore &&
                $0.account?.vendorNumber?.trimmingCharacters(in: .whitespaces).isEmpty == false
        }
    }
    private var googleIncomeApps: [TrackedApp] {
        apps.filter {
            !$0.isArchived && $0.platform == .googlePlay &&
                $0.account?.googleFinancialBucket?.isEmpty == false
        }
    }
    private var incomeApps: [TrackedApp] { appleIncomeApps + googleIncomeApps }
    private var selectedPlatform: StorePlatform? {
        guard let appFilter else { return nil }
        return incomeApps.first { $0.id.uuidString == appFilter }?.platform
    }
    private var showsApple: Bool { hasVendor && selectedPlatform != .googlePlay }
    private var showsGoogle: Bool { hasGoogleFinancials && selectedPlatform != .appleAppStore }

    private var breakdown: AppModel.IncomeBreakdown? { model.incomeBreakdown }
    private var loading: Bool { model.incomeLoading }
    private var scope: AppModel.IncomeBreakdown.AppAgg { breakdown?.scoped(to: appFilter) ?? .init() }
    /// Proceeds-per-day from the fetched breakdown (consistent with the KPIs + range).
    private var proceedsSeries: [DatedValue] {
        var s = MetricsAggregator.dayBuckets(days: rangeDays).map { DatedValue(date: $0, value: scope.byDay[$0] ?? 0) }
        while let last = s.last, last.value == 0 { s.removeLast() }   // drop trailing unreported days
        return s
    }

    private var trendApps: [TrackedApp] {
        appFilter.map { id in appleIncomeApps.filter { $0.id.uuidString == id } } ?? appleIncomeApps
    }
    private var agg: MetricsAggregator { MetricsAggregator(apps: trendApps, fx: model.fx, currency: currency) }
    private var googleTrendApps: [TrackedApp] {
        appFilter.map { id in googleIncomeApps.filter { $0.id.uuidString == id } } ?? googleIncomeApps
    }
    private var googleAgg: MetricsAggregator {
        MetricsAggregator(apps: googleTrendApps, fx: model.fx, currency: currency)
    }
    private var appByID: [String: TrackedApp] {
        Dictionary(appleIncomeApps.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        Group {
            if !hasVendor && !hasGoogleFinancials {
                noIncomeSource
            } else {
                content
            }
        }
        .navigationTitle("Income")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("", selection: $rangeDays) {
                    Text("7D").tag(7); Text("30D").tag(30); Text("90D").tag(90)
                }.pickerStyle(.segmented).fixedSize()
            }
            ToolbarItem(placement: .primaryAction) {
                Button { exportCSV() } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled((breakdown == nil || breakdown?.byApp.isEmpty == true) &&
                              !googleAgg.hasAny(.grossSales) && !googleAgg.hasAny(.netEarnings))
            }
        }
        .task(id: rangeDays) {
            if hasVendor { model.ensureIncome(days: rangeDays) }
        }
        .onChange(of: currency) {
            if hasVendor { model.ensureIncome(days: rangeDays, force: true) }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if showsApple, breakdown == nil {
                    loadingState
                } else if showsApple {
                    VStack(alignment: .leading, spacing: 18) {
                        Label("App Store · Developer Proceeds", systemImage: "apple.logo")
                            .font(.title3.weight(.semibold))
                        kpis
                        ChartCard(title: "Proceeds", symbol: "chart.line.uptrend.xyaxis",
                                  subtitle: Format.currency(scope.total, code: currency)) {
                            TrendChart(series: proceedsSeries, tint: .green,
                                       isCurrency: true, currencyCode: currency).frame(height: 180)
                        }
                        HStack(alignment: .top, spacing: 14) {
                            if appFilter == nil { byAppCard }
                            byCountryCard
                        }
                        splitCard
                    }
                    .opacity(loading ? 0.5 : 1)   // dim while re-fetching a new range
                    .animation(.default, value: loading)
                }
                if showsGoogle { googlePlayIncome }
            }
            .padding(20)
        }
        .background(.windowFill)
    }

    private var googlePlayIncome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Google Play · Sales & Earnings", systemImage: "play.fill")
                .font(.title3.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                KPITile(title: "Estimated Gross Sales",
                        value: Format.currency(googleAgg.total(.grossSales, days: rangeDays), code: currency),
                        delta: googleAgg.delta(.grossSales, days: rangeDays),
                        symbol: MetricKind.grossSales.symbol, tint: .mint)
                KPITile(title: "Finalized Earnings",
                        value: Format.currency(googleAgg.total(.netEarnings, days: rangeDays), code: currency),
                        subtitle: "monthly report", symbol: MetricKind.netEarnings.symbol, tint: .green)
                KPITile(title: "Net Orders",
                        value: Format.compact(googleAgg.total(.orders, days: rangeDays)),
                        subtitle: "charges minus refunds", symbol: MetricKind.orders.symbol, tint: .blue)
            }
            HStack(alignment: .top, spacing: 14) {
                ChartCard(title: "Estimated Gross Sales", symbol: "chart.line.uptrend.xyaxis",
                          subtitle: "before taxes and Google fees") {
                    TrendChart(series: googleAgg.reportedSeries(.grossSales, days: rangeDays), tint: .mint,
                               isCurrency: true, currencyCode: currency).frame(height: 180)
                }
                ChartCard(title: "Finalized Earnings", symbol: "banknote.fill",
                          subtitle: "payout-oriented monthly report") {
                    TrendChart(series: googleAgg.reportedSeries(.netEarnings, days: rangeDays), tint: .green,
                               isCurrency: true, currencyCode: currency).frame(height: 180)
                }
            }
            Label("Google normally posts estimated sales with a 3–7 day lag. Earnings are finalized monthly, usually around the 5th of the following month.",
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Income").font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("Last \(rangeDays) days · \(currency)").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if loading {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Loading…").font(.caption).foregroundStyle(.secondary) }
            }
            Picker("", selection: $appFilter) {
                Text("All Apps").tag(String?.none)
                ForEach(incomeApps) { Text($0.name).tag(String?.some($0.id.uuidString)) }
            }
            .frame(maxWidth: 200)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView(value: model.incomeProgress).progressViewStyle(.linear).frame(maxWidth: 260)
            Text("Scanning daily sales reports… \(Int(model.incomeProgress * 100))%")
                .font(.callout).foregroundStyle(.secondary)
            Text("Fetching \(rangeDays) days across your accounts.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private var kpis: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
            KPITile(title: "Total Proceeds", value: Format.currency(scope.total, code: currency),
                    delta: agg.delta(.proceeds, days: rangeDays), symbol: "dollarsign.circle.fill", tint: .green)
            KPITile(title: "In-App Purchases", value: Format.currency(scope.iap, code: currency),
                    subtitle: "IAP & subscriptions", symbol: "cart.fill", tint: .indigo)
            KPITile(title: "Paid Apps", value: Format.currency(scope.appProceeds, code: currency),
                    subtitle: "app sales", symbol: "app.badge.fill", tint: .blue)
            KPITile(title: "Refunds", value: Format.currency(scope.refund, code: currency),
                    subtitle: "\(scope.refundUnits) units", symbol: "arrow.uturn.left.circle.fill", tint: .red)
        }
    }

    private var byAppCard: some View {
        ChartCard(title: "By App", symbol: "square.stack.3d.up.fill") {
            let rows = (breakdown?.byApp ?? [:]).mapValues(\.total).sorted { $0.value > $1.value }.filter { $0.value != 0 }.prefix(8)
            if rows.isEmpty { emptyRows } else {
                let maxV = rows.map { abs($0.value) }.max() ?? 1
                VStack(spacing: 8) {
                    ForEach(Array(rows), id: \.key) { id, value in
                        Button { appFilter = id } label: {
                            HStack(spacing: 8) {
                                if let app = appByID[id] { AppIconView(app: app, size: 22, showsStoreBadge: true) }
                                Text(appByID[id]?.name ?? id).font(.caption).lineLimit(1).frame(width: 92, alignment: .leading)
                                GeometryReader { geo in
                                    Capsule().fill(.green.gradient)
                                        .frame(width: max(3, geo.size.width * CGFloat(abs(value) / max(maxV, 1))))
                                        .frame(maxHeight: .infinity, alignment: .leading)
                                }.frame(height: 12)
                                Text(Format.currency(value, code: currency, compact: true)).font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary).frame(width: 58, alignment: .trailing)
                            }
                        }.buttonStyle(.plain)
                    }
                }.frame(minHeight: 120)
            }
        }
    }

    private var byCountryCard: some View {
        ChartCard(title: appFilter == nil ? "By Country" : "Countries · \(appByID[appFilter!]?.name ?? "")",
                  symbol: "globe") {
            let rows = scope.byCountry.sorted { $0.value > $1.value }.filter { $0.value != 0 }.prefix(10)
            if rows.isEmpty { emptyRows } else {
                let maxV = rows.map { abs($0.value) }.max() ?? 1
                VStack(spacing: 8) {
                    ForEach(Array(rows), id: \.key) { code, value in
                        HStack(spacing: 8) {
                            Text(flagEmoji(for: code))
                            Text(code).font(.caption.weight(.medium)).frame(width: 28, alignment: .leading)
                            GeometryReader { geo in
                                Capsule().fill(.teal.gradient)
                                    .frame(width: max(3, geo.size.width * CGFloat(abs(value) / max(maxV, 1))))
                                    .frame(maxHeight: .infinity, alignment: .leading)
                            }.frame(height: 12)
                            Text(Format.currency(value, code: currency, compact: true)).font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary).frame(width: 58, alignment: .trailing)
                        }
                    }
                }.frame(minHeight: 120)
            }
        }
    }

    private var splitCard: some View {
        ChartCard(title: "Paid vs In-App", symbol: "chart.pie.fill") {
            let app = max(scope.appProceeds, 0), iap = max(scope.iap, 0)
            let total = max(app + iap, 0.0001)
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        Rectangle().fill(.blue).frame(width: geo.size.width * CGFloat(app / total))
                        Rectangle().fill(.indigo)
                    }.clipShape(Capsule())
                }.frame(height: 16)
                HStack(spacing: 16) {
                    Label("Paid apps · \(Format.currency(app, code: currency, compact: true))", systemImage: "square.fill").foregroundStyle(.blue)
                    Label("In-app · \(Format.currency(iap, code: currency, compact: true))", systemImage: "square.fill").foregroundStyle(.indigo)
                }.font(.caption)
            }.frame(minHeight: 50)
        }
    }

    private func exportCSV() {
        func f(_ v: Double) -> String { String(format: "%.2f", v) }
        var lines: [String] = []
        if let b = breakdown, !b.byApp.isEmpty {
            lines.append("App Store,App,Developer Proceeds,In-App,Paid Apps,Refunds,Currency")
            for (id, agg) in b.byApp.sorted(by: { $0.value.total > $1.value.total }) {
                lines.append(CSVExporter.row(["App Store", appByID[id]?.name ?? id, f(agg.total), f(agg.iap),
                                              f(agg.appProceeds), f(agg.refund), currency]))
            }
            lines.append("")
            lines.append("App Store Country,Developer Proceeds,Currency")
            for (code, v) in b.scoped(to: nil).byCountry.sorted(by: { $0.value > $1.value }) {
                lines.append(CSVExporter.row([code, f(v), currency]))
            }
        }
        if hasGoogleFinancials {
            if !lines.isEmpty { lines.append("") }
            lines.append("Google Play,App,Estimated Gross Sales,Finalized Earnings,Net Orders,Currency")
            for app in googleIncomeApps {
                let appAgg = MetricsAggregator(apps: [app], fx: model.fx, currency: currency)
                lines.append(CSVExporter.row([
                    "Google Play", app.name,
                    f(appAgg.total(.grossSales, days: rangeDays)),
                    f(appAgg.total(.netEarnings, days: rangeDays)),
                    f(appAgg.total(.orders, days: rangeDays)), currency,
                ]))
            }
        }
        guard !lines.isEmpty else { return }
        #if os(macOS)
        CSVExporter.save(lines.joined(separator: "\n"), suggestedName: "income-\(rangeDays)d.csv")
        #endif
    }

    @ViewBuilder private var emptyRows: some View {
        Text("No proceeds in this period.").font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
    }

    private var noIncomeSource: some View {
        VStack(spacing: 14) {
            Image(systemName: "dollarsign.circle").font(.system(size: 44)).foregroundStyle(.secondary.opacity(0.6))
            Text("Enable income reports").font(.title3.weight(.semibold))
            Text("For App Store Connect, add your vendor number. For Google Play, add the pubsite_prod_rev_… report bucket and grant Global View financial data. You can configure either one in Account Settings.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            SettingsLink { Label("Open Settings", systemImage: "gearshape") }.controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }
}

//
//  AppDetailView.swift
//  StoreGauge
//
//  Per-app detail: status, charts, status timeline, builds and recent reviews.
//

import SwiftUI
import SwiftData

struct AppDetailView: View {
    @Bindable var app: TrackedApp
    @Environment(AppModel.self) private var model
    @State private var rangeDays = 30
    @State private var builds: [BuildInfo] = []
    @State private var loadingBuilds = false
    @State private var testflight = AppModel.TestFlightData()
    @State private var loadingTF = false
    @State private var editingAnnotation: AnnotationEdit?

    private var settings: AppSettings { model.settings }
    private var agg: MetricsAggregator {
        MetricsAggregator(apps: [app], fx: model.fx, currency: settings.displayCurrency)
    }
    private var recentReviews: [Review] {
        app.reviews.sorted { $0.createdDate > $1.createdDate }
    }
    private var appRatingTrend: [DatedValue] { ratingTrend(app.reviews) }
    private var hasPerformanceData: Bool {
        app.capabilities.contains(.sales) || agg.hasDownloads ||
            agg.hasAny(.activeDevices) || agg.hasAny(.sessions) ||
            agg.hasAny(.impressions) || hasStabilityData
    }
    private var hasStabilityData: Bool { agg.hasAny(.crashRate) || agg.hasAny(.anrRate) }
    private var hasGoogleFinancialData: Bool {
        agg.hasAny(.grossSales) || agg.hasAny(.netEarnings) || agg.hasAny(.orders)
    }
    private var googleFinancialsConfigured: Bool {
        app.platform == .googlePlay && app.account?.googleFinancialBucket?.isEmpty == false
    }
    /// Distinct days on which listing metadata changed (for chart overlays).
    private var metadataMarkers: [Date] {
        let cutoff = Date.daysAgo(rangeDays).startOfDayUTC
        return Array(Set(app.metadataChanges.map { $0.date.startOfDayUTC })).filter { $0 >= cutoff }.sorted()
    }
    private var annotationMarks: [ChartAnnotationMark] {
        app.annotations.map {
            ChartAnnotationMark(id: $0.id, date: $0.date.startOfDayUTC, note: $0.note, category: $0.category)
        }
    }
    private func startAddAnnotation(_ date: Date) { editingAnnotation = .new(date) }
    private func startEditAnnotation(_ id: UUID) { editingAnnotation = .existing(id) }
    private var alertSelection: Binding<String?> {
        Binding(get: { app.alertRuleRaw }, set: { app.alertRuleRaw = $0; try? model.context.save() })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                if app.capabilities.contains(.phasedReleases) { phasedReleaseBanner }
                if hasPerformanceData {
                    kpis
                    if app.capabilities.contains(.sales) {
                        ChartCard(title: "Proceeds", symbol: "dollarsign.circle.fill",
                                  subtitle: Format.currency(agg.total(.proceeds, days: rangeDays), code: settings.displayCurrency)) {
                            TrendChart(series: agg.salesSeries(.proceeds, days: rangeDays), tint: .green,
                                       isCurrency: true, currencyCode: settings.displayCurrency, markers: metadataMarkers,
                                       annotations: annotationMarks, onAddAnnotation: startAddAnnotation, onEditAnnotation: startEditAnnotation)
                                .frame(height: 180)
                        }
                    }
                    if agg.hasDownloads { downloadsCard }
                    if agg.hasAny(.activeDevices) {
                        ChartCard(title: "Active Devices", symbol: "iphone.gen3",
                                  subtitle: Format.compact(agg.series(.activeDevices, days: rangeDays).last?.value ?? 0)) {
                            TrendChart(series: agg.series(.activeDevices, days: rangeDays), tint: .purple)
                                .frame(height: 160)
                        }
                    }
                    if hasStabilityData { stabilityCards }
                    if hasGoogleFinancialData { googleFinancialCards }
                    if agg.hasAny(.impressions) {
                        FunnelCard(impressions: agg.total(.impressions, days: rangeDays),
                                   pageViews: agg.total(.pageViews, days: rangeDays),
                                   downloads: agg.downloadTotal(days: rangeDays))
                    }
                    annotationsCard
                    if app.platform == .googlePlay { googlePlayCoverageCard }
                    timelineCard
                } else {
                    feedbackKPIs
                    if hasGoogleFinancialData { googleFinancialCards }
                    googlePlayCoverageCard
                    timelineCard
                }
                if appRatingTrend.count >= 2 {
                    ChartCard(title: "Rating Trend", symbol: "chart.line.uptrend.xyaxis", subtitle: "monthly average") {
                        TrendChart(series: appRatingTrend, tint: .yellow, yDomain: 1...5, markers: metadataMarkers, annotations: annotationMarks).frame(height: 150)
                    }
                }
                if app.capabilities.contains(.builds) { buildsCard }
                if app.capabilities.contains(.betaTesting) { testFlightCard }
                if app.capabilities.contains(.metadata) {
                    AppScreenshotsCard(app: app)
                    MetadataHistoryCard(app: app)
                }
                reviewsCard
            }
            .padding(20)
        }
        .background(.windowFill)
        .navigationTitle(app.name)
        .toolbar {
            if hasPerformanceData || googleFinancialsConfigured {
                ToolbarItem(placement: .primaryAction) {
                    Picker("", selection: $rangeDays) {
                        Text("7D").tag(7); Text("30D").tag(30); Text("90D").tag(90)
                    }.pickerStyle(.segmented).fixedSize()
                }
            }
        }
        .task(id: app.id) {
            if app.capabilities.contains(.builds) { await loadBuilds() }
            if app.capabilities.contains(.betaTesting) {
                loadingTF = true
                testflight = await model.loadTestFlight(for: app)
                loadingTF = false
            }
        }
        .sheet(item: $editingAnnotation) { edit in
            AnnotationEditor(edit: edit, app: app)
                .environment(model)
        }
    }

    // MARK: Header

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 16) {
            AppIconView(app: app, size: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(app.name).font(.system(.title, design: .rounded).weight(.bold))
                Text(app.bundleID).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                HStack(spacing: 8) {
                    StorePlatformLabel(platform: app.platform)
                    if app.currentStateRaw != nil { StatusBadge(state: app.state) }
                    if let v = app.currentVersionString { Text("v\(v)").font(.caption).foregroundStyle(.secondary) }
                    if let p = app.currentPlatform { Text(p).font(.caption).foregroundStyle(.secondary) }
                    if let account = app.account { Text("· \(account.name)").font(.caption).foregroundStyle(.secondary) }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                if let url = app.platform.appConsoleURL(remoteIdentifier: app.remoteIdentifier) {
                    Link(destination: url) {
                        Label(app.platform.accountDisplayName, systemImage: "arrow.up.forward.square")
                    }
                        .font(.callout)
                }
                Toggle("Include in dashboard", isOn: $app.isSelected)
                    .toggleStyle(.switch).controlSize(.mini).font(.caption)
                    .onChange(of: app.isSelected) { try? model.context.save(); model.recomputeBadges() }
                Picker("Alerts", selection: alertSelection) {
                    Text("Default · \(model.settings.globalAlertRule.label)").tag(String?.none)
                    ForEach(ReviewAlertRule.allCases, id: \.self) { Text($0.label).tag(String?.some($0.rawValue)) }
                }
                .pickerStyle(.menu).fixedSize().controlSize(.small).font(.caption)
            }
        }
        .card()
    }

    // MARK: KPIs

    private var kpis: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
            if app.capabilities.contains(.sales) {
                KPITile(title: "Proceeds", value: Format.currency(agg.total(.proceeds, days: rangeDays), code: settings.displayCurrency),
                        delta: agg.delta(.proceeds, days: rangeDays), symbol: "dollarsign.circle.fill", tint: .green,
                        spark: Array(agg.series(.proceeds, days: min(rangeDays, 14)).map(\.value)))
            }
            if agg.hasDownloads {
                KPITile(title: "Downloads", value: Format.int(agg.downloadTotal(days: rangeDays)),
                        delta: agg.downloadDelta(days: rangeDays), symbol: "arrow.down.circle.fill", tint: .blue,
                        spark: Array(agg.downloadSeries(days: min(rangeDays, 14)).map(\.value)))
            }
            if agg.hasAny(.crashRate) {
                KPITile(title: "Crash Rate", value: latestRate(.crashRate),
                        subtitle: "latest reported day", symbol: MetricKind.crashRate.symbol, tint: .red)
            }
            if agg.hasAny(.anrRate) {
                KPITile(title: "ANR Rate", value: latestRate(.anrRate),
                        subtitle: "latest reported day", symbol: MetricKind.anrRate.symbol, tint: .orange)
            }
            KPITile(title: "Avg Rating", value: avgRating > 0 ? String(format: "%.2f", avgRating) : "—",
                    subtitle: "\(app.reviews.count) reviews", symbol: "star.fill", tint: .yellow)
            KPITile(title: "Needs Reply", value: "\(app.reviews.filter { $0.needsAttention }.count)",
                    subtitle: "unanswered", symbol: "exclamationmark.bubble.fill", tint: .orange)
        }
    }

    private var avgRating: Double {
        let rated = app.reviews.filter { $0.rating > 0 }
        guard !rated.isEmpty else { return 0 }
        return Double(rated.reduce(0) { $0 + $1.rating }) / Double(rated.count)
    }

    private func latestRate(_ kind: MetricKind) -> String {
        guard let value = agg.reportedAverageSeries(kind, days: rangeDays).last?.value else { return "—" }
        return Format.percentRate(value)
    }

    private var feedbackKPIs: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
            KPITile(title: "Avg Rating", value: avgRating > 0 ? String(format: "%.2f", avgRating) : "—",
                    subtitle: "written reviews", symbol: "star.fill", tint: .yellow)
            KPITile(title: "Reviews", value: "\(app.reviews.count)",
                    subtitle: "synced from Google Play", symbol: "bubble.left.and.bubble.right.fill", tint: .blue)
            KPITile(title: "Needs Reply", value: "\(app.reviews.filter { $0.needsAttention }.count)",
                    subtitle: "unanswered", symbol: "exclamationmark.bubble.fill", tint: .orange)
        }
    }

    private var googlePlayCoverageCard: some View {
        ChartCard(title: "Google Play Data", symbol: "play.fill") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 5) {
                    Text(googleFinancialsConfigured
                         ? "Reviews, releases, installs, and Android vitals are connected."
                         : "Reviews, releases, and Android vitals are connected.")
                        .font(.callout.weight(.medium))
                    Text(googleFinancialsConfigured
                         ? "Install exports can lag 3–7 days; financial data also appears when View financial data is granted. Google does not currently offer programmatic access to the new Play Console acquisition funnel."
                         : "Add the pubsite_prod_rev_… report bucket in Account Settings for daily installs, updates, estimated sales, and finalized earnings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var googleFinancialCards: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                KPITile(title: "Gross Sales",
                        value: Format.currency(agg.total(.grossSales, days: rangeDays), code: settings.displayCurrency),
                        delta: agg.delta(.grossSales, days: rangeDays),
                        symbol: MetricKind.grossSales.symbol, tint: .mint)
                KPITile(title: "Finalized Earnings",
                        value: Format.currency(agg.total(.netEarnings, days: rangeDays), code: settings.displayCurrency),
                        subtitle: "monthly earnings report",
                        symbol: MetricKind.netEarnings.symbol, tint: .green)
                KPITile(title: "Net Orders", value: Format.compact(agg.total(.orders, days: rangeDays)),
                        subtitle: "charges minus refunds", symbol: MetricKind.orders.symbol, tint: .blue)
            }
            HStack(alignment: .top, spacing: 14) {
                ChartCard(title: "Estimated Gross Sales", symbol: "cart.circle.fill",
                          subtitle: "before taxes and Google fees") {
                    TrendChart(series: agg.reportedSeries(.grossSales, days: rangeDays), tint: .mint,
                               isCurrency: true, currencyCode: settings.displayCurrency).frame(height: 160)
                }
                ChartCard(title: "Finalized Earnings", symbol: "banknote.fill",
                          subtitle: "payout-oriented monthly report") {
                    TrendChart(series: agg.reportedSeries(.netEarnings, days: rangeDays), tint: .green,
                               isCurrency: true, currencyCode: settings.displayCurrency).frame(height: 160)
                }
            }
        }
    }

    @ViewBuilder private var phasedReleaseBanner: some View {
        if let state = app.phasedReleaseState, state == "ACTIVE" || state == "PAUSED" {
            let day = max(1, min(app.phasedReleaseDay ?? 1, 7))
            let pct = [1, 2, 5, 10, 20, 50, 100][day - 1]
            ChartCard(title: "Phased Release", symbol: "chart.line.uptrend.xyaxis") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Day \(day) of 7").font(.headline)
                        if state == "PAUSED" {
                            Text("Paused").font(.caption.weight(.medium)).foregroundStyle(.orange)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(.orange.opacity(0.15)))
                        }
                        Spacer()
                        Text("\(pct)%").font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(.green)
                    }
                    ProgressView(value: Double(pct), total: 100).tint(.green)
                    Text("Rolling out to \(pct)% of users with automatic updates enabled.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
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
                    .init(id: "new", name: "New (\(Format.compact(newTotal)))", color: .blue, points: newS),
                    .init(id: "updates", name: "Updates (\(Format.compact(updTotal)))", color: .teal, points: upd),
                ], markers: metadataMarkers, annotations: annotationMarks,
                   onAddAnnotation: startAddAnnotation, onEditAnnotation: startEditAnnotation).frame(height: 160)
            } else {
                BarTrendChart(series: agg.downloadSeries(days: rangeDays), tint: .blue, markers: metadataMarkers,
                              annotations: annotationMarks, onAddAnnotation: startAddAnnotation, onEditAnnotation: startEditAnnotation).frame(height: 160)
            }
        }
    }

    private var stabilityCards: some View {
        HStack(alignment: .top, spacing: 14) {
            if agg.hasAny(.crashRate) {
                ChartCard(title: "Crash Rate", symbol: MetricKind.crashRate.symbol,
                          subtitle: latestRate(.crashRate)) {
                    TrendChart(series: agg.reportedAverageSeries(.crashRate, days: rangeDays),
                               tint: .red, isPercentage: true).frame(height: 160)
                }
            }
            if agg.hasAny(.anrRate) {
                ChartCard(title: "ANR Rate", symbol: MetricKind.anrRate.symbol,
                          subtitle: latestRate(.anrRate)) {
                    TrendChart(series: agg.reportedAverageSeries(.anrRate, days: rangeDays),
                               tint: .orange, isPercentage: true).frame(height: 160)
                }
            }
        }
    }

    // MARK: Timeline

    private var timelineCard: some View {
        ChartCard(title: "Status Timeline", symbol: "clock.arrow.circlepath") {
            let events = app.statusEvents.sorted { $0.date > $1.date }
            if events.isEmpty {
                HStack(spacing: 8) {
                    if app.currentStateRaw != nil { StatusBadge(state: app.state) }
                    Text("No changes recorded yet.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(events.prefix(8), id: \.persistentModelID) { e in
                        HStack(spacing: 10) {
                            Image(systemName: e.toState.symbol).foregroundStyle(e.toState.color).frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    if let from = e.fromState { Text(from.label).foregroundStyle(.secondary); Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary) }
                                    Text(e.toState.label).fontWeight(.medium)
                                }.font(.caption)
                                if let v = e.versionString { Text("v\(v)").font(.caption2).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(Format.relativeDate(e.date)).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Builds

    private var buildsCard: some View {
        ChartCard(title: "Recent Builds", symbol: "hammer.fill") {
            if loadingBuilds {
                HStack { ProgressView().controlSize(.small); Text("Loading…").font(.caption).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if builds.isEmpty {
                Text("No builds found.").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(builds, id: \.id) { build in
                        HStack(spacing: 10) {
                            Image(systemName: "shippingbox.fill").foregroundStyle(.secondary)
                            Text("Build \(build.version ?? "?")").font(.callout.weight(.medium))
                            if build.expired { Text("expired").font(.caption2).foregroundStyle(.orange) }
                            Spacer()
                            if let state = build.processingState {
                                Text(state.capitalized).font(.caption)
                                    .foregroundStyle(state == "VALID" ? .green : .secondary)
                            }
                            if let d = build.uploadedDate { Text(Format.relativeDate(d)).font(.caption2).foregroundStyle(.tertiary) }
                        }
                    }
                }
            }
        }
    }

    private func loadBuilds() async {
        loadingBuilds = true
        builds = await model.builds(for: app)
        loadingBuilds = false
    }

    // MARK: Annotations

    private var annotationsCard: some View {
        ChartCard(title: "Annotations", symbol: "flag.fill") {
            VStack(alignment: .leading, spacing: 8) {
                if app.annotations.isEmpty {
                    Text("Pin notes to dates on your charts — e.g. \"ran a promo\", \"featured by Apple\", \"raised price\" — to correlate them with the numbers. Tip: right-click any chart to add one on that day.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(app.annotations.sorted { $0.date > $1.date }, id: \.persistentModelID) { a in
                        HStack(spacing: 8) {
                            Image(systemName: a.category.symbol).foregroundStyle(a.category.color).font(.caption).frame(width: 16)
                            Text(Format.mediumDate.string(from: a.date)).font(.caption).foregroundStyle(.secondary)
                                .frame(width: 96, alignment: .leading)
                            Text(a.note).font(.callout).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(a.category.label).font(.caption2.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(a.category.color.opacity(0.15)))
                                .foregroundStyle(a.category.color)
                            Button { startEditAnnotation(a.id) } label: { Image(systemName: "pencil").font(.caption) }
                                .buttonStyle(.borderless).help("Edit")
                            Button(role: .destructive) { model.deleteAnnotation(a) } label: { Image(systemName: "trash").font(.caption) }
                                .buttonStyle(.borderless).help("Delete")
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture { startEditAnnotation(a.id) }
                    }
                }
                Button { startAddAnnotation(Date()) } label: { Label("Add annotation", systemImage: "plus") }
                    .controlSize(.small)
            }
        }
    }

    // MARK: TestFlight

    private var testFlightCard: some View {
        ChartCard(title: "TestFlight", symbol: "airplane") {
            if loadingTF {
                HStack { ProgressView().controlSize(.small); Text("Loading…").font(.caption).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else if testflight.isEmpty {
                Text("No beta groups or crash feedback.").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if !testflight.groups.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Beta Groups").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(testflight.groups) { g in
                                HStack(spacing: 8) {
                                    Image(systemName: g.isInternal ? "lock.fill" : "globe").font(.caption).foregroundStyle(.secondary)
                                    Text(g.name).font(.callout)
                                    Text(g.isInternal ? "Internal" : "External").font(.caption2).foregroundStyle(.secondary)
                                    Spacer()
                                    Label("\(g.testerCount)", systemImage: "person.2.fill").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !testflight.feedback.isEmpty {
                        if !testflight.groups.isEmpty { Divider() }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Crash Feedback").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(testflight.feedback.prefix(5)) { f in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "ant.fill").foregroundStyle(.red).font(.caption)
                                        Text([f.device, f.os].compactMap { $0 }.joined(separator: " · ")).font(.caption.weight(.medium))
                                        Spacer()
                                        if let d = f.date { Text(Format.relativeDate(d)).font(.caption2).foregroundStyle(.tertiary) }
                                    }
                                    if let c = f.comment, !c.isEmpty { Text(c).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Reviews

    private var reviewsCard: some View {
        ChartCard(title: "Recent Reviews", symbol: "star.bubble.fill",
                  subtitle: "\(app.reviews.count)") {
            if recentReviews.isEmpty {
                Text("No reviews yet.").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(recentReviews.prefix(6)) { r in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                StarsView(rating: r.rating, size: 10)
                                ReviewLocaleBadge(review: r)
                                Spacer()
                                if r.needsAttention { Circle().fill(r.rating <= 2 ? .red : .orange).frame(width: 6, height: 6) }
                                Text(Format.relativeDate(r.createdDate)).font(.caption2).foregroundStyle(.tertiary)
                            }
                            ReviewTranslatedContent(review: r, compact: true)
                        }
                        .padding(.vertical, 7)
                        if r.id != recentReviews.prefix(6).last?.id { Divider() }
                    }
                }
            }
        }
    }
}

// MARK: - Annotation editor

/// Identifies what the annotation sheet is editing: a brand-new one on a date, or an
/// existing one by id.
enum AnnotationEdit: Identifiable {
    case new(Date)
    case existing(UUID)
    var id: String {
        switch self {
        case .new(let d): "new-\(d.timeIntervalSince1970)"
        case .existing(let id): id.uuidString
        }
    }
}

struct AnnotationEditor: View {
    let edit: AnnotationEdit
    @Bindable var app: TrackedApp
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var note = ""
    @State private var category: AnnotationCategory = .note
    @State private var loaded = false

    private var existing: ChartAnnotation? {
        if case .existing(let id) = edit { return app.annotations.first { $0.id == id } }
        return nil
    }
    private var isNew: Bool { existing == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Add Annotation" : "Edit Annotation").font(.headline)

            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Category", selection: $category) {
                    ForEach(AnnotationCategory.allCases, id: \.self) { c in
                        Label(c.label, systemImage: c.symbol).tag(c)
                    }
                }
                TextField("Note", text: $note, prompt: Text("e.g. ran a launch promo"))
            }
            .formStyle(.columns)

            HStack {
                if !isNew {
                    Button(role: .destructive) {
                        if let existing { model.deleteAnnotation(existing) }
                        dismiss()
                    } label: { Label("Delete", systemImage: "trash") }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(note.trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let e = existing {
                date = e.date; note = e.note; category = e.category
            } else if case .new(let d) = edit {
                date = d
            }
        }
    }

    private func save() {
        let trimmed = note.trimmed
        guard !trimmed.isEmpty else { return }
        if let e = existing {
            model.updateAnnotation(e, date: date, note: trimmed, category: category)
        } else {
            model.addAnnotation(date: date, note: trimmed, category: category, to: app)
        }
        dismiss()
    }
}

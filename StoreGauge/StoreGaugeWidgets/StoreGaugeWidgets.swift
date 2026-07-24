//
//  StoreGaugeWidgets.swift
//  StoreGaugeWidgets
//
//  Glanceable performance and feedback widgets backed by the local snapshot
//  StoreGauge publishes after every sync or review action.
//

import AppIntents
import Charts
import SwiftUI
import WidgetKit

// MARK: - Configuration

nonisolated struct StoreGaugeAppEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "App")
    static let defaultQuery = StoreGaugeAppQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

nonisolated struct StoreGaugeAppQuery: EntityQuery {
    func entities(for identifiers: [StoreGaugeAppEntity.ID]) async throws -> [StoreGaugeAppEntity] {
        let wanted = Set(identifiers)
        return entities.filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [StoreGaugeAppEntity] {
        entities
    }

    private var entities: [StoreGaugeAppEntity] {
        StoreGaugeWidgetStorage.load().apps.map {
            StoreGaugeAppEntity(id: $0.id, name: $0.name)
        }
    }
}

nonisolated enum WidgetPeriod: String, AppEnum {
    case sevenDays
    case fourteenDays
    case thirtyDays

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Period")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .sevenDays: "7 days",
        .fourteenDays: "14 days",
        .thirtyDays: "30 days"
    ]

    var days: Int {
        switch self {
        case .sevenDays: 7
        case .fourteenDays: 14
        case .thirtyDays: 30
        }
    }
}

nonisolated enum WidgetPerformanceMetric: String, AppEnum {
    case both
    case downloads
    case proceeds

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Metrics")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .both: "Downloads and proceeds",
        .downloads: "Downloads",
        .proceeds: "Proceeds"
    ]
}

nonisolated enum WidgetFeedbackFilter: String, AppEnum {
    case all
    case critical
    case negative
    case positive

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Ratings")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .all: "All ratings",
        .critical: "1–2 stars",
        .negative: "1–3 stars",
        .positive: "4–5 stars"
    ]

    func includes(_ rating: Int) -> Bool {
        switch self {
        case .all: true
        case .critical: rating <= 2
        case .negative: rating <= 3
        case .positive: rating >= 4
        }
    }
}

struct StoreGaugePerformanceConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Performance"
    static let description = IntentDescription("Choose apps, metrics, and a comparison period.")

    @Parameter(title: "App")
    var app: StoreGaugeAppEntity?

    @Parameter(title: "Metrics", default: .both)
    var metric: WidgetPerformanceMetric

    @Parameter(title: "Period", default: .sevenDays)
    var period: WidgetPeriod
}

struct StoreGaugeFeedbackConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "New Feedback"
    static let description = IntentDescription("Choose an app and the ratings shown in the feedback queue.")

    @Parameter(title: "App")
    var app: StoreGaugeAppEntity?

    @Parameter(title: "Ratings", default: .all)
    var ratings: WidgetFeedbackFilter
}

// MARK: - Timeline

nonisolated struct StoreGaugeWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: StoreGaugeWidgetSnapshot
    let appID: String?
    let period: WidgetPeriod
    let metric: WidgetPerformanceMetric
    let ratings: WidgetFeedbackFilter
}

nonisolated struct StoreGaugePerformanceTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StoreGaugeWidgetEntry {
        StoreGaugeWidgetEntry(date: Date(), snapshot: .preview, appID: nil,
                              period: .sevenDays, metric: .both, ratings: .all)
    }

    func snapshot(for configuration: StoreGaugePerformanceConfiguration, in context: Context) async -> StoreGaugeWidgetEntry {
        StoreGaugeWidgetEntry(
            date: Date(),
            snapshot: StoreGaugeWidgetStorage.load(),
            appID: configuration.app?.id,
            period: configuration.period,
            metric: configuration.metric,
            ratings: .all
        )
    }

    func timeline(for configuration: StoreGaugePerformanceConfiguration, in context: Context) async -> Timeline<StoreGaugeWidgetEntry> {
        let entry = StoreGaugeWidgetEntry(
            date: Date(),
            snapshot: StoreGaugeWidgetStorage.load(),
            appID: configuration.app?.id,
            period: configuration.period,
            metric: configuration.metric,
            ratings: .all
        )
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 60)))
    }
}

nonisolated struct StoreGaugeFeedbackTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StoreGaugeWidgetEntry {
        StoreGaugeWidgetEntry(date: Date(), snapshot: .preview, appID: nil,
                              period: .sevenDays, metric: .both, ratings: .all)
    }

    func snapshot(for configuration: StoreGaugeFeedbackConfiguration, in context: Context) async -> StoreGaugeWidgetEntry {
        StoreGaugeWidgetEntry(date: Date(), snapshot: StoreGaugeWidgetStorage.load(),
                              appID: configuration.app?.id, period: .sevenDays,
                              metric: .both, ratings: configuration.ratings)
    }

    func timeline(for configuration: StoreGaugeFeedbackConfiguration, in context: Context) async -> Timeline<StoreGaugeWidgetEntry> {
        let entry = StoreGaugeWidgetEntry(date: Date(), snapshot: StoreGaugeWidgetStorage.load(),
                                          appID: configuration.app?.id, period: .sevenDays,
                                          metric: .both, ratings: configuration.ratings)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 60)))
    }
}

// MARK: - Selection and aggregation

private struct WidgetSelection {
    let snapshot: StoreGaugeWidgetSnapshot
    let appID: String?

    private var selectedApps: [WidgetAppSnapshot] {
        if let appID, let app = snapshot.apps.first(where: { $0.id == appID }) {
            return [app]
        }
        let selected = snapshot.apps.filter(\.isSelected)
        return selected.isEmpty ? snapshot.apps : selected
    }

    var title: String {
        guard let appID else { return "All Apps" }
        return snapshot.apps.first(where: { $0.id == appID })?.name ?? "All Apps"
    }

    var downloads: [WidgetMetricSample] { merge(selectedApps.map(\.downloads)) }
    var proceeds: [WidgetMetricSample] { merge(selectedApps.map(\.proceeds)) }
    var feedback: [WidgetFeedbackSnapshot] {
        selectedApps.flatMap(\.feedback).sorted { $0.createdDate > $1.createdDate }
    }

    var performanceURL: URL {
        if let appID { return URL(string: "storegauge://app/\(appID)")! }
        return URL(string: "storegauge://overview")!
    }

    var feedbackURL: URL {
        if let appID { return URL(string: "storegauge://app/\(appID)")! }
        return URL(string: "storegauge://reviews")!
    }

    private func merge(_ collections: [[WidgetMetricSample]]) -> [WidgetMetricSample] {
        var totals: [Date: Double] = [:]
        for sample in collections.joined() {
            totals[sample.date, default: 0] += sample.value
        }
        return totals
            .map { WidgetMetricSample(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
    }
}

private struct WidgetMetricSummary {
    let current: Double
    let delta: Double?

    init(_ samples: [WidgetMetricSample], days: Int) {
        let current = samples.suffix(days).reduce(0) { $0 + $1.value }
        let previous = samples.dropLast(min(days, samples.count)).suffix(days).reduce(0) { $0 + $1.value }
        self.current = current
        self.delta = previous > 0 ? (current - previous) / previous : nil
    }
}

// MARK: - Performance

struct StoreGaugePerformanceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: StoreGaugeWidgetConstants.performanceKind,
            intent: StoreGaugePerformanceConfiguration.self,
            provider: StoreGaugePerformanceTimelineProvider()
        ) { entry in
            PerformanceWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Performance")
        .description("Downloads, proceeds, and recent trends for your apps.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct PerformanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StoreGaugeWidgetEntry

    private var selection: WidgetSelection {
        WidgetSelection(snapshot: entry.snapshot, appID: entry.appID)
    }
    private var periodDays: Int { entry.period.days }
    private var downloads: WidgetMetricSummary { WidgetMetricSummary(selection.downloads, days: periodDays) }
    private var proceeds: WidgetMetricSummary { WidgetMetricSummary(selection.proceeds, days: periodDays) }
    private var periodTitle: String { "\(periodDays)d" }

    var body: some View {
        if entry.snapshot.apps.isEmpty {
            WidgetEmptyState(message: "Open StoreGauge to sync your apps")
                .widgetURL(URL(string: "storegauge://overview"))
        } else {
            VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 8) {
                WidgetHeader(title: "Performance", selection: selection.title, updatedAt: entry.snapshot.generatedAt)

                HStack(spacing: 8) {
                    if entry.metric != .proceeds {
                        WidgetMetricTile(
                            title: "Downloads · \(periodTitle)",
                            value: compact(downloads.current),
                            delta: downloads.delta,
                            symbol: "arrow.down.circle.fill",
                            tint: .blue
                        )
                    }
                    if entry.metric != .downloads {
                        WidgetMetricTile(
                            title: "Proceeds · \(periodTitle)",
                            value: money(proceeds.current, currency: entry.snapshot.currency),
                            delta: proceeds.delta,
                            symbol: "dollarsign.circle.fill",
                            tint: .green
                        )
                    }
                }

                if family == .systemLarge {
                    if entry.metric != .proceeds {
                        WidgetChartSection(title: "Downloads · \(periodTitle)",
                                           samples: Array(selection.downloads.suffix(periodDays)), tint: .blue)
                    }
                    if entry.metric != .downloads {
                        WidgetChartSection(title: "Proceeds · \(periodTitle)",
                                           samples: Array(selection.proceeds.suffix(periodDays)), tint: .green)
                    }
                } else {
                    WidgetTrendChart(
                        samples: Array((entry.metric == .proceeds ? selection.proceeds : selection.downloads)
                            .suffix(periodDays)),
                        tint: entry.metric == .proceeds ? .green : .blue
                    )
                        .frame(maxHeight: .infinity)
                }
            }
            .widgetURL(selection.performanceURL)
        }
    }

    private func compact(_ value: Double) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    private func money(_ value: Double, currency: String) -> String {
        value.formatted(.currency(code: currency).notation(.compactName).precision(.fractionLength(0...1)))
    }
}

private struct WidgetMetricTile: View {
    let title: String
    let value: String
    let delta: Double?
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                if let delta {
                    Text(delta, format: .percent.precision(.fractionLength(0)))
                        .foregroundStyle(delta >= 0 ? .green : .red)
                }
            }
            .font(.caption2)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct WidgetChartSection: View {
    let title: String
    let samples: [WidgetMetricSample]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            WidgetTrendChart(samples: samples, tint: tint)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct WidgetTrendChart: View {
    let samples: [WidgetMetricSample]
    let tint: Color

    var body: some View {
        Chart(samples, id: \.date) { sample in
            AreaMark(
                x: .value("Date", sample.date),
                y: .value("Value", sample.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom)
            )

            LineMark(
                x: .value("Date", sample.date),
                y: .value("Value", sample.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...max(1, (samples.map(\.value).max() ?? 0) * 1.08))
        .accessibilityLabel("30 day trend")
    }
}

// MARK: - Feedback

struct StoreGaugeFeedbackWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: StoreGaugeWidgetConstants.feedbackKind,
            intent: StoreGaugeFeedbackConfiguration.self,
            provider: StoreGaugeFeedbackTimelineProvider()
        ) { entry in
            FeedbackWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("New Feedback")
        .description("See recent customer reviews that still need attention.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct FeedbackWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StoreGaugeWidgetEntry

    private var selection: WidgetSelection {
        WidgetSelection(snapshot: entry.snapshot, appID: entry.appID)
    }
    private var rowLimit: Int { family == .systemLarge ? 5 : 2 }
    private var feedback: [WidgetFeedbackSnapshot] {
        selection.feedback.filter { entry.ratings.includes($0.rating) }
    }

    var body: some View {
        if entry.snapshot.apps.isEmpty {
            WidgetEmptyState(message: "Open StoreGauge to sync feedback")
                .widgetURL(URL(string: "storegauge://reviews"))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(
                    title: "New Feedback",
                    selection: selection.title,
                    updatedAt: entry.snapshot.generatedAt,
                    count: feedback.count
                )

                if feedback.isEmpty {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("You’re all caught up").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    VStack(spacing: 0) {
                        ForEach(feedback.prefix(rowLimit)) { item in
                            WidgetFeedbackRow(feedback: item)
                            if item.id != feedback.prefix(rowLimit).last?.id {
                                Divider().opacity(0.55)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .widgetURL(selection.feedbackURL)
        }
    }
}

private struct WidgetFeedbackRow: View {
    let feedback: WidgetFeedbackSnapshot

    private var text: String {
        feedback.title.isEmpty ? feedback.body : feedback.title
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(initials(feedback.appName))
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(stars(feedback.rating))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(feedback.rating <= 2 ? .red : feedback.rating == 3 ? .orange : .yellow)
                    Text(feedback.appName).font(.caption2.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text(feedback.createdDate, style: .relative)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Text(text).font(.caption.weight(.medium)).lineLimit(1).privacySensitive()
                if !feedback.body.isEmpty && feedback.body != text {
                    Text(feedback.body).font(.caption2).foregroundStyle(.secondary).lineLimit(1).privacySensitive()
                }
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private func stars(_ rating: Int) -> String {
        String(repeating: "★", count: max(0, min(5, rating)))
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

// MARK: - Shared widget chrome

private struct WidgetHeader: View {
    let title: String
    let selection: String
    let updatedAt: Date
    var count: Int?

    var body: some View {
        HStack(spacing: 7) {
            StoreGaugeWidgetMark(tint: .accentColor).frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.headline).lineLimit(1)
                Text(selection).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let count, count > 0 {
                Text(count > 99 ? "99+" : "\(count)")
                    .font(.caption2.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.red, in: Capsule())
            }
            Text(updatedAt, style: .relative)
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

private struct WidgetEmptyState: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            StoreGaugeWidgetMark(tint: .accentColor).frame(width: 36, height: 36)
            Text("StoreGauge").font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WidgetBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.07), Color.clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct StoreGaugeWidgetMark: View {
    var tint: Color = .primary

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height)
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.58)
            let radius = scale * 0.36
            let stroke = max(2.4, scale * 0.17)

            var arc = Path()
            arc.addArc(center: center, radius: radius,
                       startAngle: .degrees(148), endAngle: .degrees(392), clockwise: false)
            context.stroke(arc, with: .color(tint),
                           style: StrokeStyle(lineWidth: stroke, lineCap: .round))

            var needle = Path()
            needle.move(to: center)
            needle.addLine(to: CGPoint(x: size.width * 0.76, y: size.height * 0.29))
            context.stroke(needle, with: .color(tint),
                           style: StrokeStyle(lineWidth: stroke, lineCap: .round))

            let hub = CGRect(x: center.x - stroke * 0.62, y: center.y - stroke * 0.62,
                             width: stroke * 1.24, height: stroke * 1.24)
            context.fill(Path(ellipseIn: hub), with: .color(tint))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

@main
struct StoreGaugeWidgets: WidgetBundle {
    var body: some Widget {
        StoreGaugePerformanceWidget()
        StoreGaugeFeedbackWidget()
    }
}

private extension StoreGaugeWidgetSnapshot {
    nonisolated static var preview: StoreGaugeWidgetSnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(byAdding: .day, value: -29, to: Date()) ?? Date()
        let downloads = (0..<30).compactMap { offset -> WidgetMetricSample? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return WidgetMetricSample(date: date, value: Double(45 + (offset * 13) % 90))
        }
        let proceeds = downloads.map { WidgetMetricSample(date: $0.date, value: $0.value * 0.72) }
        let feedback = [
            WidgetFeedbackSnapshot(id: "preview-1", appID: "preview", appName: "Example App", rating: 2,
                                   title: "Please fix the latest update", body: "The app closes when I open settings.",
                                   territory: "US", createdDate: Date().addingTimeInterval(-3600)),
            WidgetFeedbackSnapshot(id: "preview-2", appID: "preview", appName: "Example App", rating: 5,
                                   title: "Really useful", body: "Exactly what I needed.",
                                   territory: "DE", createdDate: Date().addingTimeInterval(-7200))
        ]
        return StoreGaugeWidgetSnapshot(
            generatedAt: Date(),
            currency: "USD",
            apps: [WidgetAppSnapshot(id: "preview", appStoreID: "1", platformRaw: "apple-app-store",
                                     name: "Example App", isSelected: true,
                                     stateLabel: "Ready for Sale", downloads: downloads, proceeds: proceeds,
                                     feedback: feedback)]
        )
    }
}

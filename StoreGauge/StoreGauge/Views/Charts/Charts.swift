//
//  Charts.swift
//  StoreGauge
//
//  Reusable Swift Charts views.
//

import SwiftUI
import Charts

// MARK: - Annotations (chart layer)

extension AnnotationCategory {
    var color: Color {
        switch self {
        case .marketing: .purple
        case .bugfix: .red
        case .release: .blue
        case .experiment: .teal
        case .note: .orange
        }
    }
}

/// A lightweight, UI-only view of a `ChartAnnotation` so the chart views stay decoupled
/// from SwiftData. Carries everything needed to draw and identify a flag.
struct ChartAnnotationMark: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let note: String
    let category: AnnotationCategory
    var color: Color { category.color }
    var symbol: String { category.symbol }
}

/// Colour-coded flags for each annotation, drawn inside a `Chart`. The flag itself is a
/// click target (→ edit) and carries a native tooltip with the note, so clicking or
/// hovering a flag surfaces it without a full-plot overlay that would block chart hover.
@ChartContentBuilder
func annotationFlags(_ marks: [ChartAnnotationMark], onEdit: ((UUID) -> Void)? = nil) -> some ChartContent {
    ForEach(marks) { m in
        RuleMark(x: .value("Note", m.date))
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .foregroundStyle(m.color.opacity(0.8))
            .annotation(position: .top, spacing: 0) {
                Image(systemName: m.symbol).font(.system(size: 9)).foregroundStyle(m.color)
                    .padding(2).contentShape(Rectangle())
                    .help(m.note)
                    .onTapGesture { onEdit?(m.id) }
            }
    }
}

/// Adds right-click-to-add (and right-click-to-edit on an annotated day) via a context
/// menu keyed off the hovered date. Deliberately avoids a hit-testing plot overlay so
/// `chartXSelection`'s hover tracking keeps working; clicking a flag handles edit instead.
struct ChartAnnotationInteraction: ViewModifier {
    let annotations: [ChartAnnotationMark]
    let hoveredDate: Date?
    var onAdd: ((Date) -> Void)? = nil
    var onEdit: ((UUID) -> Void)? = nil

    private func annotation(on date: Date?) -> ChartAnnotationMark? {
        guard let date else { return nil }
        let day = date.startOfDayUTC
        return annotations.first { $0.date.startOfDayUTC == day }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if onAdd == nil {
            content
        } else {
            content.contextMenu {
                if let d = hoveredDate {
                    Button { onAdd?(d.startOfDayUTC) } label: {
                        Label("Add annotation on \(d.formatted(.dateTime.month(.abbreviated).day()))…",
                              systemImage: "flag")
                    }
                    if let hit = annotation(on: d), let onEdit {
                        Button { onEdit(hit.id) } label: { Label("Edit “\(hit.note)”…", systemImage: "pencil") }
                    }
                } else {
                    Text("Hover a day, then right-click to annotate")
                }
            }
        }
    }
}

extension View {
    func chartAnnotations(_ marks: [ChartAnnotationMark], hovered: Date?,
                          onAdd: ((Date) -> Void)?, onEdit: ((UUID) -> Void)?) -> some View {
        modifier(ChartAnnotationInteraction(annotations: marks, hoveredDate: hovered, onAdd: onAdd, onEdit: onEdit))
    }
}

// MARK: - Sparkline

struct Sparkline: View {
    let values: [Double]
    var tint: Color = .accentColor
    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { index, value in
            LineMark(x: .value("i", index), y: .value("v", value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            AreaMark(x: .value("i", index), y: .value("v", value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: true))
    }
}

// MARK: - Trend (area + line)

struct TrendChart: View {
    let series: [DatedValue]
    var tint: Color = .green
    var isCurrency: Bool = false
    var isPercentage: Bool = false
    var currencyCode: String = "USD"
    var yDomain: ClosedRange<Double>? = nil
    var markers: [Date] = []
    var annotations: [ChartAnnotationMark] = []
    var onAddAnnotation: ((Date) -> Void)? = nil
    var onEditAnnotation: ((UUID) -> Void)? = nil
    @State private var selectedDate: Date?

    private func clip(_ dates: [Date]) -> [Date] {
        guard let lo = series.map(\.date).min(), let hi = series.map(\.date).max() else { return [] }
        return dates.filter { $0 >= lo && $0 <= hi }
    }
    private var clippedAnnotations: [ChartAnnotationMark] {
        guard let lo = series.map(\.date).min(), let hi = series.map(\.date).max() else { return [] }
        return annotations.filter { $0.date >= lo && $0.date <= hi }
    }
    private func notes(on date: Date) -> [ChartAnnotationMark] {
        annotations.filter { $0.date.startOfDayUTC == date.startOfDayUTC }
    }

    private var effectiveDomain: ClosedRange<Double> {
        if let yDomain { return yDomain }
        let floor = isPercentage ? 0.001 : 1
        let maxV = max(series.map(\.value).max() ?? floor, floor)
        return 0...(maxV * 1.15)
    }

    private var selectedPoint: DatedValue? {
        guard let selectedDate, !series.isEmpty else { return nil }
        return series.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    private func label(_ v: Double) -> String {
        if isCurrency { return Format.currency(v, code: currencyCode) }
        if isPercentage { return Format.percentRate(v) }
        return Format.int(v)
    }

    var body: some View {
        Chart {
            ForEach(series) { point in
                AreaMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.45), tint.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            ForEach(clip(markers), id: \.self) { d in
                RuleMark(x: .value("Change", d))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.purple.opacity(0.55))
            }
            annotationFlags(clippedAnnotations, onEdit: onEditAnnotation)
            if let sp = selectedPoint {
                RuleMark(x: .value("Date", sp.date))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartCallout(title: sp.date.formatted(.dateTime.month(.abbreviated).day()), value: label(sp.value), tint: tint, notes: notes(on: sp.date))
                    }
                PointMark(x: .value("Date", sp.date), y: .value("Value", sp.value))
                    .foregroundStyle(tint)
                    .symbolSize(60)
            }
        }
        .chartYScale(domain: effectiveDomain)
        .chartXSelection(value: $selectedDate)
        .chartAnnotations(annotations, hovered: selectedDate ?? selectedPoint?.date, onAdd: onAddAnnotation, onEdit: onEditAnnotation)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(.quaternary)
                if let d = value.as(Double.self) {
                    AxisValueLabel {
                        Text(isCurrency
                             ? Format.currency(d, code: currencyCode, compact: true)
                             : (isPercentage ? Format.percentRate(d) : Format.compact(d)))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
    }
}

/// Floating value label shown when a chart point is selected. When the hovered day has
/// annotations, their notes are listed underneath the value.
struct ChartCallout: View {
    let title: String
    let value: String
    var tint: Color = .accentColor
    var notes: [ChartAnnotationMark] = []
    var body: some View {
        VStack(alignment: .leading, spacing: notes.isEmpty ? 1 : 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption.weight(.semibold)).foregroundStyle(tint)
            }
            if !notes.isEmpty {
                Divider()
                ForEach(notes) { n in
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: n.symbol).font(.system(size: 8)).foregroundStyle(n.color)
                            .frame(width: 10)
                        Text(n.note).font(.caption2).foregroundStyle(.primary).lineLimit(2)
                    }
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .frame(maxWidth: notes.isEmpty ? nil : 190, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
        .fixedSize(horizontal: notes.isEmpty, vertical: true)
    }
}

// MARK: - Bar trend

struct BarTrendChart: View {
    let series: [DatedValue]
    var tint: Color = .blue
    var markers: [Date] = []
    var annotations: [ChartAnnotationMark] = []
    var onAddAnnotation: ((Date) -> Void)? = nil
    var onEditAnnotation: ((UUID) -> Void)? = nil
    @State private var selectedDate: Date?

    private var selectedPoint: DatedValue? {
        guard let selectedDate, !series.isEmpty else { return nil }
        return series.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private func clip(_ dates: [Date]) -> [Date] {
        guard let lo = series.map(\.date).min(), let hi = series.map(\.date).max() else { return [] }
        return dates.filter { $0 >= lo && $0 <= hi }
    }
    private var clippedAnnotations: [ChartAnnotationMark] {
        guard let lo = series.map(\.date).min(), let hi = series.map(\.date).max() else { return [] }
        return annotations.filter { $0.date >= lo && $0.date <= hi }
    }
    private func notes(on date: Date) -> [ChartAnnotationMark] {
        annotations.filter { $0.date.startOfDayUTC == date.startOfDayUTC }
    }

    var body: some View {
        Chart {
            ForEach(series) { point in
                BarMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(LinearGradient(colors: [tint, tint.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                    .opacity(selectedPoint == nil || selectedPoint?.id == point.id ? 1 : 0.35)
                    .cornerRadius(3)
            }
            ForEach(clip(markers), id: \.self) { d in
                RuleMark(x: .value("Change", d))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.purple.opacity(0.55))
            }
            annotationFlags(clippedAnnotations, onEdit: onEditAnnotation)
            if let sp = selectedPoint {
                RuleMark(x: .value("Date", sp.date))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartCallout(title: sp.date.formatted(.dateTime.month(.abbreviated).day()), value: Format.int(sp.value), tint: tint, notes: notes(on: sp.date))
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartAnnotations(annotations, hovered: selectedDate ?? selectedPoint?.date, onAdd: onAddAnnotation, onEdit: onEditAnnotation)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(.quaternary)
                if let d = value.as(Double.self) {
                    AxisValueLabel { Text(Format.compact(d)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
    }
}

// MARK: - App Store funnel

struct FunnelCard: View {
    let impressions: Double
    let pageViews: Double
    let downloads: Double

    var body: some View {
        let stages: [(String, Double, Color)] = [
            ("Impressions", impressions, .cyan),
            ("Product Page Views", pageViews, .orange),
            ("Downloads", downloads, .blue),
        ]
        let maxV = max(impressions, pageViews, downloads, 1)
        let cvr = impressions > 0 ? downloads / impressions : 0
        return ChartCard(title: "App Store Funnel", symbol: "line.3.horizontal.decrease.circle.fill",
                         subtitle: "\(Format.percentPlain(cvr)) conversion") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(stages.enumerated()), id: \.offset) { i, stage in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(stage.0).font(.caption.weight(.medium))
                            Spacer()
                            Text(Format.compact(stage.1)).font(.caption.monospacedDigit().weight(.semibold))
                            if i > 0 {
                                let prev = stages[i - 1].1
                                Text(prev > 0 ? Format.percentPlain(stage.1 / prev) : "—")
                                    .font(.caption2).foregroundStyle(.green).frame(width: 46, alignment: .trailing)
                            } else {
                                Color.clear.frame(width: 46, height: 1)
                            }
                        }
                        GeometryReader { geo in
                            Capsule().fill(stage.2.gradient)
                                .frame(width: max(4, geo.size.width * CGFloat(stage.1 / maxV)))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 14)
                    }
                }
            }
            .frame(minHeight: 120)
        }
    }
}

// MARK: - Stacked bars

struct StackedBarChart: View {
    struct Series: Identifiable {
        let id: String
        let name: String
        let color: Color
        let points: [DatedValue]
    }
    let series: [Series]
    var markers: [Date] = []
    var annotations: [ChartAnnotationMark] = []
    var onAddAnnotation: ((Date) -> Void)? = nil
    var onEditAnnotation: ((UUID) -> Void)? = nil
    @State private var selectedDate: Date?
    @State private var hiddenSeries: Set<String> = []

    private var visibleSeries: [Series] {
        series.filter { !hiddenSeries.contains($0.id) }
    }

    private func clip(_ dates: [Date]) -> [Date] {
        let all = series.flatMap { $0.points.map(\.date) }
        guard let lo = all.min(), let hi = all.max() else { return [] }
        return dates.filter { $0 >= lo && $0 <= hi }
    }
    private var clippedAnnotations: [ChartAnnotationMark] {
        let all = series.flatMap { $0.points.map(\.date) }
        guard let lo = all.min(), let hi = all.max() else { return [] }
        return annotations.filter { $0.date >= lo && $0.date <= hi }
    }
    private func notes(on date: Date) -> [ChartAnnotationMark] {
        annotations.filter { $0.date.startOfDayUTC == date.startOfDayUTC }
    }
    private var allDates: [Date] { Array(Set(visibleSeries.flatMap { $0.points.map(\.date) })).sorted() }
    private var selectedDay: Date? {
        guard let selectedDate, !allDates.isEmpty else { return nil }
        return allDates.min { abs($0.timeIntervalSince(selectedDate)) < abs($1.timeIntervalSince(selectedDate)) }
    }
    private func value(on day: Date, _ s: Series) -> Double { s.points.first { $0.date == day }?.value ?? 0 }
    private var clippedMarkers: [Date] {
        let dates = series.flatMap { $0.points.map(\.date) }
        guard let lo = dates.min(), let hi = dates.max() else { return [] }
        return markers.filter { $0 >= lo && $0 <= hi }
    }

    var body: some View {
        Chart {
            ForEach(visibleSeries) { s in
                ForEach(s.points) { p in
                    BarMark(x: .value("Date", p.date), y: .value("Count", p.value))
                        .foregroundStyle(by: .value("Type", s.name))
                }
            }
            ForEach(clip(markers), id: \.self) { d in
                RuleMark(x: .value("Change", d))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.purple.opacity(0.55))
            }
            annotationFlags(clippedAnnotations, onEdit: onEditAnnotation)
            if let day = selectedDay {
                RuleMark(x: .value("Date", day))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        callout(day)
                    }
            }
        }
        .chartForegroundStyleScale(domain: series.map(\.name), range: series.map(\.color))
        .chartLegend(position: .top, alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(series) { item in
                    legendButton(item)
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartAnnotations(annotations, hovered: selectedDate ?? selectedDay, onAdd: onAddAnnotation, onEdit: onEditAnnotation)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(.quaternary)
                if let d = value.as(Double.self) { AxisValueLabel { Text(Format.compact(d)) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
    }

    @ViewBuilder private func callout(_ day: Date) -> some View {
        let total = visibleSeries.reduce(0.0) { $0 + value(on: day, $1) }
        VStack(alignment: .leading, spacing: 2) {
            Text(day.formatted(.dateTime.month(.abbreviated).day())).font(.caption2).foregroundStyle(.secondary)
            ForEach(visibleSeries) { s in
                HStack(spacing: 4) {
                    Circle().fill(s.color).frame(width: 6, height: 6)
                    Text(s.name.components(separatedBy: " (").first ?? s.name).font(.caption2)
                    Spacer(minLength: 8)
                    Text(Format.int(value(on: day, s))).font(.caption2.weight(.semibold))
                }
            }
            Divider()
            HStack { Text("Total").font(.caption2); Spacer(); Text(Format.int(total)).font(.caption2.weight(.bold)) }
            let dayNotes = notes(on: day)
            if !dayNotes.isEmpty {
                Divider()
                ForEach(dayNotes) { n in
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: n.symbol).font(.system(size: 8)).foregroundStyle(n.color).frame(width: 10)
                        Text(n.note).font(.caption2).lineLimit(2)
                    }
                }
            }
        }
        .padding(8).frame(width: 140)
        .background(RoundedRectangle(cornerRadius: 6).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
    }

    private func legendButton(_ item: Series) -> some View {
        let isVisible = !hiddenSeries.contains(item.id)
        let canHide = visibleSeries.count > 1
        return Button {
            if isVisible {
                if canHide { hiddenSeries.insert(item.id) }
            } else {
                hiddenSeries.remove(item.id)
            }
        } label: {
            HStack(spacing: 4) {
                Circle().fill(item.color).frame(width: 7, height: 7)
                Text(item.name).font(.caption2.weight(.medium))
            }
            .foregroundStyle(isVisible ? .primary : .secondary)
            .opacity(isVisible ? 1 : 0.45)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.secondary.opacity(isVisible ? 0.1 : 0.04)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isVisible ? (canHide ? "Hide \(item.name)" : "At least one download type must remain visible")
                        : "Show \(item.name)")
        .accessibilityValue(isVisible ? "Shown" : "Hidden")
    }
}

// MARK: - Status donut

struct StatusDonut: View {
    struct Slice: Identifiable { let category: AppStoreState.Category; let count: Int; var id: String { category.rawValue } }
    let slices: [Slice]

    var total: Int { slices.reduce(0) { $0 + $1.count } }

    var body: some View {
        Chart(slices) { slice in
            SectorMark(angle: .value("Count", slice.count), innerRadius: .ratio(0.62), angularInset: 1.5)
                .foregroundStyle(slice.category.color)
                .cornerRadius(3)
        }
        .chartLegend(.hidden)
        .overlay {
            VStack(spacing: 0) {
                Text("\(total)").font(.system(.title2, design: .rounded).weight(.bold))
                Text("apps").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Rating distribution

struct RatingBars: View {
    /// counts indexed by star (1...5)
    let counts: [Int: Int]
    var maxCount: Int { max(1, counts.values.max() ?? 1) }

    var body: some View {
        VStack(spacing: 4) {
            ForEach((1...5).reversed(), id: \.self) { star in
                HStack(spacing: 8) {
                    HStack(spacing: 1) {
                        Text("\(star)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(star.ratingColor)
                    }
                    .frame(width: 26, alignment: .leading)
                    GeometryReader { geo in
                        let c = counts[star] ?? 0
                        Capsule()
                            .fill(star.ratingColor.opacity(0.85))
                            .frame(width: max(2, geo.size.width * CGFloat(c) / CGFloat(maxCount)))
                            .frame(maxHeight: .infinity, alignment: .leading)
                    }
                    .frame(height: 12)
                    Text("\(counts[star] ?? 0)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }
}

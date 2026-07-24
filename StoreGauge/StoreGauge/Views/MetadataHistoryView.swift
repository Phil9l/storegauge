//
//  MetadataHistoryView.swift
//  StoreGauge
//
//  App-listing surface: current screenshots + a version-grouped metadata change
//  history ("blame") with Versions / Fields / Timeline views.
//

import SwiftUI
import SwiftData
import Charts

// MARK: - Screenshots

struct AppScreenshotsCard: View {
    let app: TrackedApp
    @Environment(AppModel.self) private var model
    @State private var locale = ""
    @State private var groups: [ScreenshotGroup] = []
    @State private var loading = false

    private var locales: [String] {
        let s = Set(app.metadataSnapshots.map(\.locale))
        return s.isEmpty ? ["en-US"] : s.sorted()
    }

    var body: some View {
        ChartCard(title: "Screenshots", symbol: "photo.on.rectangle.angled",
                  subtitle: groups.reduce(0) { $0 + $1.shots.count } > 0 ? "\(groups.reduce(0) { $0 + $1.shots.count })" : nil) {
            VStack(alignment: .leading, spacing: 12) {
                if locales.count > 1 {
                    Picker("Locale", selection: $locale) {
                        ForEach(locales, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(maxWidth: 160)
                }
                if loading {
                    HStack { ProgressView().controlSize(.small); Text("Loading…").font(.caption).foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, minHeight: 90)
                } else if groups.isEmpty {
                    Text("No screenshots for this localization.").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                } else {
                    ForEach(groups) { g in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(g.label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(g.shots) { s in
                                        AsyncImage(url: URL(string: s.url)) { img in
                                            img.resizable().scaledToFit()
                                        } placeholder: {
                                            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                                                .frame(width: 100, height: 180)
                                        }
                                        .frame(height: 180)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { if locale.isEmpty { locale = locales.contains("en-US") ? "en-US" : (locales.first ?? "en-US") } }
        .task(id: locale) {
            guard !locale.isEmpty else { return }
            loading = true
            groups = await model.screenshots(for: app, locale: locale)
            loading = false
        }
    }
}

// MARK: - Metadata history (version-grouped)

struct MetadataHistoryCard: View {
    let app: TrackedApp
    @State private var localeFilter = ""
    @State private var mode: Mode = .versions
    @State private var fieldFilter: MetadataField = .keywords
    @State private var expanded: Set<String> = []

    enum Mode: String, CaseIterable, Identifiable { case versions = "Versions", fields = "Fields", timeline = "Timeline"; var id: String { rawValue } }

    private var allChanges: [MetadataChange] { app.metadataChanges }
    private var locales: [String] { Array(Set(allChanges.map(\.locale))).sorted() }
    private var localeChanges: [MetadataChange] {
        allChanges.filter { localeFilter.isEmpty || $0.locale == localeFilter }
    }

    private struct VersionGroup: Identifiable {
        let version: String; let date: Date; let changes: [MetadataChange]
        var id: String { version }
    }
    private var versionGroups: [VersionGroup] {
        Dictionary(grouping: localeChanges) { $0.versionString ?? "—" }
            .map { VersionGroup(version: $0.key, date: $0.value.map(\.date).max() ?? .distantPast,
                                changes: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        ChartCard(title: "Metadata History", symbol: "clock.badge") {
            VStack(alignment: .leading, spacing: 12) {
                if allChanges.isEmpty {
                    Text("No listing changes recorded yet. StoreGauge backfills your version history on first sync and tracks new edits across every localization from then on.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    header
                    switch mode {
                    case .versions: versionsView
                    case .fields: fieldsView
                    case .timeline: timelineView
                    }
                }
            }
        }
        .onAppear { if localeFilter.isEmpty { localeFilter = locales.contains("en-US") ? "en-US" : (locales.first ?? "") } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Picker("", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).fixedSize()
            Spacer()
            Picker("", selection: $localeFilter) {
                Text("All locales").tag("")
                ForEach(locales, id: \.self) { Text($0).tag($0) }
            }.labelsHidden().frame(maxWidth: 150)
        }
    }

    // Versions
    private var versionsView: some View {
        VStack(spacing: 0) {
            if versionGroups.isEmpty { emptyText } else {
                ForEach(versionGroups.prefix(25)) { vg in
                    versionRow(vg)
                    if vg.id != versionGroups.prefix(25).last?.id { Divider() }
                }
            }
        }
    }

    private func versionRow(_ vg: VersionGroup) -> some View {
        let fields = Set(vg.changes.map(\.field))
        let isOpen = expanded.contains(vg.id)
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                if isOpen { expanded.remove(vg.id) } else { expanded.insert(vg.id) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary).frame(width: 10)
                    Text(vg.version == "—" ? "Edit" : "v\(vg.version)").font(.callout.weight(.medium))
                    Text(Format.mediumDate.string(from: vg.date)).font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    HStack(spacing: 5) {
                        ForEach(MetadataField.allCases.filter { fields.contains($0) }, id: \.self) { f in
                            Image(systemName: f.symbol).font(.system(size: 9)).foregroundStyle(.tint)
                                .help(f.label)
                        }
                    }
                    Text("\(vg.changes.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            if isOpen {
                VStack(spacing: 0) {
                    ForEach(vg.changes, id: \.persistentModelID) { c in
                        MetadataChangeRow(change: c, showMeta: false)
                    }
                }.padding(.leading, 16)
            }
        }
        .padding(.vertical, 5)
    }

    // Fields
    private var fieldsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Field", selection: $fieldFilter) {
                ForEach(MetadataField.allCases, id: \.self) { Label($0.label, systemImage: $0.symbol).tag($0) }
            }.frame(maxWidth: 240)
            let fieldChanges = localeChanges.filter { $0.field == fieldFilter }.sorted { $0.date > $1.date }
            if fieldChanges.isEmpty { emptyText } else {
                VStack(spacing: 0) {
                    ForEach(fieldChanges.prefix(50), id: \.persistentModelID) { c in
                        MetadataChangeRow(change: c, showMeta: true)
                        if c.persistentModelID != fieldChanges.prefix(50).last?.persistentModelID { Divider() }
                    }
                }
            }
        }
    }

    // Timeline (Gantt-style lanes)
    private var timelineView: some View {
        let fieldsPresent = MetadataField.allCases.filter { f in localeChanges.contains { $0.field == f } }
        return VStack(alignment: .leading, spacing: 6) {
            if localeChanges.isEmpty { emptyText } else {
                Chart(localeChanges, id: \.persistentModelID) { c in
                    PointMark(x: .value("Date", c.date), y: .value("Field", c.field.label))
                        .foregroundStyle(by: .value("Field", c.field.label))
                        .symbolSize(50)
                }
                .chartYScale(domain: fieldsPresent.map(\.label))
                .chartLegend(.hidden)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .frame(height: max(130, CGFloat(fieldsPresent.count) * 28))
                Text("Each dot marks a change to that field over time.").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var emptyText: some View {
        Text("No changes for this filter.").font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
    }
}

struct MetadataChangeRow: View {
    let change: MetadataChange
    var showMeta: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: change.field.symbol).foregroundStyle(.tint).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(change.field.label).font(.caption.weight(.semibold))
                    if showMeta {
                        Text(change.locale).font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(.secondary.opacity(0.15)))
                        if let v = change.versionString { Text("v\(v)").font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text(Format.relativeDate(change.date)).font(.caption2).foregroundStyle(.tertiary)
                }
                diff
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private var diff: some View {
        if change.field == .screenshots {
            Text("\(count(change.oldValue)) → \(count(change.newValue)) screenshots")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                if let old = change.oldValue, !old.isEmpty {
                    Text(old).font(.caption).foregroundStyle(.red.opacity(0.75)).strikethrough().lineLimit(3).textSelection(.enabled)
                }
                if let new = change.newValue, !new.isEmpty {
                    Text(new).font(.caption).foregroundStyle(.green).lineLimit(3).textSelection(.enabled)
                } else {
                    Text("removed").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func count(_ s: String?) -> String { s?.split(separator: "#").first.map(String.init) ?? "0" }
}

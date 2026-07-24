//
//  SubscriptionsView.swift
//  StoreGauge
//
//  Active subscribers, MRR, trials and per-subscription / per-country breakdown
//  from Apple's daily SUBSCRIPTION report.
//

import SwiftUI
import SwiftData

struct SubscriptionsView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \TrackedApp.name) private var apps: [TrackedApp]
    @Query(sort: \Account.sortIndex) private var accounts: [Account]

    @State private var rangeDays = 30

    private var settings: AppSettings { model.settings }
    private var currency: String { settings.displayCurrency }
    private var hasVendor: Bool {
        accounts.contains {
            $0.platform == .appleAppStore && ($0.vendorNumber?.trimmingCharacters(in: .whitespaces).isEmpty == false)
        }
    }
    private var data: AppModel.SubscriptionData? { model.subscriptionData }
    private var loading: Bool { model.subLoading }
    private var appByID: [String: TrackedApp] {
        Dictionary(apps.filter { !$0.isArchived }.map { ($0.id.uuidString, $0) },
                   uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        Group {
            if !hasVendor {
                VStack(spacing: 14) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle").font(.system(size: 44)).foregroundStyle(.secondary.opacity(0.6))
                    Text("Add a vendor number").font(.title3.weight(.semibold))
                    Text("Subscription data comes from Apple's subscription reports, which need your vendor number. Add it to your account in Settings.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
                    SettingsLink { Label("Open Settings", systemImage: "gearshape") }.controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
            } else {
                content
            }
        }
        .navigationTitle("Subscriptions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("", selection: $rangeDays) { Text("7D").tag(7); Text("30D").tag(30); Text("90D").tag(90) }
                    .pickerStyle(.segmented).fixedSize()
            }
            ToolbarItem(placement: .primaryAction) {
                Button { exportCSV() } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(data?.bySubscription.isEmpty ?? true)
            }
        }
        .task(id: rangeDays) { model.ensureSubscriptions(days: rangeDays) }
        .onChange(of: currency) { model.ensureSubscriptions(days: rangeDays, force: true) }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Subscriptions").font(.system(.largeTitle, design: .rounded).weight(.bold))
                        Text(data?.snapshotDate.map { "Snapshot · \(Format.mediumDate.string(from: $0))" } ?? "Loading…")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if loading { HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Loading…").font(.caption).foregroundStyle(.secondary) } }
                }

                if data == nil {
                    VStack(spacing: 10) {
                        ProgressView(value: model.subProgress).progressViewStyle(.linear).frame(maxWidth: 260)
                        Text("Scanning subscription reports… \(Int(model.subProgress * 100))%")
                            .font(.callout).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, minHeight: 260)
                } else if (data?.totalActive ?? 0) == 0 && (data?.bySubscription.isEmpty ?? true) {
                    EmptyStateView(symbol: "person.crop.circle.badge.questionmark",
                                   title: "No active subscriptions",
                                   message: "When you have active subscribers they'll appear here with MRR, trials and country breakdowns.")
                        .frame(minHeight: 260)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        kpis
                        ChartCard(title: "Active Subscribers", symbol: "person.2.fill",
                                  subtitle: "\(data?.totalActive ?? 0)") {
                            TrendChart(series: data?.trend ?? [], tint: .pink).frame(height: 170)
                        }
                        eventsCard
                        HStack(alignment: .top, spacing: 14) {
                            bySubscriptionCard
                            byCountryCard
                        }
                    }
                    .opacity(loading ? 0.5 : 1)
                    .animation(.default, value: loading)
                }
            }
            .padding(20)
        }
        .background(.windowFill)
    }

    private var kpis: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
            KPITile(title: "Active Subscribers", value: "\(data?.totalActive ?? 0)",
                    subtitle: "\(data?.bySubscription.count ?? 0) products", symbol: "person.2.fill", tint: .pink)
            KPITile(title: "MRR", value: Format.currency(data?.mrr ?? 0, code: currency),
                    subtitle: "monthly recurring", symbol: "arrow.triangle.2.circlepath", tint: .green)
            KPITile(title: "Paying", value: "\(data?.totalPaid ?? 0)",
                    subtitle: "standard + intro", symbol: "creditcard.fill", tint: .blue)
            KPITile(title: "Free Trials", value: "\(data?.totalTrials ?? 0)",
                    subtitle: "active trials", symbol: "gift.fill", tint: .orange)
        }
    }

    private var eventsCard: some View {
        let ev = data?.events ?? [:]
        let order = ["New", "Trial→Paid", "Renewals", "Reactivations", "Cancelled", "Refunds"]
        let colors: [String: Color] = ["New": .green, "Trial→Paid": .mint, "Renewals": .blue,
                                       "Reactivations": .teal, "Cancelled": .orange, "Refunds": .red]
        let net = (ev["New"] ?? 0) + (ev["Reactivations"] ?? 0) - (ev["Cancelled"] ?? 0)
        let extras = ev.keys.filter { !order.contains($0) }.sorted()
        return ChartCard(title: "Subscriber Changes", symbol: "arrow.left.arrow.right", subtitle: "last \(rangeDays)d") {
            if ev.isEmpty {
                Text("No subscription events in this period (new, cancellations, renewals, refunds appear here).")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                        ForEach(order.filter { ev[$0] != nil } + extras, id: \.self) { k in
                            HStack(spacing: 8) {
                                Circle().fill(colors[k] ?? .gray).frame(width: 8, height: 8)
                                Text(k).font(.caption)
                                Spacer()
                                Text("\(ev[k] ?? 0)").font(.callout.monospacedDigit().weight(.semibold))
                            }
                            .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
                        }
                    }
                    HStack {
                        Text("Net change").font(.caption.weight(.medium))
                        Spacer()
                        Text(net >= 0 ? "+\(net)" : "\(net)").font(.callout.weight(.bold)).foregroundStyle(net >= 0 ? .green : .red)
                    }
                }
            }
        }
    }

    private func exportCSV() {
        guard let d = data else { return }
        var lines = ["Subscription,App,Active,Paying,Trials,MRR,Currency"]
        for s in d.bySubscription.values.sorted(by: { $0.active > $1.active }) {
            lines.append(CSVExporter.row([s.name, appByID[s.appID]?.name ?? s.appID,
                                          "\(s.active)", "\(s.paid)", "\(s.trials)", String(format: "%.2f", s.mrr), currency]))
        }
        lines.append("")
        lines.append("Country,Active Subscribers")
        for (code, c) in d.byCountry.sorted(by: { $0.value > $1.value }) {
            lines.append(CSVExporter.row([code, "\(c)"]))
        }
        #if os(macOS)
        CSVExporter.save(lines.joined(separator: "\n"), suggestedName: "subscriptions.csv")
        #endif
    }

    private var bySubscriptionCard: some View {
        ChartCard(title: "By Subscription", symbol: "list.bullet.rectangle.fill") {
            let rows = (data?.bySubscription.values.sorted { $0.active > $1.active } ?? [])
            if rows.isEmpty {
                Text("No subscriptions.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, s in
                        HStack(spacing: 8) {
                            if let app = appByID[s.appID] { AppIconView(app: app, size: 24, showsStoreBadge: true) }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.name.isEmpty ? "Subscription" : s.name).font(.caption.weight(.medium)).lineLimit(1)
                                Text("\(s.active) active · \(s.trials) trials").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Format.currency(s.mrr, code: currency, compact: true) + "/mo")
                                .font(.caption.monospacedDigit()).foregroundStyle(.green)
                        }
                    }
                }.frame(minHeight: 100)
            }
        }
    }

    private var byCountryCard: some View {
        ChartCard(title: "Subscribers by Country", symbol: "globe") {
            let rows = (data?.byCountry.sorted { $0.value > $1.value } ?? []).prefix(10)
            if rows.isEmpty {
                Text("No data.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100)
            } else {
                let maxV = rows.map(\.value).max() ?? 1
                VStack(spacing: 8) {
                    ForEach(Array(rows), id: \.key) { code, count in
                        HStack(spacing: 8) {
                            Text(flagEmoji(for: code))
                            Text(code).font(.caption.weight(.medium)).frame(width: 28, alignment: .leading)
                            GeometryReader { geo in
                                Capsule().fill(.pink.gradient)
                                    .frame(width: max(3, geo.size.width * CGFloat(Double(count) / Double(max(maxV, 1)))))
                                    .frame(maxHeight: .infinity, alignment: .leading)
                            }.frame(height: 12)
                            Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                        }
                    }
                }.frame(minHeight: 100)
            }
        }
    }
}

//
//  MenuBarView.swift
//  StoreGauge
//
//  Rich menu-bar popover: quick stats + untriaged reviews + actions.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage("selectedSettingsSection") private var selectedSettingsSection = SettingsSection.accounts
    @Query(sort: \TrackedApp.name) private var apps: [TrackedApp]
    @Query(filter: #Predicate<Review> { $0.responseBody == nil && !$0.isAcknowledged },
           sort: \Review.createdDate, order: .reverse) private var pending: [Review]

    private var settings: AppSettings { model.settings }
    private var selectedApps: [TrackedApp] { apps.filter { $0.isSelected && !$0.isArchived } }
    private var untriaged: [Review] {
        pending.filter { $0.app?.isSelected == true && $0.app?.isArchived != true }
            .sorted { ($0.rating, $1.createdDate) < ($1.rating, $0.createdDate) }
    }
    private var agg: MetricsAggregator {
        MetricsAggregator(apps: selectedApps, fx: model.fx, currency: settings.displayCurrency)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let error = model.lastSyncError {
                Divider()
                Button {
                    selectedSettingsSection = .syncHealth
                    openSettings()
                } label: {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }
            Divider()
            stats
            Divider()
            quickActions
            Divider()
            reviewsSection
            Divider()
            footer
        }
        .frame(width: 340)
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            Button { openDestination(.overview) } label: {
                Label("Dashboard", systemImage: "square.grid.2x2")
            }
            Button { openDestination(.reviews) } label: {
                Label("Reviews", systemImage: "star.bubble")
            }
            Button { copySummary() } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Spacer(minLength: 0)
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var header: some View {
        HStack {
            StoreGaugeMark().frame(width: 18, height: 18)
            Text("StoreGauge").font(.headline)
            Spacer()
            if model.isSyncing {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await model.syncNow() } } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(.borderless).help("Sync now")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var stats: some View {
        HStack(spacing: 10) {
            MiniStat(title: "Proceeds · 7d",
                     value: Format.currency(agg.total(.proceeds, days: 7), code: settings.displayCurrency, compact: true),
                     symbol: "dollarsign.circle.fill", tint: .green)
            MiniStat(title: "Downloads · 7d",
                     value: Format.compact(agg.total(agg.hasAny(.installs) ? .installs : .units, days: 7)),
                     symbol: "arrow.down.circle.fill", tint: .blue)
            MiniStat(title: "Needs Reply",
                     value: "\(untriaged.count)",
                     symbol: "exclamationmark.bubble.fill", tint: .orange)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Needs Reply").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if !untriaged.isEmpty {
                    Button("Acknowledge all") { model.acknowledge(untriaged) }
                        .buttonStyle(.link).font(.caption2)
                }
            }
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4)

            if untriaged.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("You're all caught up").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 14)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(untriaged.prefix(6)) { r in
                            MenuReviewRow(
                                review: r,
                                open: {
                                    if let id = r.app?.id { openDestination(.app(id)) }
                                    else { openDestination(.reviews) }
                                },
                                markRead: { model.acknowledge([r]) }
                            )
                            if r.id != untriaged.prefix(6).last?.id { Divider().padding(.leading, 14) }
                        }
                    }
                }
                .frame(maxHeight: 260)
                if untriaged.count > 6 {
                    Text("+ \(untriaged.count - 6) more").font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 14).padding(.bottom, 6)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                openMainWindow()
            } label: { Label("Open", systemImage: "macwindow") }
            SettingsLink { Label("Settings", systemImage: "gearshape") }
            Spacer()
            Button(role: .destructive) { NSApplication.shared.terminate(nil) } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func openMainWindow() {
        #if os(macOS)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        #endif
        openWindow(id: "main")
    }

    private func openDestination(_ destination: StoreGaugeDestination) {
        openMainWindow()
        model.navigationRequest = StoreGaugeNavigationRequest(destination: destination)
    }

    private func copySummary() {
        #if os(macOS)
        let summary = [
            "StoreGauge · last 7 days",
            "Downloads: \(Format.int(agg.total(agg.hasAny(.installs) ? .installs : .units, days: 7)))",
            "Proceeds: \(Format.currency(agg.total(.proceeds, days: 7), code: settings.displayCurrency))",
            "Reviews needing reply: \(untriaged.count)"
        ].joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        #endif
    }
}

struct MiniStat: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: symbol).font(.caption).foregroundStyle(tint)
            Text(value).font(.system(.callout, design: .rounded).weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.1)))
    }
}

struct MenuReviewRow: View {
    let review: Review
    let open: () -> Void
    let markRead: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let app = review.app { AppIconView(app: app, size: 26) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    StarsView(rating: review.rating, size: 9)
                    ReviewLocaleBadge(review: review)
                    Spacer()
                    Text(Format.relativeDate(review.createdDate)).font(.caption2).foregroundStyle(.tertiary)
                }
                Text(review.title.isEmpty ? review.body : review.title).font(.caption.weight(.medium)).lineLimit(1)
                Text(review.body).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Button(action: markRead) { Image(systemName: "checkmark.circle") }
                .buttonStyle(.borderless).help("Acknowledge")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .help("Open \(review.app?.name ?? "review")")
    }
}

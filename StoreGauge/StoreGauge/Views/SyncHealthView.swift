//
//  SyncHealthView.swift
//  StoreGauge
//
//  One place to understand data freshness, partial failures, and recovery.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct SyncHealthSettingsView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Account.sortIndex) private var accounts: [Account]

    private var failingCount: Int { accounts.filter { $0.lastSyncError != nil }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if accounts.isEmpty {
                EmptyStateView(
                    symbol: "heart.text.square",
                    title: "No sync activity yet",
                    message: "Add an account to see connection health and data freshness."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        summary
                        ForEach(accounts) { account in
                            SyncHealthAccountCard(account: account)
                        }
                    }
                    .padding(16)
                }
            }

            Divider()
            HStack {
                Button { DiagnosticLog.reveal() } label: {
                    Label("Reveal Log", systemImage: "doc.text.magnifyingglass")
                }
                Button { copyLogPath() } label: {
                    Label("Copy Log Path", systemImage: "doc.on.doc")
                }
                Spacer()
                if model.isSyncing {
                    ProgressView().controlSize(.small)
                    Text(model.syncActivity.isEmpty ? "Syncing…" : model.syncActivity)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Button { Task { await model.syncNow() } } label: {
                    Label("Sync All", systemImage: "arrow.clockwise")
                }
                .disabled(model.isSyncing)
            }
            .padding(12)
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            Image(systemName: failingCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(failingCount == 0 ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(failingCount == 0 ? "All connected accounts are healthy" :
                        "\(failingCount) \(failingCount == 1 ? "account needs" : "accounts need") attention")
                    .font(.headline)
                Text("Automatic retries handle temporary network and service failures. Use Full Refresh after changing permissions or report access.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func copyLogPath() {
        #if os(macOS)
        let path = DiagnosticLog.fileURL?.path ?? "~/Library/Logs/StoreGauge/StoreGauge.log"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        #endif
    }
}

private struct SyncHealthAccountCard: View {
    @Environment(AppModel.self) private var model
    @Bindable var account: Account

    private var hasCredential: Bool {
        Keychain.load(account: account.id.uuidString)?.isEmpty == false || account.isDemo
    }

    private var latestProductData: Date? {
        let metricDate = account.apps.flatMap(\.metrics).map(\.date).max()
        let reviewDate = account.apps.flatMap(\.reviews).map(\.createdDate).max()
        return [metricDate, reviewDate].compactMap { $0 }.max()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                header
                Divider()
                healthRows
                if let error = account.lastSyncError {
                    Label {
                        Text(error).textSelection(.enabled)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                }
                HStack {
                    Button("Retry") { Task { await model.syncAccount(account) } }
                        .buttonStyle(.borderedProminent)
                    Button("Full Refresh") { Task { await model.refreshAllData(for: account) } }
                        .help("Ignore StoreGauge’s per-source refresh intervals and fetch everything again")
                    Spacer()
                    if let duration = account.lastSyncDuration {
                        Text("Last run \(duration.formatted(.number.precision(.fractionLength(1))))s")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .disabled(model.isSyncing)
            }
            .padding(4)
        } label: {
            EmptyView()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            StorePlatformIcon(platform: account.platform, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(account.name).font(.headline)
                Text("\(account.platform.displayName) · \(account.apps.filter { !$0.isArchived }.count) active apps")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label(statusTitle, systemImage: statusSymbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
        }
    }

    private var healthRows: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
            healthRow("Credentials", hasCredential ? "Available in Keychain" : "Missing",
                      hasCredential ? .healthy : .error)
            healthRow("Last attempt", dateLabel(account.lastSyncAttemptAt),
                      account.lastSyncError == nil ? .healthy : .error)
            healthRow("Last complete sync", dateLabel(account.lastSyncedAt),
                      account.lastSyncedAt == nil ? .waiting : .healthy)
            healthRow("Newest local data", dateLabel(latestProductData),
                      latestProductData == nil ? .waiting : .healthy)

            if account.platform == .googlePlay {
                healthRow("Android vitals", dateLabel(account.lastGoogleVitalsSyncAt),
                          sourceState(account.lastGoogleVitalsSyncAt))
                if account.googleFinancialBucket?.isEmpty == false {
                    healthRow("Install statistics", dateLabel(account.lastGoogleStatisticsSyncAt),
                              sourceState(account.lastGoogleStatisticsSyncAt))
                    healthRow("Financial reports", dateLabel(account.lastGoogleFinancialSyncAt),
                              sourceState(account.lastGoogleFinancialSyncAt))
                } else {
                    healthRow("Play report bucket", "Not configured", .optional)
                }
            } else if account.vendorNumber?.isEmpty != false {
                healthRow("Sales and proceeds", "Vendor Number not configured", .optional)
            }
        }
    }

    private func healthRow(_ title: String, _ value: String, _ state: HealthState) -> some View {
        GridRow {
            Label(title, systemImage: state.symbol)
                .foregroundStyle(state.color)
                .gridColumnAlignment(.leading)
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .font(.caption)
    }

    private var statusTitle: String {
        if account.lastSyncError != nil { return "Needs attention" }
        if account.lastSyncedAt != nil { return "Healthy" }
        return "Not synced"
    }

    private var statusSymbol: String {
        if account.lastSyncError != nil { return "exclamationmark.triangle.fill" }
        if account.lastSyncedAt != nil { return "checkmark.circle.fill" }
        return "clock.fill"
    }

    private var statusColor: Color {
        if account.lastSyncError != nil { return .orange }
        if account.lastSyncedAt != nil { return .green }
        return .secondary
    }

    private func dateLabel(_ date: Date?) -> String {
        date.map { Format.relativeDate($0) } ?? "Never"
    }

    private func sourceState(_ date: Date?) -> HealthState {
        date == nil ? .waiting : .healthy
    }
}

private enum HealthState {
    case healthy, waiting, optional, error

    var symbol: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .waiting: "clock.fill"
        case .optional: "minus.circle"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .healthy: .green
        case .waiting: .secondary
        case .optional: .secondary.opacity(0.6)
        case .error: .orange
        }
    }
}

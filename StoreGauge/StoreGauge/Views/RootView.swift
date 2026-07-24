//
//  RootView.swift
//  StoreGauge
//
//  Main window: sidebar navigation + detail area.
//

import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case overview
    case reviews
    case income
    case subscriptions
    case app(UUID)
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query(sort: \TrackedApp.name) private var apps: [TrackedApp]
    @AppStorage("selectedSettingsSection") private var selectedSettingsSection = SettingsSection.accounts
    @State private var selection: SidebarItem? = .overview
    @State private var keyMonitor = KeyboardMonitor()
    @State private var showingAddAccount = false

    var body: some View {
        Group {
            if accounts.isEmpty {
                welcome
            } else {
                VStack(spacing: 0) {
                    NavigationSplitView {
                        sidebar
                            .navigationSplitViewColumnWidth(min: 240, ideal: 264, max: 320)
                    } detail: {
                        detail
                    }
                    StatusBar()
                }
            }
        }
        .overlay {
            if keyMonitor.showOverlay {
                ShortcutsOverlay(shortcuts: contextShortcuts).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: keyMonitor.showOverlay)
        .sheet(isPresented: $showingAddAccount) { AccountFormView(existing: nil) }
        .onAppear { keyMonitor.start() }
        .onChange(of: model.navigationRequest) { _, request in
            guard let request else { return }
            switch request.destination {
            case .overview: selection = .overview
            case .reviews: selection = .reviews
            case .app(let id): selection = .app(id)
            }
        }
    }

    private var contextShortcuts: [ShortcutHint] {
        var list: [ShortcutHint] = [
            .init(keys: "⌘R", action: "Sync now"),
            .init(keys: "⌘,", action: "Settings"),
        ]
        switch selection {
        case .reviews:
            list += [.init(keys: "⌘E", action: "Export reviews CSV"),
                     .init(keys: "⌘⇧A", action: "Acknowledge all"),
                     .init(keys: "⌘↩", action: "Send reply (in editor)")]
        case .income, .subscriptions:
            list.append(.init(keys: "⌘E", action: "Export CSV"))
        default:
            break
        }
        return list
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section {
                    Label("Overview", systemImage: "square.grid.2x2.fill")
                        .tag(SidebarItem.overview)
                    HStack {
                        Label("Reviews", systemImage: "star.bubble.fill")
                        Spacer()
                        if model.untriagedCount > 0 {
                            Text("\(model.untriagedCount)")
                                .font(.caption2.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(.red))
                        }
                    }
                    .tag(SidebarItem.reviews)
                    Label("Income", systemImage: "dollarsign.circle.fill")
                        .tag(SidebarItem.income)
                    Label("Subscriptions", systemImage: "arrow.triangle.2.circlepath")
                        .tag(SidebarItem.subscriptions)
                }

                ForEach(accountsWithApps, id: \.0.id) { account, accountApps in
                    Section(accounts.count > 1 ? "\(account.name) · \(account.platform.displayName)" : "Apps") {
                        ForEach(accountApps) { app in
                            AppSidebarRow(app: app)
                                .tag(SidebarItem.app(app.id))
                                .contextMenu {
                                    Button {
                                        setDashboardInclusion(app, included: !app.isSelected)
                                    } label: {
                                        Label(app.isSelected ? "Exclude from Dashboard" : "Include in Dashboard",
                                              systemImage: app.isSelected ? "eye.slash" : "eye")
                                    }
                                    Button {
                                        setPinned(app, pinned: !app.isPinned)
                                    } label: {
                                        Label(app.isPinned ? "Unpin" : "Pin to Top",
                                              systemImage: app.isPinned ? "pin.slash" : "pin")
                                    }
                                    Divider()
                                    Button("Sync This Account") {
                                        if let account = app.account { Task { await model.syncAccount(account) } }
                                    }
                                    Divider()
                                    Button {
                                        archive(app)
                                    } label: {
                                        Label("Archive App", systemImage: "archivebox")
                                    }
                                }
                        }
                    }
                }
            }
            Divider()
            HStack(spacing: 0) {
                Button { showSettings(.accounts) } label: {
                    Label("Accounts", systemImage: "person.2")
                        .frame(maxWidth: .infinity)
                }
                .help("Manage accounts")

                Divider().frame(height: 22)

                Button { showingAddAccount = true } label: {
                    Image(systemName: "plus")
                        .frame(width: 34)
                }
                .help("Add account")

                Divider().frame(height: 22)

                Button { showSettings(.general) } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 34)
                }
                .help("Settings")
            }
            .buttonStyle(.plain)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7).stroke(.separator.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var accountsWithApps: [(Account, [TrackedApp])] {
        accounts.map { account in
            (account, apps.filter { $0.account?.id == account.id && !$0.isArchived }.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            })
        }
    }

    private func setDashboardInclusion(_ app: TrackedApp, included: Bool) {
        app.isSelected = included
        try? model.context.save()
        model.recomputeBadges()
    }

    private func setPinned(_ app: TrackedApp, pinned: Bool) {
        app.isPinned = pinned
        try? model.context.save()
    }

    private func archive(_ app: TrackedApp) {
        app.isArchived = true
        app.isSelected = false
        app.isPinned = false
        try? model.context.save()
        if selection == .app(app.id) { selection = .overview }
        model.invalidateIncome()
        model.invalidateSubscriptions()
        model.recomputeBadges()
    }

    private func showSettings(_ section: SettingsSection) {
        selectedSettingsSection = section
        openSettings()
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        switch selection {
        case .overview, .none:
            OverviewView()
        case .reviews:
            ReviewsView(filterAppID: nil)
        case .income:
            IncomeView()
        case .subscriptions:
            SubscriptionsView()
        case .app(let id):
            if let app = apps.first(where: { $0.id == id && !$0.isArchived }) {
                AppDetailView(app: app)
                    .id(app.id)   // fresh view per app so on-demand loads (screenshots, builds) don't go stale
            } else {
                EmptyStateView(symbol: "app.dashed", title: "App not found")
            }
        }
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(spacing: 20) {
            StoreGaugeMark()
                .frame(width: 64, height: 64)
            Text("Welcome to StoreGauge").font(.largeTitle.bold())
            Text("Track reviews, releases and performance across App Store and Google Play — privately, on your Mac.")
                .font(.title3).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 460)
            Button { showingAddAccount = true } label: {
                Label("Add Account", systemImage: "key.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("Connect App Store Connect or Google Play Console.")
                .font(.callout).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Sidebar row

struct AppSidebarRow: View {
    @Bindable var app: TrackedApp
    private var unread: Int { app.reviews.filter { $0.needsAttention }.count }

    var body: some View {
        HStack(spacing: 9) {
            AppIconView(app: app, size: 26, showsStoreBadge: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.callout).lineLimit(1)
                if app.currentStateRaw != nil {
                    HStack(spacing: 4) {
                        Circle().fill(app.state.color).frame(width: 6, height: 6)
                        Text(app.state.label).font(.caption2).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if app.isPinned {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
            }
            if !app.isSelected {
                Image(systemName: "eye.slash").font(.caption2).foregroundStyle(.tertiary)
                    .help("Excluded from dashboard")
            }
            if unread > 0 {
                Text("\(unread)")
                    .font(.caption2.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(.red))
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Global status bar

struct StatusBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @AppStorage("selectedSettingsSection") private var selectedSettingsSection = SettingsSection.accounts

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                if model.isSyncing {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                    Text(model.syncActivity.isEmpty ? "Syncing…" : model.syncActivity)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .transition(.opacity)
                } else if model.incomeLoading {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                    Text("Loading income reports…").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else if let err = model.lastSyncError {
                    Button { showSyncHealth() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(err).lineLimit(1)
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Open Sync Health for retries, source freshness, and diagnostics")
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    Text(model.lastSyncedAt.map { "Up to date · updated \(Format.relativeDate($0))" } ?? "Ready")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    MCPStatusButton {
                        selectedSettingsSection = .integrations
                        openSettings()
                    }
                }
                if model.untriagedCount > 0 {
                    Label("\(model.untriagedCount) need reply", systemImage: "exclamationmark.bubble")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button { Task { await model.syncNow() } } label: {
                    Image(systemName: "arrow.clockwise").font(.caption)
                }
                .buttonStyle(.borderless).disabled(model.isSyncing).help("Sync now")
            }
            .padding(.horizontal, 12).frame(height: 26)
        }
        .background(.bar)
        .animation(.default, value: model.isSyncing)
    }

    private func showSyncHealth() {
        selectedSettingsSection = .syncHealth
        openSettings()
    }
}

private struct MCPStatusButton: View {
    @Environment(AppModel.self) private var model
    let action: () -> Void

    private var activities: [StoreGaugeMCPActivity] { StoreGaugeMCPStorage.loadActivities() }
    private var liveActivities: [StoreGaugeMCPActivity] { activities.filter(\.isLive) }
    private var activity: StoreGaugeMCPActivity? { activities.first }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle().fill(statusColor).frame(width: 6, height: 6)
                Text(statusText).lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(model.settings.mcpEnabled ? .secondary : .tertiary)
        }
        .buttonStyle(.plain)
        .help("Open MCP setup and activity")
    }

    private var statusColor: Color {
        guard model.settings.mcpEnabled else { return .secondary.opacity(0.45) }
        if !liveActivities.isEmpty { return .green }
        if activity?.state == .error { return .orange }
        return .blue
    }

    private var statusText: String {
        guard model.settings.mcpEnabled else { return "MCP off" }
        guard let activity = liveActivities.first else { return "MCP ready" }
        if liveActivities.count > 1 { return "MCP · \(liveActivities.count) agents connected" }
        if let detail = activity.lastActivity, let date = activity.lastActivityAt {
            return "MCP · \(detail) \(Format.relativeDate(date))"
        }
        return "MCP · agent connected"
    }
}

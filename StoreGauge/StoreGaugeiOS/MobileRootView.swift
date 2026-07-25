//
//  MobileRootView.swift
//  StoreGaugeMobile
//
//  Phone-sized navigation and screens backed by the same local StoreGauge data.
//

import Charts
import SwiftData
import SwiftUI
import UIKit

private enum MobileTab: Hashable {
    case overview
    case reviews
    case apps
    case settings
}

struct MobileRootView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedTab: MobileTab

    init() {
        #if DEBUG
        let initial: MobileTab = switch ProcessInfo.processInfo.environment["STOREGAUGE_MOBILE_TAB"] {
        case "reviews": .reviews
        case "apps": .apps
        case "settings": .settings
        default: .overview
        }
        #else
        let initial: MobileTab = .overview
        #endif
        _selectedTab = State(initialValue: initial)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Overview", systemImage: "square.grid.2x2.fill", value: .overview) {
                NavigationStack { MobileOverviewView() }
            }

            Tab("Reviews", systemImage: "star.bubble.fill", value: .reviews) {
                NavigationStack { MobileReviewsView() }
            }
            .badge(model.untriagedCount)

            Tab("Apps", systemImage: "square.stack.3d.up.fill", value: .apps) {
                NavigationStack { MobileAppsView() }
            }

            Tab("Settings", systemImage: "gearshape.fill", value: .settings) {
                NavigationStack { MobileSettingsView() }
            }
        }
        .tint(.blue)
        .onChange(of: model.navigationRequest) { _, request in
            guard let request else { return }
            switch request.destination {
            case .overview: selectedTab = .overview
            case .reviews: selectedTab = .reviews
            case .app: selectedTab = .apps
            }
        }
    }
}

// MARK: - Overview

private struct MobileOverviewView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query(sort: \TrackedApp.name) private var allApps: [TrackedApp]
    @Query(sort: \Review.createdDate, order: .reverse) private var reviews: [Review]
    @State private var showingAccount = false

    private var apps: [TrackedApp] {
        allApps.filter { $0.isSelected && !$0.isArchived }
    }

    private var aggregator: MetricsAggregator {
        MetricsAggregator(apps: apps, fx: model.fx, currency: model.settings.displayCurrency)
    }

    var body: some View {
        Group {
            if accounts.isEmpty {
                MobileWelcomeView(showingAccount: $showingAccount)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        syncHeader
                        metrics
                        downloadsChart
                        appStatus
                        recentFeedback
                    }
                    .padding()
                }
                .refreshable { await model.syncNow() }
            }
        }
        .background(Color.windowFill)
        .navigationTitle("StoreGauge")
        .toolbar {
            if !accounts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.syncNow() }
                    } label: {
                        if model.isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(model.isSyncing)
                    .accessibilityLabel("Sync now")
                }
            }
        }
        .sheet(isPresented: $showingAccount) {
            NavigationStack { MobileAccountForm() }
        }
    }

    private var syncHeader: some View {
        HStack(spacing: 12) {
            Image("StoreGaugeBrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.isSyncing ? model.syncActivity : "Your stores at a glance")
                    .font(.headline)
                    .lineLimit(1)
                if let error = model.lastSyncError {
                    Text(error).foregroundStyle(.red)
                } else if let date = model.lastSyncedAt ?? accounts.compactMap(\.lastSyncedAt).max() {
                    Text("Updated \(Format.relativeDate(date))")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Pull down to sync")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            Spacer()
        }
        .mobilePanel()
    }

    private var metrics: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ], spacing: 12) {
            MobileMetricCard(
                title: "Downloads",
                value: Format.compact(aggregator.downloadTotal(days: 30)),
                delta: aggregator.downloadDelta(days: 30),
                symbol: "arrow.down.circle.fill",
                color: .blue
            )
            MobileMetricCard(
                title: "Proceeds",
                value: Format.currency(
                    aggregator.total(.proceeds, days: 30),
                    code: model.settings.displayCurrency,
                    compact: true
                ),
                delta: aggregator.delta(.proceeds, days: 30),
                symbol: "banknote.fill",
                color: .green
            )
            MobileMetricCard(
                title: "Needs reply",
                value: Format.int(Double(model.untriagedCount)),
                delta: nil,
                symbol: "exclamationmark.bubble.fill",
                color: .orange
            )
            MobileMetricCard(
                title: "Tracked apps",
                value: "\(apps.count)",
                delta: nil,
                symbol: "square.stack.3d.up.fill",
                color: .purple
            )
        }
    }

    @ViewBuilder
    private var downloadsChart: some View {
        let series = aggregator.downloadSeries(days: 30)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                Text("Last 30 days").font(.caption).foregroundStyle(.secondary)
            }

            Chart(series) { point in
                AreaMark(
                    x: .value("Day", point.date),
                    y: .value("Downloads", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.35), .blue.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("Day", point.date),
                    y: .value("Downloads", point.value)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    AxisGridLine()
                }
            }
            .frame(height: 180)
        }
        .mobilePanel()
    }

    private var appStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App status").font(.headline)
            ForEach(apps.prefix(5)) { app in
                NavigationLink {
                    MobileAppDetailView(app: app)
                } label: {
                    MobileAppRow(app: app)
                }
                .buttonStyle(.plain)
                if app.id != apps.prefix(5).last?.id { Divider() }
            }
        }
        .mobilePanel()
    }

    private var recentFeedback: some View {
        let visible = reviews.filter { $0.app?.isSelected == true && $0.app?.isArchived == false }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent feedback").font(.headline)
                Spacer()
                NavigationLink("See all") { MobileReviewsView() }
                    .font(.caption.weight(.semibold))
            }

            if visible.isEmpty {
                Label("No reviews yet", systemImage: "star.bubble")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(visible.prefix(3)) { review in
                    NavigationLink {
                        MobileReviewDetailView(review: review)
                    } label: {
                        MobileReviewRow(review: review, showsApp: true)
                    }
                    .buttonStyle(.plain)
                    if review.id != visible.prefix(3).last?.id { Divider() }
                }
            }
        }
        .mobilePanel()
    }
}

private struct MobileWelcomeView: View {
    @Binding var showingAccount: Bool
    @Environment(AppModel.self) private var model
    @State private var addingDemo = false

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("StoreGauge")
            } icon: {
                Image("StoreGaugeBrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
            }
        } description: {
            Text("Connect App Store Connect or Google Play Console. Everything stays on this iPhone.")
        } actions: {
            VStack(spacing: 12) {
                Button("Connect an account") { showingAccount = true }
                    .buttonStyle(.borderedProminent)
                Button {
                    addDemo()
                } label: {
                    if addingDemo {
                        ProgressView()
                    } else {
                        Text("Explore with demo data")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(addingDemo)
            }
        }
    }

    private func addDemo() {
        addingDemo = true
        let account = Account(
            name: "Demo · App Store",
            issuerID: Account.demoMarker,
            keyID: "DEMO",
            vendorNumber: "DEMO",
            sortIndex: model.accounts().count
        )
        model.context.insert(account)
        try? model.context.save()
        Task {
            await model.syncAccount(account)
            addingDemo = false
        }
    }
}

private struct MobileMetricCard: View {
    let title: String
    let value: String
    let delta: Double?
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
                .contentTransition(.numericText())
            HStack(spacing: 4) {
                Text(title)
                if let delta {
                    Text(Format.percent(delta))
                        .foregroundStyle(delta >= 0 ? .green : .red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mobilePanel(padding: 14)
    }
}

// MARK: - Reviews

private enum MobileReviewFilter: String, CaseIterable, Identifiable {
    case needsReply = "Needs Reply"
    case all = "All"
    var id: String { rawValue }
}

struct MobileReviewsView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Review.createdDate, order: .reverse) private var reviews: [Review]
    @State private var filter: MobileReviewFilter = .needsReply

    private var visible: [Review] {
        reviews.filter {
            $0.app?.isSelected == true &&
            $0.app?.isArchived == false &&
            (filter == .all || $0.needsAttention)
        }
    }

    var body: some View {
        List {
            if visible.isEmpty {
                ContentUnavailableView(
                    filter == .needsReply ? "Inbox clear" : "No reviews",
                    systemImage: filter == .needsReply ? "checkmark.circle.fill" : "star.bubble",
                    description: Text(filter == .needsReply
                                      ? "There are no reviews waiting for a reply."
                                      : "Reviews appear after your first sync.")
                )
                .listRowSeparator(.hidden)
                .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                Section {
                    ForEach(visible) { review in
                        NavigationLink {
                            MobileReviewDetailView(review: review)
                        } label: {
                            MobileReviewRow(review: review, showsApp: true)
                        }
                        .swipeActions(edge: .trailing) {
                            if review.needsAttention {
                                Button {
                                    model.acknowledge([review])
                                } label: {
                                    Label("Acknowledge", systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await model.syncNow() }
        .navigationTitle("Reviews")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Review filter", selection: $filter) {
                    ForEach(MobileReviewFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }
        }
    }
}

private struct MobileReviewRow: View {
    let review: Review
    let showsApp: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                MobileRatingStars(rating: review.rating)
                Spacer()
                Text(Format.relativeDate(review.createdDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !review.title.isEmpty {
                Text(review.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            Text(review.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                if showsApp, let app = review.app {
                    Text(app.name)
                }
                MobileTerritoryLabel(code: review.territory)
                if review.triage != .needsReply {
                    Label(review.triage.label, systemImage: review.triage.symbol)
                        .foregroundStyle(review.triage.color)
                } else if !review.isRead {
                    Text("NEW").foregroundStyle(.blue).fontWeight(.bold)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct MobileReviewDetailView: View {
    @Environment(AppModel.self) private var model
    let review: Review
    @State private var reply = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private var limit: Int {
        review.app?.platform.reviewReplyCharacterLimit ?? 4_000
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        MobileRatingStars(rating: review.rating, font: .title3)
                        Spacer()
                        MobileTerritoryLabel(code: review.territory)
                        Text(Format.relativeDate(review.createdDate))
                            .foregroundStyle(.secondary)
                    }
                    if !review.title.isEmpty {
                        Text(review.title).font(.headline)
                    }
                    Text(review.body).textSelection(.enabled)
                    Text([review.reviewer, review.app?.name].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if let response = review.responseBody {
                Section("Your response") {
                    Text(response)
                    if let date = review.responseDate {
                        Text("Sent \(Format.relativeDate(date))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if review.needsAttention {
                Section("Reply") {
                    TextEditor(text: $reply)
                        .frame(minHeight: 130)
                    HStack {
                        Text("\(reply.count) / \(limit)")
                            .foregroundStyle(reply.count > limit ? .red : .secondary)
                        Spacer()
                        Button("Send") {
                            Task { await sendReply() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(reply.mobileTrimmed.isEmpty || reply.count > limit || isSending)
                    }
                    if isSending { ProgressView("Sending…") }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.caption)
                    }
                }

                Section {
                    Button("Acknowledge without replying") {
                        model.acknowledge([review])
                    }
                }
            }
        }
        .navigationTitle(review.app?.name ?? "Review")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.markRead([review]) }
    }

    private func sendReply() async {
        isSending = true
        errorMessage = nil
        do {
            try await model.reply(to: review, body: reply.mobileTrimmed + model.settings.signatureSuffix)
            reply = ""
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isSending = false
    }
}

private struct MobileRatingStars: View {
    let rating: Int
    var font: Font = .caption

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { position in
                Image(systemName: "star.fill")
                    .foregroundStyle(
                        position <= rating
                            ? rating.ratingColor
                            : Color.secondary.opacity(0.28)
                    )
            }
        }
        .font(font)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rating) out of 5 stars")
    }
}

private struct MobileTerritoryLabel: View {
    let code: String

    var body: some View {
        Text(code.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel(
                Locale.current.localizedString(forRegionCode: code.uppercased()) ?? code.uppercased()
            )
    }
}

// MARK: - Apps

struct MobileAppsView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \TrackedApp.name) private var apps: [TrackedApp]

    private var visible: [TrackedApp] {
        apps.filter { !$0.isArchived }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if visible.isEmpty {
                ContentUnavailableView(
                    "No apps yet",
                    systemImage: "square.stack.3d.up",
                    description: Text("Connect an account in Settings, then sync.")
                )
            } else {
                List {
                    ForEach(visible) { app in
                        NavigationLink {
                            MobileAppDetailView(app: app)
                        } label: {
                            MobileAppRow(app: app)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                app.isSelected.toggle()
                                try? model.context.save()
                                model.recomputeBadges()
                            } label: {
                                Label(app.isSelected ? "Exclude" : "Include",
                                      systemImage: app.isSelected ? "eye.slash" : "eye")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await model.syncNow() }
            }
        }
        .navigationTitle("Apps")
    }
}

private struct MobileAppRow: View {
    let app: TrackedApp

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: app.iconURLString.flatMap(URL.init(string:))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(app.platform.iconBackground.gradient)
                        .overlay {
                            Image(systemName: app.platform.symbol)
                                .foregroundStyle(.white)
                        }
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.headline).lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: app.state.symbol)
                    Text(app.state.label)
                    if let version = app.currentVersionString {
                        Text("· \(version)")
                    }
                }
                .font(.caption)
                .foregroundStyle(app.state.color)
            }
            Spacer()
            if !app.isSelected {
                Image(systemName: "eye.slash").foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct MobileAppDetailView: View {
    @Environment(AppModel.self) private var model
    let app: TrackedApp

    private var aggregator: MetricsAggregator {
        MetricsAggregator(apps: [app], fx: model.fx, currency: model.settings.displayCurrency)
    }

    private var feedback: [Review] {
        app.reviews.sorted { $0.createdDate > $1.createdDate }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                MobileAppRow(app: app).mobilePanel()

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ], spacing: 12) {
                    MobileMetricCard(
                        title: "30-day downloads",
                        value: Format.compact(aggregator.downloadTotal(days: 30)),
                        delta: aggregator.downloadDelta(days: 30),
                        symbol: "arrow.down.circle.fill",
                        color: .blue
                    )
                    MobileMetricCard(
                        title: "30-day proceeds",
                        value: Format.currency(
                            aggregator.total(.proceeds, days: 30),
                            code: model.settings.displayCurrency,
                            compact: true
                        ),
                        delta: aggregator.delta(.proceeds, days: 30),
                        symbol: "banknote.fill",
                        color: .green
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Downloads").font(.headline)
                    Chart(aggregator.downloadSeries(days: 30)) { point in
                        LineMark(
                            x: .value("Day", point.date),
                            y: .value("Downloads", point.value)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis(.hidden)
                    .frame(height: 170)
                }
                .mobilePanel()

                if app.platform == .appleAppStore && app.capabilities.contains(.metadata) {
                    NavigationLink {
                        MobileStoreListingView(app: app)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "text.badge.checkmark")
                                .font(.title2)
                                .foregroundStyle(.blue)
                                .frame(width: 36, height: 36)
                                .background(.blue.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Store listing")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("\(app.metadataSnapshots.count) locales · \(app.metadataChanges.count) recorded changes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .mobilePanel()
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Latest reviews").font(.headline)
                    if feedback.isEmpty {
                        Text("No reviews yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(feedback.prefix(5)) { review in
                            NavigationLink {
                                MobileReviewDetailView(review: review)
                            } label: {
                                MobileReviewRow(review: review, showsApp: false)
                            }
                            .buttonStyle(.plain)
                            if review.id != feedback.prefix(5).last?.id { Divider() }
                        }
                    }
                }
                .mobilePanel()
            }
            .padding()
        }
        .background(Color.windowFill)
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            if let account = app.account { await model.syncAccount(account) }
        }
    }
}

// MARK: - Store listing

private enum MobileMetadataFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case keywords = "Keywords"
    case screenshots = "Screenshots"

    var id: String { rawValue }
}

struct MobileStoreListingView: View {
    @Environment(AppModel.self) private var model
    let app: TrackedApp

    @State private var locale = ""
    @State private var filter: MobileMetadataFilter = .all
    @State private var screenshotGroups: [ScreenshotGroup] = []
    @State private var screenshotsLoading = false

    private var locales: [String] {
        Array(Set(app.metadataSnapshots.map(\.locale) + app.metadataChanges.map(\.locale))).sorted()
    }

    private var currentSnapshot: MetadataSnapshot? {
        app.metadataSnapshots.first { $0.locale == locale }
    }

    private var changes: [MetadataChange] {
        app.metadataChanges
            .filter { change in
                guard change.locale == locale else { return false }
                switch filter {
                case .all: return true
                case .keywords: return change.field == .keywords
                case .screenshots: return change.field == .screenshots
                }
            }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                Picker("Localization", selection: $locale) {
                    ForEach(locales, id: \.self) { Text($0).tag($0) }
                }
            }

            Section("Current keywords") {
                if let keywords = currentSnapshot?.keywords, !keywords.isEmpty {
                    Text(keywords)
                        .font(.callout)
                        .textSelection(.enabled)
                } else {
                    Text("No keywords for this localization.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Current screenshots") {
                if screenshotsLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading from App Store Connect…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                } else if screenshotGroups.isEmpty {
                    ContentUnavailableView(
                        "No screenshots",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("No screenshots were returned for \(locale).")
                    )
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    ForEach(screenshotGroups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.label)
                                .font(.subheadline.weight(.semibold))
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 10) {
                                    ForEach(group.shots) { shot in
                                        AsyncImage(url: URL(string: shot.url)) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image
                                                    .resizable()
                                                    .scaledToFit()
                                            case .failure:
                                                ContentUnavailableView(
                                                    "Unavailable",
                                                    systemImage: "photo.badge.exclamationmark"
                                                )
                                            default:
                                                ProgressView()
                                            }
                                        }
                                        .frame(width: 122, height: 216)
                                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .accessibilityLabel("\(group.label) App Store screenshot")
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section {
                Picker("Change filter", selection: $filter) {
                    ForEach(MobileMetadataFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

                if changes.isEmpty {
                    ContentUnavailableView(
                        "No recorded changes",
                        systemImage: "clock.badge",
                        description: Text("StoreGauge records listing edits when it syncs.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ForEach(changes, id: \.persistentModelID) { change in
                        MobileMetadataChangeRow(change: change)
                    }
                }
            } header: {
                Text("Change history")
            } footer: {
                Text("Keyword history is backfilled from previous App Store versions. Screenshot history begins after StoreGauge records its first local baseline.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Store listing")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if locale.isEmpty {
                locale = locales.contains("en-US") ? "en-US" : (locales.first ?? "en-US")
            }
        }
        .task(id: locale) {
            guard !locale.isEmpty else { return }
            screenshotsLoading = true
            screenshotGroups = await model.screenshots(for: app, locale: locale)
            screenshotsLoading = false
        }
        .refreshable {
            if let account = app.account {
                await model.syncAccount(account)
                screenshotGroups = await model.screenshots(for: app, locale: locale)
            }
        }
    }
}

private struct MobileMetadataChangeRow: View {
    let change: MetadataChange

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: change.field.symbol)
                    .foregroundStyle(.tint)
                    .frame(width: 20)
                Text(change.field.label)
                    .font(.subheadline.weight(.semibold))
                if let version = change.versionString {
                    Text("v\(version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Format.relativeDate(change.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if change.field == .screenshots {
                Label(
                    "\(screenshotCount(change.oldValue)) → \(screenshotCount(change.newValue)) screenshots",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            } else {
                if let oldValue = change.oldValue, !oldValue.isEmpty {
                    metadataValue(oldValue, title: "Before", color: .red)
                }
                if let newValue = change.newValue, !newValue.isEmpty {
                    metadataValue(newValue, title: "After", color: .green)
                } else {
                    Label("Removed", systemImage: "minus.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 5)
    }

    private func metadataValue(_ value: String, title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.caption)
                .lineLimit(5)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func screenshotCount(_ fingerprint: String?) -> String {
        fingerprint?.split(separator: "#").first.map(String.init) ?? "0"
    }
}

// MARK: - Settings

struct MobileSettingsView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @State private var showingAccount = false
    @State private var accountToEdit: Account?
    @State private var accountToDelete: Account?

    var body: some View {
        Form {
            Section("Accounts") {
                ForEach(accounts) { account in
                    Button {
                        accountToEdit = account
                    } label: {
                        HStack {
                            Label(account.name, systemImage: account.platform.symbol)
                                .foregroundStyle(.primary)
                            Spacer()
                            if account.isDemo {
                                Text("Demo").foregroundStyle(.secondary)
                            } else if account.lastSyncError != nil {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions(allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            accountToDelete = account
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                Button {
                    showingAccount = true
                } label: {
                    Label("Connect account", systemImage: "plus.circle.fill")
                }
            }

            Section("Display") {
                Picker("Appearance", selection: settingBinding(\.appearance)) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Label(appearance.label, systemImage: appearance.symbol)
                            .tag(appearance)
                    }
                }
                Picker("Currency", selection: settingBinding(\.displayCurrency)) {
                    ForEach(["USD", "EUR", "GBP", "JPY", "CAD", "AUD"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                Picker("While app is open", selection: settingBinding(\.pollIntervalMinutes)) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                }
                .onChange(of: model.settings.pollIntervalMinutes) {
                    model.restartPoller()
                }
            }

            Section("Notifications") {
                Toggle("Store activity notifications", isOn: Binding(
                    get: { model.settings.notificationsEnabled },
                    set: { enabled in
                        if enabled {
                            Task {
                                let allowed = await model.notifier.requestAuthorization()
                                model.settings.notificationsEnabled = allowed
                                MobileBackgroundRefresh.updateSchedule(
                                    enabled: allowed && accounts.contains { !$0.isDemo }
                                )
                            }
                        } else {
                            model.settings.notificationsEnabled = false
                            MobileBackgroundRefresh.cancel()
                        }
                    }
                ))
                LabeledContent("System permission", value: model.notifier.authorizationLabel)
                    .foregroundStyle(.secondary)
                LabeledContent(
                    "Background App Refresh",
                    value: MobileBackgroundRefresh.availabilityLabel
                )
                .foregroundStyle(.secondary)

                if let lastCheck = MobileBackgroundRefresh.lastCompletedAt {
                    LabeledContent(
                        "Last background check",
                        value: lastCheck.formatted(date: .abbreviated, time: .shortened)
                    )
                    .foregroundStyle(.secondary)
                }

                Toggle("Performance alerts", isOn: settingBinding(\.anomalyAlertsEnabled))
                    .disabled(!model.settings.notificationsEnabled)

                if model.notifier.isAuthorized {
                    Button {
                        model.notifier.notify(
                            title: "StoreGauge notifications work",
                            body: "You’ll receive alerts when a sync finds new reviews, status changes, or listing edits.",
                            id: "storegauge-notification-test"
                        )
                    } label: {
                        Label("Send test notification", systemImage: "bell.badge")
                    }
                }
            }
            .listSectionSpacing(.compact)

            Section {
                Text("StoreGauge asks iOS to check reviews and release status no earlier than hourly. iOS chooses the actual time, and may delay checks when the app is rarely used, Background App Refresh is off, or Low Power Mode is enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Local by design") {
                Label(
                    "Store data stays in SwiftData on this iPhone. API keys stay in Keychain and are sent only to Apple or Google when StoreGauge syncs.",
                    systemImage: "lock.shield.fill"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                Link(
                    destination: URL(string: "https://phil9l.github.io/storegauge/privacy/")!
                ) {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                }
            }

            if let error = model.lastSyncError {
                Section("Last sync error") {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingAccount) {
            NavigationStack { MobileAccountForm() }
        }
        .sheet(item: $accountToEdit) { account in
            NavigationStack { MobileAccountForm(existing: account) }
        }
        .alert(
            "Delete account?",
            isPresented: Binding(
                get: { accountToDelete != nil },
                set: { if !$0 { accountToDelete = nil } }
            ),
            presenting: accountToDelete
        ) { account in
            Button("Delete Account", role: .destructive) {
                delete(account)
                accountToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                accountToDelete = nil
            }
        } message: { account in
            Text("Delete \(account.name) and all of its locally stored data from this iPhone?")
        }
    }

    private func settingBinding<Value>(_ keyPath: ReferenceWritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { model.settings[keyPath: keyPath] = $0 }
        )
    }

    private func delete(_ account: Account) {
        Keychain.delete(account: account.id.uuidString)
        model.context.delete(account)
        try? model.context.save()
        model.refreshSyncStatus()
        model.invalidateIncome()
        model.invalidateSubscriptions()
        model.recomputeBadges()
    }
}

extension String {
    fileprivate var mobileTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct MobilePanelModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .shadow(color: .black.opacity(0.045), radius: 12, y: 5)
    }
}

private extension View {
    func mobilePanel(padding: CGFloat = 16) -> some View {
        modifier(MobilePanelModifier(padding: padding))
    }
}

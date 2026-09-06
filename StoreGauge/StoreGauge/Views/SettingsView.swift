//
//  SettingsView.swift
//  StoreGauge
//
//  Preferences window: accounts, general, notifications, about.
//

import SwiftUI
import SwiftData
import Translation
#if os(macOS)
import AppKit
#endif

enum SettingsSection: String {
    case accounts
    case syncHealth
    case archived
    case general
    case integrations
    case notifications
    case replies
    case about
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("selectedSettingsSection") private var selection = SettingsSection.accounts

    var body: some View {
        TabView(selection: $selection) {
            AccountsSettingsView()
                .tabItem { Label("Accounts", systemImage: "key.fill") }
                .tag(SettingsSection.accounts)
            SyncHealthSettingsView()
                .tabItem { Label("Sync Health", systemImage: "heart.text.square.fill") }
                .tag(SettingsSection.syncHealth)
            ArchivedAppsSettingsView()
                .tabItem { Label("Archived", systemImage: "archivebox.fill") }
                .tag(SettingsSection.archived)
            GeneralSettingsView(settings: model.settings)
                .tabItem { Label("General", systemImage: "gearshape.fill") }
                .tag(SettingsSection.general)
            IntegrationsSettingsView(settings: model.settings)
                .tabItem { Label("Integrations", systemImage: "point.3.connected.trianglepath.dotted") }
                .tag(SettingsSection.integrations)
            NotificationsSettingsView(settings: model.settings)
                .tabItem { Label("Notifications", systemImage: "bell.fill") }
                .tag(SettingsSection.notifications)
            RepliesSettingsView(settings: model.settings)
                .tabItem { Label("Replies", systemImage: "arrowshape.turn.up.left.fill") }
                .tag(SettingsSection.replies)
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle.fill") }
                .tag(SettingsSection.about)
        }
    }
}

// MARK: - Accounts

struct AccountsSettingsView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @State private var editing: Account?
    @State private var showingAdd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if accounts.isEmpty {
                EmptyStateView(symbol: "key.horizontal.fill",
                               title: "No accounts yet",
                               message: "Connect App Store Connect or Google Play Console to start tracking your apps.",
                               actionTitle: "Add Account") { showingAdd = true }
            } else {
                List {
                    ForEach(accounts) { account in
                        AccountRow(account: account)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = account }
                            .contextMenu {
                                Button("Edit…") { editing = account }
                                Button("Sync This Account") { Task { await model.syncAccount(account) } }
                                Divider()
                                Button("Remove", role: .destructive) { remove(account) }
                            }
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                Button { showingAdd = true } label: { Label("Add Account", systemImage: "plus") }
                Spacer()
                if model.isSyncing { ProgressView().controlSize(.small); Text(model.syncActivity).font(.caption).foregroundStyle(.secondary) }
                Button { Task { await model.syncNow() } } label: { Label("Sync All", systemImage: "arrow.clockwise") }
                    .disabled(model.isSyncing || accounts.isEmpty)
            }
            .padding(12)
        }
        .sheet(isPresented: $showingAdd) { AccountFormView(existing: nil) }
        .sheet(item: $editing) { AccountFormView(existing: $0) }
    }

    private func remove(_ account: Account) {
        Keychain.delete(account: account.id.uuidString)
        model.context.delete(account)
        try? model.context.save()
        model.recomputeBadges()
    }
}

struct AccountRow: View {
    let account: Account
    var body: some View {
        HStack(spacing: 12) {
            StorePlatformIcon(platform: account.platform, size: 30)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(.body.weight(.medium))
                Text(accountSummary)
                    .font(.caption).foregroundStyle(.secondary)
                if let err = account.lastSyncError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange).lineLimit(2)
                } else if let last = account.lastSyncedAt {
                    Text("Synced \(Format.relativeDate(last))").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if account.vendorNumber?.isEmpty == false {
                Image(systemName: "dollarsign.circle.fill").foregroundStyle(.green).help("Income enabled")
            } else if account.googleFinancialBucket?.isEmpty == false {
                Image(systemName: "chart.bar.doc.horizontal.fill").foregroundStyle(.green).help("Play reports enabled")
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var accountSummary: String {
        let activeCount = account.apps.filter { !$0.isArchived }.count
        let archivedCount = account.apps.count - activeCount
        let appCount = "\(activeCount) apps" + (archivedCount > 0 ? " · \(archivedCount) archived" : "")
        switch account.platform {
        case .appleAppStore:
            return "App Store Connect · Key \(account.keyID) · \(appCount)"
        case .googlePlay:
            let project = account.externalAccountID.map { " · \($0)" } ?? ""
            return "Google Play Console\(project) · \(appCount)"
        }
    }
}

// MARK: - Archived apps

struct ArchivedAppsSettingsView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \TrackedApp.name) private var apps: [TrackedApp]

    private var archivedApps: [TrackedApp] { apps.filter(\.isArchived) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if archivedApps.isEmpty {
                EmptyStateView(
                    symbol: "archivebox",
                    title: "No archived apps",
                    message: "Apps you archive from the sidebar will appear here."
                )
            } else {
                List(archivedApps) { app in
                    HStack(spacing: 12) {
                        AppIconView(app: app, size: 32, showsStoreBadge: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).font(.body.weight(.medium))
                            Text(archivedAppSummary(app))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") { restore(app) }
                            .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button { restore(app) } label: {
                            Label("Restore App", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            Label("Archived apps are hidden throughout StoreGauge and are not synced. Their existing data is kept on this Mac.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
        }
    }

    private func archivedAppSummary(_ app: TrackedApp) -> String {
        let account = app.account?.name ?? "Unknown account"
        return "\(app.platform.displayName) · \(account)"
    }

    private func restore(_ app: TrackedApp) {
        app.isArchived = false
        app.isSelected = false
        try? model.context.save()
        model.invalidateIncome()
        model.invalidateSubscriptions()
        model.recomputeBadges()
    }
}

// MARK: - Add / edit account

private enum AccountSetupLinks {
    static let apiKeys = URL(string: "https://appstoreconnect.apple.com/access/integrations/api")!
    static let apiKeyGuide = URL(string: "https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api")!
    static let reports = URL(string: "https://appstoreconnect.apple.com/itc/payments_and_financial_reports#/")!
    static let vendorNumberGuide = URL(string: "https://developer.apple.com/help/app-store-connect/getting-paid/view-payments-and-proceeds/")!
    static let googleGettingStarted = URL(string: "https://developers.google.com/android-publisher/getting_started")!
    static let googleServiceAccounts = URL(string: "https://console.cloud.google.com/iam-admin/serviceaccounts")!
    static let googlePublisherAPI = URL(string: "https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com")!
    static let googleReportingAPI = URL(string: "https://console.cloud.google.com/apis/library/playdeveloperreporting.googleapis.com")!
    static let googleUsers = URL(string: "https://play.google.com/console/users-and-permissions")!
    static let googleFinancialGuide = URL(string: "https://support.google.com/googleplay/android-developer/answer/6135870?hl=en")!
}

struct AccountFormView: View {
    let existing: Account?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var platform: StorePlatform = .appleAppStore
    @State private var name = ""
    @State private var issuerID = ""
    @State private var keyID = ""
    @State private var p8Text = ""
    @State private var serviceAccountJSON = ""
    @State private var vendorNumber = ""
    @State private var googleFinancialBucket = ""

    enum TestState: Equatable { case idle, testing, success(Int), failure(String) }
    @State private var testState: TestState = .idle

    private var isEditing: Bool { existing != nil }
    private var canSave: Bool {
        guard !name.trimmed.isEmpty else { return false }
        if isDemoSubmission { return true }
        switch platform {
        case .appleAppStore:
            return AccountFieldValidation.isValidIssuerID(issuerID) &&
                AccountFieldValidation.isValidKeyID(keyID) &&
                AccountFieldValidation.isValidVendorNumber(vendorNumber) &&
                appleSecretReady
        case .googlePlay:
            return AccountFieldValidation.isValidGoogleReportBucket(googleFinancialBucket) &&
                googleSecretReady
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditing ? "Edit \(platform.accountDisplayName)" : "Add Account").font(.title2.bold())
                Spacer()
            }
            .padding([.horizontal, .top], 20).padding(.bottom, 12)

            Form {
                if !isEditing {
                    Section("Store") {
                        Picker("Connect", selection: $platform) {
                            ForEach(StorePlatform.allCases) { store in
                                Label(store.accountDisplayName, systemImage: store.symbol).tag(store)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                if platform == .appleAppStore { appleForm }
                else { googlePlayForm }

                readinessSection

                if !isEditing {
                    Section("Demo mode") {
                        Label("Enter test in every visible field to create a complete local demo. StoreGauge generates sample apps, reviews, and metrics without contacting Apple or Google.",
                              systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                testStatusView
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isEditing ? "Save" : "Test & Add") { Task { await save() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave || testState == .testing)
            }
            .padding(16)
        }
        .frame(width: 680, height: 760)
        .onAppear(perform: populate)
    }

    @ViewBuilder private var appleForm: some View {
        if !isEditing {
            Section("Get your credentials from Apple") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("You’ll need a Team API key from App Store Connect. This usually takes about two minutes.")
                        .font(.callout)
                    AccountSetupStep(number: 1, title: "Open Team Keys",
                                     detail: "Open Users and Access → Integrations → App Store Connect API → Team Keys. An Account Holder or Admin must generate the key.")
                    HStack(spacing: 16) {
                        Link(destination: AccountSetupLinks.apiKeys) { Label("Open API Keys", systemImage: "arrow.up.right.square") }
                        Link(destination: AccountSetupLinks.apiKeyGuide) { Label("Apple’s setup guide", systemImage: "book") }
                    }
                    .font(.caption).padding(.leading, 30)
                    AccountSetupStep(number: 2, title: "Generate a Team key",
                                     detail: "Create a dedicated key and choose the lowest role that covers the features you need. Use Admin only if you want access to every feature. Individual API keys can’t download Sales or Finance reports.")
                    AccountSetupStep(number: 3, title: "Copy the IDs and download the key",
                                     detail: "Copy the Issuer ID and Key ID, then download AuthKey_XXXXXXXXXX.p8. Apple lets you download it only once.")
                }
                .padding(.vertical, 4)
            }
        }

        Section("Identity") {
            accountNameField(prompt: "e.g. My Team")
            VStack(alignment: .leading, spacing: 4) {
                TextField("Issuer ID", text: $issuerID, prompt: Text("00000000-0000-0000-0000-000000000000"))
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                Text("Shown near the top of the Team Keys page.").font(.caption2).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                TextField("Key ID", text: $keyID, prompt: Text("10-character key ID"))
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                Text("Shown beside the generated key and included in its filename.").font(.caption2).foregroundStyle(.secondary)
            }
        }

        Section("Authentication") {
            credentialEditor(title: "Private Key (.p8)", text: $p8Text,
                             help: isEditing ? "Leave blank to keep the existing key."
                             : "Choose AuthKey_XXXXXXXXXX.p8 or paste it. StoreGauge keeps it in macOS Keychain.")
        }

        Section("Income (optional)") {
            TextField("Vendor Number", text: $vendorNumber, prompt: Text("Optional — enables income"))
                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            Text("Open App Store Connect Reports. The Vendor Number appears under your Legal Entity Name.")
                .font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Link(destination: AccountSetupLinks.reports) { Label("Open Reports", systemImage: "arrow.up.right.square") }
                Link(destination: AccountSetupLinks.vendorNumberGuide) { Label("Where to find it", systemImage: "questionmark.circle") }
            }
            .font(.caption)
        }
    }

    @ViewBuilder private var googlePlayForm: some View {
        if !isEditing {
            Section("Set up Google Play API access") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("StoreGauge uses a service account to discover apps and read releases, reviews, and Android vitals. The key stays in your Mac’s Keychain.")
                        .font(.callout)
                    AccountSetupStep(number: 1, title: "Enable both Google APIs",
                                     detail: "In one Google Cloud project, enable Google Play Android Developer API and Google Play Developer Reporting API.")
                    HStack(spacing: 16) {
                        Link(destination: AccountSetupLinks.googlePublisherAPI) { Label("Publisher API", systemImage: "arrow.up.right.square") }
                        Link(destination: AccountSetupLinks.googleReportingAPI) { Label("Reporting API", systemImage: "arrow.up.right.square") }
                    }
                    .font(.caption).padding(.leading, 30)
                    AccountSetupStep(number: 2, title: "Create and download a JSON key",
                                     detail: "Create a service account, open Keys → Add key → Create new key, choose JSON, and keep the downloaded file.")
                    Link(destination: AccountSetupLinks.googleServiceAccounts) {
                        Label("Open Service Accounts", systemImage: "arrow.up.right.square")
                    }
                    .font(.caption).padding(.leading, 30)
                    AccountSetupStep(number: 3, title: "Invite it to this Play developer account",
                                     detail: "Open your developer account’s Users and permissions page, then invite the service account’s client_email as a new user. Its URL looks like play.google.com/console/u/0/developers/<developer-id>/users-and-permissions. Grant Global View app information (read-only), access to the apps, and Reply to reviews.")
                    HStack(spacing: 16) {
                        Link(destination: AccountSetupLinks.googleUsers) { Label("Users and permissions", systemImage: "arrow.up.right.square") }
                        Link(destination: AccountSetupLinks.googleGettingStarted) { Label("Google’s setup guide", systemImage: "book") }
                    }
                    .font(.caption).padding(.leading, 30)
                }
                .padding(.vertical, 4)
            }
        }

        Section("Identity") { accountNameField(prompt: "e.g. Android Team") }

        Section("Authentication") {
            credentialEditor(title: "Service-account key (.json)", text: $serviceAccountJSON,
                             help: isEditing ? "Leave blank to keep the existing JSON key."
                             : "Choose the downloaded service-account JSON file or paste its complete contents.")
        }

        Section("Performance reports & income (optional)") {
            TextField("Play report bucket", text: $googleFinancialBucket,
                      prompt: Text("pubsite_prod_rev_0123456789"))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Text("In Play Console, open Download reports → Statistics and copy the private Cloud Storage bucket ID. Global “View app information” enables installs and updates; add Global “View financial data” for sales and earnings.")
                .font(.caption2).foregroundStyle(.secondary)
            Link(destination: AccountSetupLinks.googleFinancialGuide) {
                Label("Google’s report guide", systemImage: "book")
            }
            .font(.caption)
        }

        Section {
            Label("Install statistics and estimated sales normally lag 3–7 days. Finalized earnings come from the monthly earnings report and can arrive around the 5th of the following month.",
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var readinessSection: some View {
        Section("Ready to connect") {
            AccountReadinessRow(
                title: "Account label",
                detail: name.trimmed.isEmpty ? "Enter a name used inside StoreGauge." : name.trimmed,
                ready: !name.trimmed.isEmpty
            )

            switch platform {
            case .appleAppStore:
                AccountReadinessRow(
                    title: "Issuer ID",
                    detail: appleIssuerReady ? "Looks like an Apple Issuer ID." : "Copy the UUID from the Team Keys page.",
                    ready: appleIssuerReady
                )
                AccountReadinessRow(
                    title: "Key ID",
                    detail: appleKeyReady
                        ? AccountFieldValidation.normalizedKeyID(keyID)
                        : "Enter the 10-character ID beside your Team key.",
                    ready: appleKeyReady
                )
                AccountReadinessRow(
                    title: "Private key",
                    detail: appleSecretReady ? (p8Text.trimmed.isEmpty ? "Keeping the existing Keychain item." : "Valid P-256 private key.") :
                        "Choose the complete AuthKey .p8 file.",
                    ready: appleSecretReady
                )
                if !vendorNumber.trimmed.isEmpty {
                    AccountReadinessRow(
                        title: "Income reports",
                        detail: AccountFieldValidation.isValidVendorNumber(vendorNumber)
                            ? "Vendor Number included."
                            : "Vendor Number must contain digits only.",
                        ready: AccountFieldValidation.isValidVendorNumber(vendorNumber)
                    )
                }
            case .googlePlay:
                AccountReadinessRow(
                    title: "Service account",
                    detail: googleCredentials.map { "\($0.clientEmail) · \($0.projectID)" } ??
                        (serviceAccountJSON.trimmed.isEmpty && isEditing
                         ? "Keeping the existing Keychain item."
                         : "Choose the complete JSON key downloaded from Google Cloud."),
                    ready: googleSecretReady
                )
                AccountReadinessRow(
                    title: "Play Console access",
                    detail: "The service-account email must also be invited under Users and permissions.",
                    ready: googleSecretReady,
                    informational: true
                )
                if !googleFinancialBucket.trimmed.isEmpty {
                    AccountReadinessRow(
                        title: "Report bucket",
                        detail: googleBucketReady ? "Statistics and financial report access will be tested." :
                            "Use the pubsite_prod_rev_… bucket shown in Download reports.",
                        ready: googleBucketReady
                    )
                }
            }
        }
    }

    private var appleIssuerReady: Bool {
        isDemoSubmission || AccountFieldValidation.isValidIssuerID(issuerID)
    }

    private var appleKeyReady: Bool {
        isDemoSubmission || AccountFieldValidation.isValidKeyID(keyID)
    }

    private var appleSecretReady: Bool {
        if isEditing && p8Text.trimmed.isEmpty {
            return existing.flatMap { Keychain.load(account: $0.id.uuidString) }?.isEmpty == false
        }
        return (try? JWT.privateKey(from: p8Text)) != nil || isDemoSubmission
    }

    private var googleCredentials: GoogleServiceAccountCredentials? {
        let source: String
        if isEditing && serviceAccountJSON.trimmed.isEmpty {
            source = existing.flatMap { Keychain.load(account: $0.id.uuidString) } ?? ""
        } else {
            source = serviceAccountJSON
        }
        return try? GoogleServiceAccountCredentials.decode(json: source)
    }

    private var googleSecretReady: Bool {
        googleCredentials != nil || isDemoSubmission
    }

    private var googleBucketReady: Bool {
        AccountFieldValidation.isValidGoogleReportBucket(googleFinancialBucket)
    }

    private func accountNameField(prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Account name", text: $name, prompt: Text(prompt))
            Text("A label used only inside StoreGauge.").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func credentialEditor(title: String, text: Binding<String>, help: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.callout.weight(.medium))
                Spacer()
                #if os(macOS)
                Button("Choose File…") { chooseFile() }.controlSize(.small)
                #endif
            }
            TextEditor(text: text)
                .font(.system(size: 11, design: .monospaced))
                .frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            Text(help).font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var testStatusView: some View {
        switch testState {
        case .idle: EmptyView()
        case .testing: HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Testing…").foregroundStyle(.secondary) }.font(.caption)
        case .success(let n): Label("Connected · \(n) apps", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        case .failure(let m): Label(m, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.caption).lineLimit(2)
        }
    }

    private func populate() {
        guard let a = existing else { return }
        platform = a.platform
        if a.isDemo {
            name = "test"
            issuerID = platform == .appleAppStore ? "test" : ""
            keyID = platform == .appleAppStore ? "test" : ""
            p8Text = platform == .appleAppStore ? "test" : ""
            serviceAccountJSON = platform == .googlePlay ? "test" : ""
            vendorNumber = platform == .appleAppStore ? "test" : ""
            googleFinancialBucket = platform == .googlePlay ? "test" : ""
            return
        }
        name = a.name; issuerID = a.issuerID; keyID = a.keyID; vendorNumber = a.vendorNumber ?? ""
        googleFinancialBucket = a.googleFinancialBucket ?? ""
    }

    #if os(macOS)
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = platform == .appleAppStore ? "Choose your AuthKey .p8 file" : "Choose your service-account JSON key"
        if panel.runModal() == .OK, let url = panel.url {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                if platform == .googlePlay {
                    serviceAccountJSON = text
                } else {
                    p8Text = text
                }
                if platform == .appleAppStore, keyID.trimmed.isEmpty {
                    // AuthKey_XXXXXXXXXX.p8 -> extract key id
                    let base = url.deletingPathExtension().lastPathComponent
                    if base.hasPrefix("AuthKey_") { keyID = String(base.dropFirst("AuthKey_".count)) }
                }
            }
        }
    }
    #endif

    private func save() async {
        testState = .testing
        if isDemoSubmission {
            testState = .success(2)
            persistDemo()
            try? await Task.sleep(for: .milliseconds(400))
            dismiss()
            return
        }
        do {
            let count: Int
            let secret: String
            switch platform {
            case .appleAppStore:
                try AccountFieldValidation.validateApple(
                    issuerID: issuerID,
                    keyID: keyID,
                    vendorNumber: vendorNumber
                )
                secret = p8Text.trimmed.isEmpty ? (existing.flatMap { Keychain.load(account: $0.id.uuidString) } ?? "") : p8Text
                let credentials = ASCCredentials(
                    issuerID: issuerID.trimmed,
                    keyID: AccountFieldValidation.normalizedKeyID(keyID),
                    p8PEM: secret
                )
                count = try await ASCClient(credentials: credentials).verifyConnection()
            case .googlePlay:
                try AccountFieldValidation.validateGoogle(reportBucket: googleFinancialBucket)
                secret = serviceAccountJSON.trimmed.isEmpty ? (existing.flatMap { Keychain.load(account: $0.id.uuidString) } ?? "") : serviceAccountJSON
                let credentials = try GoogleServiceAccountCredentials.decode(json: secret)
                count = try await GooglePlayClient(credentials: credentials).verifyConnection()
                if !googleFinancialBucket.trimmed.isEmpty {
                    let storage = try GoogleCloudStorageClient(credentials: credentials,
                                                               bucket: googleFinancialBucket)
                    try await storage.verifyConnection()
                }
            }
            testState = .success(count)
            try persist(secret: secret)
            try? await Task.sleep(for: .milliseconds(400))
            dismiss()
        } catch {
            testState = .failure((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func persist(secret: String) throws {
        let ctx = model.context
        let account: Account
        if let existing {
            account = existing
            account.name = name.trimmed
        } else {
            account = Account(name: name.trimmed, issuerID: "", keyID: "",
                              sortIndex: model.accounts().count, platform: platform)
            ctx.insert(account)
        }
        account.platform = platform
        switch platform {
        case .appleAppStore:
            account.issuerID = issuerID.trimmed
            account.keyID = AccountFieldValidation.normalizedKeyID(keyID)
            account.vendorNumber = vendorNumber.trimmed.isEmpty ? nil : vendorNumber.trimmed
            account.externalAccountID = nil
            account.googleFinancialBucket = nil
            account.lastGoogleFinancialSyncAt = nil
            account.lastGoogleStatisticsSyncAt = nil
            account.lastGoogleVitalsSyncAt = nil
        case .googlePlay:
            if let credentials = try? GoogleServiceAccountCredentials.decode(json: secret) {
                account.externalAccountID = credentials.projectID
                account.keyID = credentials.privateKeyID
            }
            account.issuerID = ""
            account.vendorNumber = nil
            let normalized = try? GoogleCloudStorageClient.normalizeBucket(googleFinancialBucket)
            if account.googleFinancialBucket != normalized {
                account.lastGoogleFinancialSyncAt = nil
                account.lastGoogleStatisticsSyncAt = nil
            }
            account.googleFinancialBucket = normalized
        }
        let suppliedNewSecret = platform == .appleAppStore ? !p8Text.trimmed.isEmpty : !serviceAccountJSON.trimmed.isEmpty
        if suppliedNewSecret {
            try Keychain.save(secret, account: account.id.uuidString)
            if platform == .googlePlay { account.lastGoogleVitalsSyncAt = nil }
        }
        try ctx.save()
        Task { await model.syncAccount(account) }
    }

    private var isDemoSubmission: Bool {
        func isTest(_ value: String) -> Bool {
            value.trimmed.caseInsensitiveCompare("test") == .orderedSame
        }
        func isEmptyOrTest(_ value: String) -> Bool { value.trimmed.isEmpty || isTest(value) }

        guard isTest(name) else { return false }
        switch platform {
        case .appleAppStore:
            return isTest(issuerID) && isTest(keyID) && isTest(p8Text) && isEmptyOrTest(vendorNumber)
        case .googlePlay:
            return isTest(serviceAccountJSON) && isEmptyOrTest(googleFinancialBucket)
        }
    }

    private func persistDemo() {
        let ctx = model.context
        let account: Account
        if let existing {
            account = existing
        } else {
            account = Account(name: "StoreGauge Demo", issuerID: "", keyID: "",
                              sortIndex: model.accounts().count, platform: platform)
            ctx.insert(account)
        }
        account.name = platform == .appleAppStore ? "Demo · App Store" : "Demo · Google Play"
        account.platform = platform
        account.lastSyncError = nil
        account.lastGoogleFinancialSyncAt = nil
        account.lastGoogleStatisticsSyncAt = nil
        account.lastGoogleVitalsSyncAt = nil
        switch platform {
        case .appleAppStore:
            account.issuerID = Account.demoMarker
            account.keyID = "DEMO"
            account.vendorNumber = "DEMO"
            account.externalAccountID = nil
            account.googleFinancialBucket = nil
        case .googlePlay:
            account.issuerID = ""
            account.keyID = "DEMO"
            account.vendorNumber = nil
            account.externalAccountID = Account.demoMarker
            account.googleFinancialBucket = "DEMO"
        }
        Keychain.delete(account: account.id.uuidString)
        try? ctx.save()
        Task { await model.syncAccount(account) }
    }
}

private struct AccountSetupStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "\(number).circle.fill")
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AccountReadinessRow: View {
    let title: String
    let detail: String
    let ready: Bool
    var informational = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: informational ? "info.circle.fill" :
                    (ready ? "checkmark.circle.fill" : "circle"))
                .foregroundStyle(informational ? .blue : (ready ? .green : .secondary))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(AppModel.self) private var model
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage("shortcutHintWhileCommandHeld") private var shortcutHintWhileCommandHeld = true
    @State private var supportedTranslationLanguages: [Locale.Language] = []
    @State private var systemLanguageRevision = 0

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Label(appearance.label, systemImage: appearance.symbol)
                            .tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                Text("System follows the current macOS appearance automatically.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Section("Syncing") {
                Picker("Refresh every", selection: $settings.pollIntervalMinutes) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                    Text("4 hours").tag(240)
                }
                .onChange(of: settings.pollIntervalMinutes) { model.restartPoller() }
                Stepper("Sales history: \(settings.salesHistoryDays) days", value: $settings.salesHistoryDays, in: 7...365, step: 1)
                Toggle("Fetch usage analytics (downloads, sessions, active devices)", isOn: $settings.fetchAnalytics)
                Text("Analytics come from Apple's asynchronous reports and can take a day or two to populate after you first enable them.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("Money") {
                Picker("Display currency", selection: $settings.displayCurrency) {
                    ForEach(FXService.commonDisplayCurrencies, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Text("Exchange rates").foregroundStyle(.secondary)
                    Spacer()
                    Text(model.fx.usingLiveRates ? "Live (ECB)" : "Approximate").foregroundStyle(.secondary)
                }.font(.caption)
            }
            Section("Review Translation") {
                Picker("Translate reviews to", selection: $settings.reviewTranslationLanguage) {
                    Text("System Language (\(systemLanguageName))").tag("")
                    ForEach(translationLanguageChoices, id: \.minimalIdentifier) { language in
                        Text(languageName(language)).tag(language.minimalIdentifier)
                    }
                }
                Toggle("Automatically translate non-matching reviews", isOn: $settings.autoTranslateReviews)
                Text("Translations run on this Mac with Apple’s Translation framework. macOS may ask to download a language the first time it is used.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("Menu Bar & Dock") {
                Toggle("Show menu bar icon", isOn: $showMenuBarExtra)
                Toggle("Menu bar only (hide Dock icon)", isOn: $settings.menuBarOnly)
                    .onChange(of: settings.menuBarOnly) { model.applyActivationPolicy() }
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { model.updateLoginItem() }
            }
            Section("Keyboard") {
                Toggle("Hint at shortcuts while ⌘ is held", isOn: $shortcutHintWhileCommandHeld)
                Text("The full list opens with ⌘/ or the Shortcuts button in the status bar, whether or not the hint is on.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("Diagnostics") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Local connector log")
                        Text("Records operations and errors, never credentials, response bodies, or review text.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reveal Log") { DiagnosticLog.reveal() }
                }
            }
        }
        .formStyle(.grouped)
        .task { await loadTranslationLanguages() }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
            systemLanguageRevision &+= 1
        }
    }

    private var translationLanguageChoices: [Locale.Language] {
        var byIdentifier = Dictionary(supportedTranslationLanguages.map {
            ($0.minimalIdentifier, $0)
        }, uniquingKeysWith: { first, _ in first })
        if !settings.reviewTranslationLanguage.isEmpty {
            let selected = Locale.Language(identifier: settings.reviewTranslationLanguage)
            byIdentifier[selected.minimalIdentifier] = selected
        }
        return byIdentifier.values.sorted {
            languageName($0).localizedStandardCompare(languageName($1)) == .orderedAscending
        }
    }

    private var systemLanguageName: String {
        _ = systemLanguageRevision
        return languageName(settings.reviewTranslationTargetLanguage)
    }

    private func languageName(_ language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier)
            ?? language.minimalIdentifier
    }

    private func loadTranslationLanguages() async {
        supportedTranslationLanguages = await LanguageAvailability().supportedLanguages
    }
}

// MARK: - Integrations

private enum MCPAgent: String, CaseIterable, Identifiable {
    case codex
    case claudeCode
    case claudeDesktop
    case other

    var id: Self { self }
    var label: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        case .claudeDesktop: return "Claude Desktop"
        case .other: return "Other MCP client"
        }
    }
}

struct IntegrationsSettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(AppModel.self) private var model
    @State private var selectedAgent = MCPAgent.codex
    @State private var actionFeedback: String?
    @State private var feedbackIsError = false

    var body: some View {
        Form {
            Section("Model Context Protocol") {
                Toggle("Share StoreGauge data with local agents", isOn: $settings.mcpEnabled)
                    .onChange(of: settings.mcpEnabled) { _, _ in model.publishMCPData() }

                Label("The MCP helper reads a sanitized snapshot. It cannot access API keys, Keychain, or modify StoreGauge data.",
                      systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Data access") {
                Toggle("Include review text and reviewer names", isOn: $settings.mcpIncludeReviewText)
                    .onChange(of: settings.mcpIncludeReviewText) { _, _ in model.publishMCPData() }
                Toggle("Include proceeds, sales, and earnings", isOn: $settings.mcpIncludeFinancialData)
                    .onChange(of: settings.mcpIncludeFinancialData) { _, _ in model.publishMCPData() }
                Toggle("Only include apps selected for the dashboard", isOn: $settings.mcpSelectedAppsOnly)
                    .onChange(of: settings.mcpSelectedAppsOnly) { _, _ in model.publishMCPData() }
            }
            .disabled(!settings.mcpEnabled)

            Section("Agent setup") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Agent", selection: $selectedAgent) {
                        ForEach(MCPAgent.allCases) { agent in
                            Text(agent.label).tag(agent)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(setupInstructions)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if isDevelopmentCommandPath {
                        Label("Development build: this DerivedData path can change. Install StoreGauge in Applications before keeping this config.",
                              systemImage: "hammer.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    GroupBox {
                        ScrollView(.horizontal) {
                            Text(setupValue)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .scrollIndicators(.hidden)
                    }

                    HStack {
                        Button(copyButtonTitle) { copy(setupValue, feedback: copiedSetupMessage) }
                        if let configURL {
                            Button("Open Config") { openConfig(configURL) }
                        }
                        Button("Copy Executable Path") {
                            copy(mcpCommandPath, feedback: "Executable path copied")
                        }
                        Spacer()
                        Button("Refresh Data") { model.publishMCPData() }
                            .disabled(!settings.mcpEnabled)
                    }

                    if let actionFeedback {
                        Label(actionFeedback,
                              systemImage: feedbackIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(feedbackIsError ? .orange : .green)
                            .transition(.opacity)
                    }
                }
            }

            Section("Available to agents") {
                LabeledContent("Tools", value: "Portfolio, apps, metrics, reviews, releases, metadata, notes")
                LabeledContent("Resources", value: "Portfolio snapshot and app catalog")
                Text("All operations are read-only. Full exported history is queryable with filters and cursor pagination; archived apps are never exported.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Activity") {
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    MCPActivityDetails(enabled: settings.mcpEnabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var mcpCommandPath: String {
        Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("storegauge-mcp")
            .path ?? "/Applications/StoreGauge.app/Contents/MacOS/storegauge-mcp"
    }

    private var codexConfiguration: String {
        let escaped = mcpCommandPath.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "[mcp_servers.storegauge]\ncommand = \"\(escaped)\""
    }

    private var claudeConfiguration: String {
        let object: [String: Any] = [
            "mcpServers": ["storegauge": ["command": mcpCommandPath]]
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    private var genericConfiguration: String {
        let object: [String: Any] = [
            "command": mcpCommandPath,
            "args": [],
            "type": "stdio"
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    private var claudeCodeCommand: String {
        let escaped = mcpCommandPath.replacingOccurrences(of: "'", with: "'\\''")
        return "claude mcp add storegauge --scope user -- '\(escaped)'"
    }

    private var setupValue: String {
        switch selectedAgent {
        case .codex: codexConfiguration
        case .claudeCode: claudeCodeCommand
        case .claudeDesktop: claudeConfiguration
        case .other: genericConfiguration
        }
    }

    private var setupInstructions: String {
        switch selectedAgent {
        case .codex:
            "Add this block to ~/.codex/config.toml, then restart Codex."
        case .claudeCode:
            "Run this command once in Terminal. User scope makes StoreGauge available in every project; verify it with `claude mcp get storegauge`."
        case .claudeDesktop:
            "Merge this entry into Claude Desktop's mcpServers object, then fully quit and reopen Claude Desktop."
        case .other:
            "Configure a local stdio MCP server using this absolute executable path. No environment variables or arguments are required."
        }
    }

    private var copyButtonTitle: String {
        selectedAgent == .claudeCode ? "Copy Install Command" : "Copy Config"
    }

    private var copiedSetupMessage: String {
        selectedAgent == .claudeCode ? "Install command copied" : "Configuration copied"
    }

    private var isDevelopmentCommandPath: Bool {
        mcpCommandPath.contains("/DerivedData/")
    }

    private var configURL: URL? {
        switch selectedAgent {
        case .codex:
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/config.toml")
        case .claudeDesktop:
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        case .claudeCode, .other:
            nil
        }
    }

    private func copy(_ value: String, feedback: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(value, forType: .string) {
            showFeedback(feedback)
        } else {
            showFeedback("Could not access the clipboard", isError: true)
        }
        #endif
    }

    private func openConfig(_ url: URL) {
        #if os(macOS)
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app", isDirectory: true)
        let configuration = NSWorkspace.OpenConfiguration()
        showFeedback("Opening config in TextEdit…")
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: textEdit,
            configuration: configuration
        ) { _, error in
            Task { @MainActor in
                if let error {
                    NSWorkspace.shared.open(url.deletingLastPathComponent())
                    showFeedback("Could not open the file; opened its folder instead: \(error.localizedDescription)",
                                 isError: true)
                } else {
                    showFeedback("Config opened in TextEdit")
                }
            }
        }
        #endif
    }

    private func showFeedback(_ message: String, isError: Bool = false) {
        actionFeedback = message
        feedbackIsError = isError
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard actionFeedback == message else { return }
            actionFeedback = nil
        }
    }
}

private struct MCPActivityDetails: View {
    let enabled: Bool
    private var activities: [StoreGaugeMCPActivity] { StoreGaugeMCPStorage.loadActivities() }
    private var liveActivities: [StoreGaugeMCPActivity] { activities.filter(\.isLive) }
    private var activity: StoreGaugeMCPActivity? { activities.first }
    private var snapshot: StoreGaugeMCPSnapshot { StoreGaugeMCPStorage.loadSnapshot() }

    var body: some View {
        if !enabled {
            Label("Off · no data is shared", systemImage: "circle")
                .foregroundStyle(.secondary)
        } else {
            LabeledContent("Status") {
                Label(statusLabel, systemImage: !liveActivities.isEmpty ? "bolt.horizontal.circle.fill" : "checkmark.circle")
                    .foregroundStyle(!liveActivities.isEmpty ? .green : .secondary)
            }
            LabeledContent("Last export", value: snapshot.generatedAt == .distantPast
                           ? "Not exported yet" : Format.relativeDate(snapshot.generatedAt))
            LabeledContent("Exported apps", value: "\(snapshot.apps.count)")
            let clients = liveActivities.compactMap(\.clientName).filter { !$0.isEmpty }
            if !clients.isEmpty {
                LabeledContent(liveActivities.count == 1 ? "Agent" : "Agents",
                               value: clients.joined(separator: ", "))
            }
            if let detail = activity?.lastActivity, let date = activity?.lastActivityAt {
                LabeledContent("Last request", value: "\(detail) · \(Format.relativeDate(date))")
            }
            if let count = activity?.requestCount, count > 0 {
                LabeledContent("Requests this session", value: "\(count)")
            }
            if let error = activity?.errorMessage, !error.isEmpty {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var statusLabel: String {
        if liveActivities.count == 1 { return "Agent connected" }
        if liveActivities.count > 1 { return "\(liveActivities.count) agents connected" }
        if activity?.state == .error { return "Last connection failed" }
        return "Ready for an agent"
    }
}

// MARK: - Notifications

struct NotificationsSettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Toggle("Enable notifications", isOn: $settings.notificationsEnabled)
                    .onChange(of: settings.notificationsEnabled) { _, on in
                        if on { Task { await model.notifier.requestAuthorization() } }
                    }
            } footer: {
                Text("Get notified about status changes (e.g. In Review → Ready for Sale) and newly discovered apps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("New review alerts") {
                Picker("Notify me about", selection: $settings.globalAlertRule) {
                    ForEach(ReviewAlertRule.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Text("Default rule for all apps. Override per app from the app's detail page — e.g. all reviews for one app, only 1–2★ for another.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("Trend alerts") {
                Toggle("Alert on sharp week-over-week changes", isOn: $settings.anomalyAlertsEnabled)
                Stepper("Sensitivity: ±\(settings.anomalyThresholdPercent)%",
                        value: $settings.anomalyThresholdPercent, in: 10...100, step: 5)
                    .disabled(!settings.anomalyAlertsEnabled)
                Text("Notifies you when a selected app's downloads or proceeds move more than this much versus the previous week. Checked at most once a day.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Replies

struct RepliesSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var drafts: [ReplyTemplate] = []

    var body: some View {
        Form {
            Section("Signature") {
                TextField("Appended to new replies", text: $settings.replySignature,
                          prompt: Text("— The Acme Team"), axis: .vertical)
                    .lineLimit(1...3)
                Text("Automatically added to the bottom of new replies. Use {name} in templates to insert the reviewer's nickname.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("Templates") {
                ForEach($drafts) { $t in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Title", text: $t.title).font(.body.weight(.medium))
                            Button(role: .destructive) { drafts.removeAll { $0.id == t.id }; persist() } label: {
                                Image(systemName: "trash")
                            }.buttonStyle(.borderless)
                        }
                        TextField("Body", text: $t.body, axis: .vertical).lineLimit(2...5)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .onChange(of: drafts) { persist() }
                HStack {
                    Button { drafts.append(ReplyTemplate(title: "New template", body: "")); persist() } label: {
                        Label("Add Template", systemImage: "plus")
                    }
                    Spacer()
                    Button("Reset to defaults") {
                        drafts = ReplyTemplates.builtIn.map { ReplyTemplate(title: $0.title, body: $0.body) }
                        persist()
                    }.foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { drafts = settings.allTemplates }
    }

    private func persist() { settings.setTemplates(drafts) }
}

// MARK: - About

struct AboutView: View {
    private let repositoryURL = URL(string: "https://github.com/Phil9l/storegauge")!
    private let newIssueURL = URL(string: "https://github.com/Phil9l/storegauge/issues/new")!
    private let pullRequestsURL = URL(string: "https://github.com/Phil9l/storegauge/pulls")!
    private let privacyURL = URL(string: "https://phil9l.github.io/storegauge/privacy/")!

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 14) {
            StoreGaugeMark()
                .frame(width: 58, height: 58)
            Text("StoreGauge").font(.largeTitle.bold())
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("A source-available App Store Connect and Google Play dashboard. Track reviews, releases, income, and usage across your apps and accounts — privately, on your Mac.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Text("Your API keys never leave your Keychain. Data is stored locally with SwiftData.")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)

            Divider().frame(maxWidth: 420)

            Text("Found a problem or have an idea? Open an issue on GitHub. Contributions are welcome, too.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 8) {
                Link(destination: repositoryURL) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: newIssueURL) {
                    Label("New Issue", systemImage: "exclamationmark.bubble")
                }
                Link(destination: pullRequestsURL) {
                    Label("Pull Requests", systemImage: "arrow.triangle.branch")
                }
                Link(destination: privacyURL) {
                    Label("Privacy", systemImage: "hand.raised.fill")
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

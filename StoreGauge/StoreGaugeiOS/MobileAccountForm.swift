//
//  MobileAccountForm.swift
//  StoreGaugeMobile
//
//  iPhone account setup. Credentials are verified with the selected provider,
//  then stored in the local Keychain under the account's stable UUID.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MobileAccountForm: View {
    let existing: Account?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var platform: StorePlatform
    @State private var name: String
    @State private var issuerID: String
    @State private var keyID: String
    @State private var privateKey = ""
    @State private var serviceAccountJSON = ""
    @State private var vendorNumber: String
    @State private var reportBucket: String
    @State private var importingFile = false
    @State private var isSaving = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    init(existing: Account? = nil) {
        self.existing = existing
        _platform = State(initialValue: existing?.platform ?? .appleAppStore)
        _name = State(initialValue: existing?.name ?? "")
        _issuerID = State(initialValue: existing?.issuerID ?? "")
        _keyID = State(initialValue: existing?.keyID ?? "")
        _vendorNumber = State(initialValue: existing?.vendorNumber ?? "")
        _reportBucket = State(initialValue: existing?.googleFinancialBucket ?? "")
    }

    private var isEditing: Bool { existing != nil }

    private var hasStoredSecret: Bool {
        guard let existing else { return false }
        return Keychain.load(account: existing.id.uuidString)?.isEmpty == false
    }

    private var canSave: Bool {
        guard !name.mobileAccountTrimmed.isEmpty else { return false }
        switch platform {
        case .appleAppStore:
            return AccountFieldValidation.isValidIssuerID(issuerID) &&
                AccountFieldValidation.isValidKeyID(keyID) &&
                AccountFieldValidation.isValidVendorNumber(vendorNumber) &&
                (!privateKey.mobileAccountTrimmed.isEmpty || hasStoredSecret)
        case .googlePlay:
            return AccountFieldValidation.isValidGoogleReportBucket(reportBucket) &&
                (!serviceAccountJSON.mobileAccountTrimmed.isEmpty || hasStoredSecret)
        }
    }

    var body: some View {
        Form {
            if !isEditing {
                Section("Store") {
                    Picker("Store", selection: $platform) {
                        ForEach(StorePlatform.allCases) { store in
                            Label(store.accountDisplayName, systemImage: store.symbol).tag(store)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if existing?.isDemo == true {
                Section {
                    Label(
                        "This is a fully local demo account. Add a real account to sync your store.",
                        systemImage: "sparkles"
                    )
                    .foregroundStyle(.secondary)
                }
            } else {
                Section("Account") {
                    TextField("Account name", text: $name)
                        .textContentType(.organizationName)
                    Text("This label is only visible inside StoreGauge.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                switch platform {
                case .appleAppStore:
                    appleFields
                case .googlePlay:
                    googleFields
                }

                Section {
                    Label(
                        "The credential is kept in this iPhone's Keychain. Store data stays in the app's local database.",
                        systemImage: "lock.shield.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }

            if !isEditing {
                Section("Try StoreGauge first") {
                    Button {
                        addDemo()
                    } label: {
                        Label("Add local demo account", systemImage: "sparkles")
                    }
                    Text("Creates sample apps, metrics, and reviews without contacting either store.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isEditing {
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Account", systemImage: "trash")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } footer: {
                    Text("Deletes this account and all of its locally stored apps, metrics, reviews, and credentials.")
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Account" : "Connect Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            if existing?.isDemo != true {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Verify & Save") {
                        Task { await verifyAndSave() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
        .overlay {
            if isSaving {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Verifying access…").font(.callout.weight(.medium))
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
        .fileImporter(
            isPresented: $importingFile,
            allowedContentTypes: platform == .appleAppStore
                ? [.plainText, .data]
                : [.json, .plainText, .data],
            allowsMultipleSelection: false,
            onCompletion: importCredential
        )
        .confirmationDialog(
            "Delete \(existing?.name ?? "account")?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive, action: deleteAccount)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all data for the account from this iPhone. This cannot be undone.")
        }
    }

    private var appleFields: some View {
        Group {
            Section("App Store Connect API") {
                TextField("Issuer ID", text: $issuerID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                if !issuerID.mobileAccountTrimmed.isEmpty,
                   !AccountFieldValidation.isValidIssuerID(issuerID) {
                    validationLabel("Use the UUID shown on Apple’s Team Keys page.")
                }
                TextField("Key ID", text: $keyID)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                if !keyID.mobileAccountTrimmed.isEmpty,
                   !AccountFieldValidation.isValidKeyID(keyID) {
                    validationLabel("Key ID must contain exactly 10 letters or digits.")
                }
                Link(
                    "Open App Store Connect API keys",
                    destination: URL(string: "https://appstoreconnect.apple.com/access/integrations/api")!
                )
                Text("Create a dedicated key with the lowest role that covers the features you need. Use Admin only if you want access to every StoreGauge feature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Private key") {
                credentialEditor(
                    text: $privateKey,
                    prompt: hasStoredSecret
                        ? "Leave blank to keep the saved AuthKey"
                        : "Paste the contents of AuthKey_XXXXXXXXXX.p8"
                )
            }

            Section("Income · Optional") {
                TextField("Vendor number", text: $vendorNumber)
                    .keyboardType(.numberPad)
                if !AccountFieldValidation.isValidVendorNumber(vendorNumber) {
                    validationLabel("Vendor Number must contain digits only.")
                }
                Text("Required only for Sales and Trends income and subscription reports.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var googleFields: some View {
        Group {
            Section("Google service account") {
                credentialEditor(
                    text: $serviceAccountJSON,
                    prompt: hasStoredSecret
                        ? "Leave blank to keep the saved JSON key"
                        : "Paste the complete service-account JSON"
                )
                Link(
                    "Open Google Cloud service accounts",
                    destination: URL(string: "https://console.cloud.google.com/iam-admin/serviceaccounts")!
                )
            }

            Section("Reports · Optional") {
                TextField("pubsite_prod_rev_… bucket", text: $reportBucket)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                if !AccountFieldValidation.isValidGoogleReportBucket(reportBucket) {
                    validationLabel("Use pubsite_prod_rev_ followed by the numeric developer account ID.")
                }
                Text("Adds install statistics, estimated sales, and finalized earnings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func credentialEditor(text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: text)
                .font(.system(size: 12, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 120)
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(prompt)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                importingFile = true
            } label: {
                Label("Choose credential file", systemImage: "doc.badge.plus")
            }
        }
    }

    private func validationLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.red)
    }

    private func importCredential(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            if platform == .appleAppStore {
                privateKey = text
                if keyID.mobileAccountTrimmed.isEmpty {
                    let filename = url.deletingPathExtension().lastPathComponent
                    if filename.hasPrefix("AuthKey_") {
                        keyID = String(filename.dropFirst("AuthKey_".count))
                    }
                }
            } else {
                serviceAccountJSON = text
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verifyAndSave() async {
        isSaving = true
        errorMessage = nil

        do {
            let oldSecret = existing.flatMap { Keychain.load(account: $0.id.uuidString) } ?? ""
            let secret: String

            switch platform {
            case .appleAppStore:
                try AccountFieldValidation.validateApple(
                    issuerID: issuerID,
                    keyID: keyID,
                    vendorNumber: vendorNumber
                )
                secret = privateKey.mobileAccountTrimmed.isEmpty ? oldSecret : privateKey.mobileAccountTrimmed
                let credentials = ASCCredentials(
                    issuerID: issuerID.mobileAccountTrimmed,
                    keyID: AccountFieldValidation.normalizedKeyID(keyID),
                    p8PEM: secret
                )
                _ = try await ASCClient(credentials: credentials).verifyConnection()

            case .googlePlay:
                try AccountFieldValidation.validateGoogle(reportBucket: reportBucket)
                secret = serviceAccountJSON.mobileAccountTrimmed.isEmpty
                    ? oldSecret
                    : serviceAccountJSON.mobileAccountTrimmed
                let credentials = try GoogleServiceAccountCredentials.decode(json: secret)
                _ = try await GooglePlayClient(credentials: credentials).verifyConnection()
                if !reportBucket.mobileAccountTrimmed.isEmpty {
                    let storage = try GoogleCloudStorageClient(
                        credentials: credentials,
                        bucket: reportBucket.mobileAccountTrimmed
                    )
                    try await storage.verifyConnection()
                }
            }

            let account = try persist(secret: secret)
            isSaving = false
            dismiss()
            Task { await model.syncAccount(account, waitingForActiveSync: true) }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isSaving = false
        }
    }

    private func persist(secret: String) throws -> Account {
        let account: Account
        let isNewAccount: Bool
        if let existing {
            account = existing
            isNewAccount = false
        } else {
            account = Account(
                name: name.mobileAccountTrimmed,
                issuerID: "",
                keyID: "",
                sortIndex: model.accounts().count,
                platform: platform
            )
            isNewAccount = true
        }

        account.name = name.mobileAccountTrimmed
        account.platform = platform

        switch platform {
        case .appleAppStore:
            account.issuerID = issuerID.mobileAccountTrimmed
            account.keyID = AccountFieldValidation.normalizedKeyID(keyID)
            account.vendorNumber = vendorNumber.mobileAccountTrimmed.isEmpty
                ? nil
                : vendorNumber.mobileAccountTrimmed
            account.externalAccountID = nil
            account.googleFinancialBucket = nil

        case .googlePlay:
            if let credentials = try? GoogleServiceAccountCredentials.decode(json: secret) {
                account.externalAccountID = credentials.projectID
                account.keyID = credentials.privateKeyID
            }
            account.issuerID = ""
            account.vendorNumber = nil
            account.googleFinancialBucket = reportBucket.mobileAccountTrimmed.isEmpty
                ? nil
                : try GoogleCloudStorageClient.normalizeBucket(reportBucket)
            account.lastGoogleFinancialSyncAt = nil
            account.lastGoogleStatisticsSyncAt = nil
            account.lastGoogleVitalsSyncAt = nil
        }

        try Keychain.save(secret, account: account.id.uuidString)
        if isNewAccount {
            model.context.insert(account)
        }
        account.lastSyncError = nil
        account.lastSyncErrorAt = nil
        do {
            try model.context.save()
        } catch {
            if isNewAccount {
                Keychain.delete(account: account.id.uuidString)
                model.context.delete(account)
            }
            throw error
        }
        model.refreshSyncStatus()
        return account
    }

    private func deleteAccount() {
        guard let existing else { return }
        Keychain.delete(account: existing.id.uuidString)
        model.context.delete(existing)
        try? model.context.save()
        model.refreshSyncStatus()
        model.invalidateIncome()
        model.invalidateSubscriptions()
        model.recomputeBadges()
        dismiss()
    }

    private func addDemo() {
        let account = Account(
            name: "Demo · App Store",
            issuerID: Account.demoMarker,
            keyID: "DEMO",
            vendorNumber: "DEMO",
            sortIndex: model.accounts().count,
            platform: .appleAppStore
        )
        model.context.insert(account)
        try? model.context.save()
        dismiss()
        Task { await model.syncAccount(account) }
    }
}

extension String {
    fileprivate var mobileAccountTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

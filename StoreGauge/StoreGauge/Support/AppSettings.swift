//
//  AppSettings.swift
//  StoreGauge
//
//  User preferences, persisted in UserDefaults and observable by the UI + poller.
//

import Foundation

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    private let d = UserDefaults.standard

    var pollIntervalMinutes: Int { didSet { d.set(pollIntervalMinutes, forKey: K.pollInterval) } }
    var notificationsEnabled: Bool { didSet { d.set(notificationsEnabled, forKey: K.notifications) } }
    var displayCurrency: String { didSet { d.set(displayCurrency, forKey: K.currency) } }
    var appearance: AppAppearance { didSet { d.set(appearance.rawValue, forKey: K.appearance) } }
    var fetchAnalytics: Bool { didSet { d.set(fetchAnalytics, forKey: K.analytics) } }
    var menuBarOnly: Bool { didSet { d.set(menuBarOnly, forKey: K.menuBarOnly) } }
    var salesHistoryDays: Int { didSet { d.set(salesHistoryDays, forKey: K.salesDays) } }
    var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: K.launchAtLogin) } }

    /// MCP is entirely opt-in. Enabling it writes a sanitized snapshot into the
    /// shared App Group; the helper never opens SwiftData or Keychain itself.
    var mcpEnabled: Bool { didSet { d.set(mcpEnabled, forKey: K.mcpEnabled) } }
    var mcpIncludeReviewText: Bool { didSet { d.set(mcpIncludeReviewText, forKey: K.mcpReviewText) } }
    var mcpIncludeFinancialData: Bool { didSet { d.set(mcpIncludeFinancialData, forKey: K.mcpFinancials) } }
    var mcpSelectedAppsOnly: Bool { didSet { d.set(mcpSelectedAppsOnly, forKey: K.mcpSelectedOnly) } }

    /// Empty means follow the first language in the current system language list.
    var reviewTranslationLanguage: String {
        didSet { d.set(reviewTranslationLanguage, forKey: K.reviewTranslationLanguage) }
    }
    var autoTranslateReviews: Bool { didSet { d.set(autoTranslateReviews, forKey: K.autoTranslateReviews) } }

    /// Notify when week-over-week downloads/proceeds swing by more than the threshold.
    var anomalyAlertsEnabled: Bool { didSet { d.set(anomalyAlertsEnabled, forKey: K.anomalyAlerts) } }
    var anomalyThresholdPercent: Int { didSet { d.set(anomalyThresholdPercent, forKey: K.anomalyThreshold) } }

    /// Appended to new replies (e.g. "— The Acme Team").
    var replySignature: String { didSet { d.set(replySignature, forKey: K.signature) } }

    /// Default notification rule for new reviews (apps can override).
    var globalAlertRuleRaw: String { didSet { d.set(globalAlertRuleRaw, forKey: K.alertRule) } }
    var globalAlertRule: ReviewAlertRule {
        get { ReviewAlertRule(rawValue: globalAlertRuleRaw) ?? .all }
        set { globalAlertRuleRaw = newValue.rawValue }
    }

    /// User-defined reply templates (persisted as JSON).
    private(set) var customTemplates: [ReplyTemplate] = []

    init() {
        pollIntervalMinutes = (d.object(forKey: K.pollInterval) as? Int) ?? 30
        notificationsEnabled = (d.object(forKey: K.notifications) as? Bool) ?? true
        displayCurrency = (d.string(forKey: K.currency)) ?? "USD"
        appearance = d.string(forKey: K.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .system
        fetchAnalytics = (d.object(forKey: K.analytics) as? Bool) ?? false
        menuBarOnly = (d.object(forKey: K.menuBarOnly) as? Bool) ?? false
        salesHistoryDays = (d.object(forKey: K.salesDays) as? Int) ?? 45
        launchAtLogin = (d.object(forKey: K.launchAtLogin) as? Bool) ?? false
        mcpEnabled = (d.object(forKey: K.mcpEnabled) as? Bool) ?? false
        mcpIncludeReviewText = (d.object(forKey: K.mcpReviewText) as? Bool) ?? true
        mcpIncludeFinancialData = (d.object(forKey: K.mcpFinancials) as? Bool) ?? true
        mcpSelectedAppsOnly = (d.object(forKey: K.mcpSelectedOnly) as? Bool) ?? true
        reviewTranslationLanguage = d.string(forKey: K.reviewTranslationLanguage) ?? ""
        autoTranslateReviews = (d.object(forKey: K.autoTranslateReviews) as? Bool) ?? false
        anomalyAlertsEnabled = (d.object(forKey: K.anomalyAlerts) as? Bool) ?? true
        anomalyThresholdPercent = (d.object(forKey: K.anomalyThreshold) as? Int) ?? 40
        replySignature = d.string(forKey: K.signature) ?? ""
        globalAlertRuleRaw = d.string(forKey: K.alertRule) ?? ReviewAlertRule.all.rawValue
        if let data = d.data(forKey: K.templates),
           let decoded = try? JSONDecoder().decode([ReplyTemplate].self, from: data) {
            customTemplates = decoded
        }
    }

    // MARK: Templates

    var allTemplates: [ReplyTemplate] { customTemplates.isEmpty ? ReplyTemplates.builtIn : customTemplates }

    func saveTemplate(_ template: ReplyTemplate) {
        if let idx = customTemplates.firstIndex(where: { $0.id == template.id }) {
            customTemplates[idx] = template
        } else {
            customTemplates.append(template)
        }
        persistTemplates()
    }

    func deleteTemplate(_ template: ReplyTemplate) {
        customTemplates.removeAll { $0.id == template.id }
        persistTemplates()
    }

    /// Seeds the editable list with the built-ins so users can tweak them.
    func loadBuiltInTemplates() {
        customTemplates = ReplyTemplates.builtIn.map { ReplyTemplate(title: $0.title, body: $0.body) }
        persistTemplates()
    }

    func setTemplates(_ templates: [ReplyTemplate]) {
        customTemplates = templates
        persistTemplates()
    }

    private func persistTemplates() {
        if let data = try? JSONEncoder().encode(customTemplates) { d.set(data, forKey: K.templates) }
    }

    var signatureSuffix: String {
        replySignature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n\(replySignature)"
    }

    /// Resolve this on every access so "System Language" follows macOS changes
    /// instead of persisting the language that happened to be active at setup.
    var reviewTranslationTargetLanguage: Locale.Language {
        if !reviewTranslationLanguage.isEmpty {
            return Locale.Language(identifier: reviewTranslationLanguage)
        }
        if let preferred = Locale.preferredLanguages.first {
            return Locale.Language(identifier: preferred)
        }
        return Locale.current.language
    }

    var reviewTranslationTargetIdentifier: String {
        reviewTranslationTargetLanguage.minimalIdentifier
    }

    private enum K {
        static let pollInterval = "pollIntervalMinutes"
        static let notifications = "notificationsEnabled"
        static let currency = "displayCurrency"
        static let appearance = "appearance"
        static let analytics = "fetchAnalytics"
        static let menuBarOnly = "menuBarOnly"
        static let salesDays = "salesHistoryDays"
        static let launchAtLogin = "launchAtLogin"
        static let mcpEnabled = "mcpEnabled"
        static let mcpReviewText = "mcpIncludeReviewText"
        static let mcpFinancials = "mcpIncludeFinancialData"
        static let mcpSelectedOnly = "mcpSelectedAppsOnly"
        static let reviewTranslationLanguage = "reviewTranslationLanguage"
        static let autoTranslateReviews = "autoTranslateReviews"
        static let anomalyAlerts = "anomalyAlertsEnabled"
        static let anomalyThreshold = "anomalyThresholdPercent"
        static let signature = "replySignature"
        static let alertRule = "globalAlertRule"
        static let templates = "customTemplates"
    }
}

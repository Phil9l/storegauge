//
//  Components.swift
//  StoreGauge
//
//  Small reusable UI building blocks.
//

import SwiftUI
import SwiftData
import NaturalLanguage
import Translation
#if os(macOS)
import AppKit
#endif

// MARK: - App icon

struct AppIconView: View {
    let app: TrackedApp
    var size: CGFloat = 40
    var showsStoreBadge = false

    var body: some View {
        Group {
            if let s = app.iconURLString, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(.black.opacity(0.08), lineWidth: 0.5)
        )
        .overlay(alignment: .bottomTrailing) {
            if showsStoreBadge {
                StorePlatformIcon(platform: app.platform, size: max(12, size * 0.44))
                    .offset(x: 2, y: 2)
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [.accentColor.opacity(0.8), .accentColor.opacity(0.4)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var initials: String {
        let words = app.name.split(separator: " ").prefix(2)
        return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

// MARK: - Store identity

struct StorePlatformIcon: View {
    let platform: StorePlatform
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().fill(platform.iconBackground)
            Image(systemName: platform.symbol)
                .font(.system(size: size * 0.55, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.background, lineWidth: max(1, size * 0.1)))
        .accessibilityLabel(platform.displayName)
    }
}

struct StorePlatformLabel: View {
    let platform: StorePlatform

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: platform.symbol).font(.caption2.weight(.bold))
            Text(platform.displayName).font(.caption.weight(.medium))
        }
        .foregroundStyle(platform.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(platform.color.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

struct ReviewLocaleBadge: View {
    let review: Review

    var body: some View {
        if review.app?.platform == .googlePlay {
            Text(review.reviewerLanguage?.uppercased() ?? "—")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(.secondary.opacity(0.12)))
                .help("Reviewer language")
        } else {
            Text(flagEmoji(for: review.territory))
        }
    }
}

// MARK: - Review translation

/// Review title/body with an inline, on-device translation control. The cached
/// translation is only displayed when it matches the current target language.
struct ReviewTranslatedContent: View {
    @Bindable var review: Review
    var compact = false

    @Environment(AppModel.self) private var model
    @State private var sourceLanguage: Locale.Language?
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var canTranslate = false
    @State private var isTranslating = false
    @State private var showingTranslation = false
    @State private var translationError: String?
    @State private var systemLanguageRevision = 0
    @State private var didCopy = false

    private var targetLanguage: Locale.Language {
        _ = systemLanguageRevision
        return model.settings.reviewTranslationTargetLanguage
    }

    private var hasCachedTranslation: Bool {
        review.hasTranslation(to: targetLanguage)
    }

    private var usesTranslation: Bool {
        showingTranslation && hasCachedTranslation
    }

    private var visibleTitle: String {
        if usesTranslation, let title = review.translatedTitle, !title.isEmpty { return title }
        return review.title
    }

    private var visibleBody: String {
        if usesTranslation, let body = review.translatedBody, !body.isEmpty { return body }
        return review.body
    }

    private var taskIdentity: TranslationTaskIdentity {
        TranslationTaskIdentity(reviewID: review.id,
                                title: review.title,
                                body: review.body,
                                target: targetLanguage.minimalIdentifier,
                                automatic: model.settings.autoTranslateReviews,
                                systemRevision: systemLanguageRevision)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            if !visibleTitle.isEmpty {
                Text(visibleTitle)
                    .font(compact ? .caption.weight(.semibold) : .headline)
                    .textSelection(.enabled)
            }
            Text(visibleBody)
                .font(compact ? .caption : .callout)
                .foregroundStyle(compact
                    ? AnyShapeStyle(.secondary)
                    : AnyShapeStyle(.primary.opacity(0.9)))
                .textSelection(.enabled)
                .lineLimit(compact ? 3 : nil)
                .fixedSize(horizontal: false, vertical: true)

            translationControl
        }
        .task(id: taskIdentity) { await evaluateTranslation() }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
            systemLanguageRevision &+= 1
        }
        .translationTask(translationConfiguration) { session in
            await translate(using: session)
        }
    }

    private var translationControl: some View {
        HStack(spacing: 6) {
            if isTranslating {
                ProgressView().controlSize(.mini)
                Text("Translating…").font(.caption2).foregroundStyle(.secondary)
            } else if hasCachedTranslation {
                Button {
                    showingTranslation.toggle()
                } label: {
                    Label(usesTranslation ? "Show Original" : "Show Translation",
                          systemImage: usesTranslation ? "textformat" : "character.book.closed")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            } else if canTranslate {
                Button { requestTranslation() } label: {
                    Label("Translate to \(languageName(targetLanguage))", systemImage: "character.book.closed")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            if usesTranslation {
                Text("Translated to \(languageName(targetLanguage))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            if let translationError {
                Text(translationError)
                    .font(.caption2).foregroundStyle(.red)
                    .lineLimit(1)
                    .help(translationError)
                if canTranslate {
                    Button("Retry") { requestTranslation() }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            }

            Spacer(minLength: 0)
            Button { copyVisibleReview() } label: {
                Label(didCopy ? "Copied" : "Copy",
                      systemImage: didCopy ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help(usesTranslation ? "Copy translated review" : "Copy original review")
        }
    }

    private func copyVisibleReview() {
        #if os(macOS)
        let text = [visibleTitle, visibleBody]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopy = false
        }
        #endif
    }

    private func evaluateTranslation() async {
        translationConfiguration = nil
        translationError = nil
        isTranslating = false

        let target = targetLanguage
        let source = detectedSourceLanguage()
        sourceLanguage = source
        showingTranslation = hasCachedTranslation && model.settings.autoTranslateReviews

        if let source, source.isEquivalent(to: target) {
            canTranslate = false
            showingTranslation = false
            return
        }

        let availability = LanguageAvailability()
        let status: LanguageAvailability.Status?
        if let source {
            status = await availability.status(from: source, to: target)
        } else {
            status = try? await availability.status(for: sourceText, to: target)
        }
        guard !Task.isCancelled else { return }
        canTranslate = status.map { $0 != .unsupported } ?? false

        if canTranslate && !hasCachedTranslation && model.settings.autoTranslateReviews {
            requestTranslation()
        }
    }

    private func requestTranslation() {
        translationError = nil
        isTranslating = true
        let next = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
        if translationConfiguration == next {
            translationConfiguration?.invalidate()
        } else {
            translationConfiguration = next
        }
    }

    private func translate(using session: TranslationSession) async {
        do {
            let translatedBody = try await session.translate(review.body)
            // Translate the longer body first so a short title or brand name
            // cannot prevent an otherwise useful review translation.
            let translatedTitle = review.title.isEmpty
                ? nil
                : try? await session.translate(review.title)
            guard !Task.isCancelled,
                  translatedBody.targetLanguage.isEquivalent(to: targetLanguage) else { return }

            review.translatedTitle = translatedTitle?.targetText
            review.translatedBody = translatedBody.targetText
            review.translationSourceLanguage = translatedBody.sourceLanguage.minimalIdentifier
            review.translationTargetLanguage = translatedBody.targetLanguage.minimalIdentifier
            try? model.context.save()
            showingTranslation = true
            isTranslating = false
        } catch is CancellationError {
            isTranslating = false
        } catch {
            isTranslating = false
            translationError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var sourceText: String {
        [review.body, review.title].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func detectedSourceLanguage() -> Locale.Language? {
        if let hint = review.reviewerLanguage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !hint.isEmpty, hint.lowercased() != "und" {
            return Locale.Language(identifier: hint)
        }
        guard let language = NLLanguageRecognizer.dominantLanguage(for: sourceText),
              language != .undetermined else { return nil }
        return Locale.Language(identifier: language.rawValue)
    }

    private func languageName(_ language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier)
            ?? language.minimalIdentifier
    }

    private struct TranslationTaskIdentity: Hashable {
        let reviewID: String
        let title: String
        let body: String
        let target: String
        let automatic: Bool
        let systemRevision: Int
    }
}

// MARK: - Status badge

struct StatusBadge: View {
    let state: AppStoreState
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state.symbol).font(.caption2)
            if !compact { Text(state.label).font(.caption.weight(.medium)) }
        }
        .foregroundStyle(state.color)
        .padding(.horizontal, compact ? 5 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(Capsule().fill(state.color.opacity(0.14)))
    }
}

// MARK: - Stars

struct StarsView: View {
    let rating: Int
    var size: CGFloat = 12
    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(i <= rating ? rating.ratingColor : Color.secondary.opacity(0.4))
            }
        }
    }
}

// MARK: - Delta badge

struct DeltaBadge: View {
    let fraction: Double?     // e.g. +0.12
    var body: some View {
        if let f = fraction, f.isFinite, abs(f) > 0.0001 {
            let up = f >= 0
            HStack(spacing: 2) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right").font(.system(size: 9, weight: .bold))
                Text(Format.percent(f))
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(up ? .green : .red)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill((up ? Color.green : Color.red).opacity(0.14)))
        }
    }
}

// MARK: - KPI tile

struct KPITile: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var delta: Double? = nil
    let symbol: String
    let tint: Color
    var spark: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(tint.opacity(0.15)))
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                DeltaBadge(fraction: delta)
            }
            Text(value)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.6)
            if !spark.isEmpty {
                Sparkline(values: spark, tint: tint).frame(height: 26)
            } else if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Filter chip

struct FilterChip: View {
    let title: String
    let isOn: Bool
    var color: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle().fill(isOn ? color : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                Text(title).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(isOn ? color.opacity(0.14) : Color.secondary.opacity(0.08)))
            .overlay(Capsule().strokeBorder(isOn ? color.opacity(0.35) : .clear, lineWidth: 1))
            .foregroundStyle(isOn ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(.secondary.opacity(0.6))
            Text(title).font(.title3.weight(.semibold))
            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

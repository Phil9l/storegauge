//
//  ReviewsView.swift
//  StoreGauge
//
//  Review triage inbox: answer unanswered reviews, acknowledge others, and
//  browse your published answers — filtered by triage state.
//

import SwiftUI
import SwiftData

struct ReviewsView: View {
    /// When set, the inbox is locked to a single app (used from App Detail).
    let filterAppID: UUID?

    @Environment(AppModel.self) private var model
    @Query(sort: \Review.createdDate, order: .reverse) private var allReviews: [Review]
    @Query(sort: \TrackedApp.name) private var apps: [TrackedApp]

    @State private var triage: TriageStatus? = .needsReply   // nil == All
    @State private var appFilter: UUID?
    @State private var ratingFilter: Int?
    @State private var search = ""

    private var effectiveAppFilter: UUID? { filterAppID ?? appFilter }
    private var visibleApps: [TrackedApp] { apps.filter { !$0.isArchived } }
    private var availableReviews: [Review] { allReviews.filter { $0.app?.isArchived != true } }

    /// Reviews after app/rating/search (but before the triage tab).
    private var base: [Review] {
        availableReviews.filter { r in
            if let id = effectiveAppFilter, r.app?.id != id { return false }
            if let rating = ratingFilter, r.rating != rating { return false }
            if !search.isEmpty {
                let hay = "\(r.title) \(r.body) \(r.reviewer)".lowercased()
                if !hay.contains(search.lowercased()) { return false }
            }
            return true
        }
    }

    private var displayed: [Review] {
        let list = base.filter { triage == nil || $0.triage == triage }
        if triage == .needsReply {
            // Most urgent first: lowest rating, then newest.
            return list.sorted { ($0.rating, $1.createdDate) < ($1.rating, $0.createdDate) }
        }
        return list.sorted { $0.createdDate > $1.createdDate }
    }

    private var counts: (needs: Int, ack: Int, answered: Int) {
        base.reduce(into: (0, 0, 0)) { acc, r in
            switch r.triage {
            case .needsReply: acc.0 += 1
            case .acknowledged: acc.1 += 1
            case .answered: acc.2 += 1
            }
        }
    }
    private var responseRate: Double {
        base.isEmpty ? 0 : Double(counts.answered) / Double(base.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            summaryStrip
            Divider()
            if displayed.isEmpty {
                EmptyStateView(symbol: emptySymbol, title: emptyTitle, message: emptyMessage)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(displayed) { review in
                            ReviewCard(review: review, showApp: effectiveAppFilter == nil)
                        }
                    }
                    .padding(16)
                }
                .background(.windowFill)
            }
        }
        .navigationTitle("Reviews")
        .toolbar {
            if triage == .needsReply {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.acknowledge(displayed)
                    } label: { Label("Acknowledge All", systemImage: "checkmark.circle") }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(displayed.isEmpty)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    #if os(macOS)
                    ReviewExporter.exportPanel(displayed)
                    #endif
                } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(displayed.isEmpty)
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $triage) {
                Text("Needs Reply (\(counts.needs))").tag(TriageStatus?.some(.needsReply))
                Text("Acknowledged (\(counts.ack))").tag(TriageStatus?.some(.acknowledged))
                Text("Answered (\(counts.answered))").tag(TriageStatus?.some(.answered))
                Text("All (\(base.count))").tag(TriageStatus?.none)
            }
            .pickerStyle(.segmented).fixedSize()
            Spacer()
            if filterAppID == nil {
                Picker("", selection: $appFilter) {
                    Text("All Apps").tag(UUID?.none)
                    ForEach(visibleApps) { app in Text(app.name).tag(UUID?.some(app.id)) }
                }
                .frame(maxWidth: 160)
            }
            Picker("", selection: $ratingFilter) {
                Text("Any ★").tag(Int?.none)
                ForEach((1...5).reversed(), id: \.self) { Text("\($0) ★").tag(Int?.some($0)) }
            }
            .frame(maxWidth: 90)
            TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 180)
        }
        .padding(10)
    }

    private var summaryStrip: some View {
        HStack(spacing: 14) {
            Label("\(counts.answered) answered", systemImage: "arrowshape.turn.up.left.fill").foregroundStyle(.green)
            Label("\(counts.needs) need reply", systemImage: "exclamationmark.bubble.fill").foregroundStyle(.orange)
            Label("\(counts.ack) acknowledged", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                Text("Response rate").foregroundStyle(.secondary)
                Text(Format.percentPlain(responseRate)).fontWeight(.semibold)
                ProgressView(value: responseRate).frame(width: 60)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private var emptySymbol: String {
        switch triage {
        case .needsReply: return "checkmark.circle"
        case .answered: return "arrowshape.turn.up.left"
        default: return "star.bubble"
        }
    }
    private var emptyTitle: String {
        if availableReviews.isEmpty { return "No reviews yet" }
        switch triage {
        case .needsReply: return "All caught up"
        case .acknowledged: return "Nothing acknowledged"
        case .answered: return "No answers yet"
        case .none: return "No matching reviews"
        }
    }
    private var emptyMessage: String? {
        if availableReviews.isEmpty { return "Reviews will appear here after your first sync." }
        switch triage {
        case .needsReply: return "Every review here has been answered or acknowledged. Nice work!"
        case .answered: return "Replies you publish will be listed here."
        default: return nil
        }
    }
}

// MARK: - Review card

struct ReviewCard: View {
    @Bindable var review: Review
    let showApp: Bool
    @Environment(AppModel.self) private var model

    @State private var editing = false     // reply or edit-response editor open
    @State private var draft = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ReviewTranslatedContent(review: review)

            if let resp = review.responseBody, !resp.isEmpty, !editing {
                responseBlock(resp)
            }
            if editing { editor }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            footer
        }
        .card()
        .overlay(alignment: .leading) {
            if review.needsAttention {
                RoundedRectangle(cornerRadius: 2).fill(review.rating <= 2 ? .red : .orange)
                    .frame(width: 3).padding(.vertical, 10)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if showApp, let app = review.app {
                AppIconView(app: app, size: 24)
                Text(app.name).font(.subheadline.weight(.medium))
            }
            StarsView(rating: review.rating, size: 12)
            Spacer()
            TriageBadge(status: review.triage)
            ReviewLocaleBadge(review: review)
            Text(Format.relativeDate(review.createdDate)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func responseBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("Your reply", systemImage: "arrowshape.turn.up.left.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.green)
            Text(text).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.green.opacity(0.08)))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(review.hasResponse ? "Edit your reply" : "Reply to \(review.reviewer)")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(model.settings.allTemplates) { t in
                        Button(t.title) { draft = t.rendered(reviewer: review.reviewer) + model.settings.signatureSuffix }
                    }
                } label: { Label("Templates", systemImage: "text.badge.plus") }
                    .menuStyle(.borderlessButton).fixedSize().controlSize(.small)
            }
            TextEditor(text: $draft).font(.callout).frame(height: 74)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            HStack {
                Text("\(draft.count) / \(replyLimit) characters")
                    .font(.caption2)
                    .foregroundStyle(draft.count > replyLimit ? Color.red : Color.secondary)
                Spacer()
                Button("Cancel") { editing = false; error = nil }
                Button(working ? "Sending…" : "Publish") { Task { await submit() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(draft.trimmed.isEmpty || draft.count > replyLimit || working)
            }
        }
        .padding(.top, 4)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("by \(review.reviewer)").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if editing { EmptyView() }
            else if review.hasResponse {
                Button { startEdit() } label: { Label("Edit reply", systemImage: "pencil") }.controlSize(.small)
                if review.app?.capabilities.contains(.responseDeletion) == true {
                    Button(role: .destructive) { Task { await deleteReply() } } label: {
                        Label("Delete reply", systemImage: "trash")
                    }.controlSize(.small)
                }
            } else {
                Button { startReply() } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                    .controlSize(.small).buttonStyle(.borderedProminent)
                if review.isAcknowledged {
                    Button { model.acknowledge([review], false) } label: { Label("Un-acknowledge", systemImage: "arrow.uturn.backward") }.controlSize(.small)
                } else {
                    Button { model.acknowledge([review]) } label: { Label("Acknowledge", systemImage: "checkmark.circle") }.controlSize(.small)
                }
            }
        }
    }

    private func startReply() { draft = model.settings.signatureSuffix; editing = true; error = nil }
    private func startEdit() { draft = review.responseBody ?? ""; editing = true; error = nil }
    private var replyLimit: Int { review.app?.platform.reviewReplyCharacterLimit ?? 4_000 }

    private func submit() async {
        working = true; error = nil
        do {
            if review.hasResponse { try await model.editResponse(to: review, body: draft.trimmed) }
            else { try await model.reply(to: review, body: draft.trimmed) }
            editing = false
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        working = false
    }

    private func deleteReply() async {
        working = true; error = nil
        do { try await model.deleteResponse(from: review) }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        working = false
    }
}

struct TriageBadge: View {
    let status: TriageStatus
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: status.symbol).font(.system(size: 9))
            Text(status.label).font(.caption2.weight(.medium))
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(status.color.opacity(0.14)))
    }
}

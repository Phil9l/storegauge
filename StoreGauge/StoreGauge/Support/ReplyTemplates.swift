//
//  ReplyTemplates.swift
//  StoreGauge
//
//  Reply templates (built-in defaults + user-defined). `{name}` is replaced with
//  the reviewer nickname when inserted.
//

import Foundation

struct ReplyTemplate: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var body: String

    func rendered(reviewer: String) -> String {
        let name = reviewer.isEmpty ? "there" : reviewer
        return body.replacingOccurrences(of: "{name}", with: name)
    }
}

enum ReplyTemplates {
    static let builtIn: [ReplyTemplate] = [
        .init(title: "Thank you",
              body: "Thanks so much for the kind words, {name}! We're thrilled you're enjoying the app. 🙌"),
        .init(title: "Sorry — offer help",
              body: "Sorry to hear about the trouble, {name}. We'd love to help — please reach out to our support team so we can look into it and make it right."),
        .init(title: "Bug acknowledged",
              body: "Thanks for reporting this, {name}. We've reproduced the issue and a fix is on the way in an upcoming update."),
        .init(title: "Feature request",
              body: "Great suggestion, {name}! We've added it to our roadmap for a future update. Thank you for helping us improve."),
        .init(title: "Ask to re-rate",
              body: "Thank you for the feedback, {name}! The latest update should address this — if it helped, we'd really appreciate you updating your rating."),
    ]
}

/// When to fire a notification for a newly arrived review.
enum ReviewAlertRule: String, CaseIterable, Codable, Sendable {
    case off, all, threeOrLower, twoOrLower

    var label: String {
        switch self {
        case .off: return "No alerts"
        case .all: return "All new reviews"
        case .threeOrLower: return "3★ and below"
        case .twoOrLower: return "2★ and below"
        }
    }

    func allows(rating: Int) -> Bool {
        switch self {
        case .off: return false
        case .all: return true
        case .threeOrLower: return rating <= 3
        case .twoOrLower: return rating <= 2
        }
    }
}

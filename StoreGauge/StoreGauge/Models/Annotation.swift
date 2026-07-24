//
//  Annotation.swift
//  StoreGauge
//
//  User-authored annotations pinned to a date on the charts ("ran a promo",
//  "featured by Apple", "price change"). Scoped to one app, or global (app == nil).
//

import Foundation
import SwiftData

/// A colour-coded kind of annotation, so promos, bug fixes, releases etc. are
/// distinguishable at a glance on the charts. (Colours live in a SwiftUI extension.)
enum AnnotationCategory: String, CaseIterable, Codable, Sendable {
    case marketing
    case bugfix
    case release
    case experiment
    case note

    var label: String {
        switch self {
        case .marketing: "Marketing"
        case .bugfix: "Bug fix"
        case .release: "Release"
        case .experiment: "Experiment"
        case .note: "Note"
        }
    }

    /// SF Symbol drawn as the flag on the chart and in the list.
    var symbol: String {
        switch self {
        case .marketing: "megaphone.fill"
        case .bugfix: "ladybug.fill"
        case .release: "shippingbox.fill"
        case .experiment: "flask.fill"
        case .note: "flag.fill"
        }
    }
}

@Model
final class ChartAnnotation {
    @Attribute(.unique) var id: UUID
    var date: Date
    var note: String
    var createdAt: Date
    /// Stored raw so SwiftData can add the column with a default for existing rows.
    var categoryRaw: String = AnnotationCategory.note.rawValue
    var app: TrackedApp?

    var category: AnnotationCategory {
        get { AnnotationCategory(rawValue: categoryRaw) ?? .note }
        set { categoryRaw = newValue.rawValue }
    }

    init(date: Date, note: String, category: AnnotationCategory = .note, app: TrackedApp?) {
        self.id = UUID()
        self.date = date
        self.note = note
        self.createdAt = Date()
        self.categoryRaw = category.rawValue
        self.app = app
    }
}

//
//  Metadata.swift
//  StoreGauge
//
//  App-listing metadata snapshots + a change timeline ("blame") per locale.
//

import Foundation
import SwiftData

enum MetadataField: String, Codable, CaseIterable, Sendable {
    case name, subtitle, description, keywords, promotionalText, whatsNew, marketingURL, supportURL, screenshots

    var label: String {
        switch self {
        case .name: return "Name"
        case .subtitle: return "Subtitle"
        case .description: return "Description"
        case .keywords: return "Keywords"
        case .promotionalText: return "Promotional Text"
        case .whatsNew: return "What's New"
        case .marketingURL: return "Marketing URL"
        case .supportURL: return "Support URL"
        case .screenshots: return "Screenshots"
        }
    }

    var symbol: String {
        switch self {
        case .name: return "textformat"
        case .subtitle: return "text.alignleft"
        case .description: return "doc.text"
        case .keywords: return "tag"
        case .promotionalText: return "megaphone"
        case .whatsNew: return "sparkles"
        case .marketingURL, .supportURL: return "link"
        case .screenshots: return "photo.on.rectangle.angled"
        }
    }
}

/// Current metadata for one app + locale (updated in place each metadata sync).
@Model
final class MetadataSnapshot {
    @Attribute(.unique) var key: String        // "<local app identity>|metadata|<locale>"
    var appStoreID: String
    var locale: String
    var name: String?
    var subtitle: String?
    var localizedDescription: String?
    var keywords: String?
    var promotionalText: String?
    var whatsNew: String?
    var marketingURL: String?
    var supportURL: String?
    var screenshots: String?                   // fingerprint, e.g. "APP_IPHONE_67:5;..."
    var updatedAt: Date
    var app: TrackedApp?

    init(appStoreID: String, locale: String, app: TrackedApp?) {
        self.key = app.map { "\($0.storageIdentity)|metadata|\(locale)" } ?? "\(appStoreID)|metadata|\(locale)"
        self.appStoreID = appStoreID
        self.locale = locale
        self.updatedAt = Date()
        self.app = app
    }

    func value(for field: MetadataField) -> String? {
        switch field {
        case .name: return name
        case .subtitle: return subtitle
        case .description: return localizedDescription
        case .keywords: return keywords
        case .promotionalText: return promotionalText
        case .whatsNew: return whatsNew
        case .marketingURL: return marketingURL
        case .supportURL: return supportURL
        case .screenshots: return screenshots
        }
    }

    func set(_ newValue: String?, for field: MetadataField) {
        switch field {
        case .name: name = newValue
        case .subtitle: subtitle = newValue
        case .description: localizedDescription = newValue
        case .keywords: keywords = newValue
        case .promotionalText: promotionalText = newValue
        case .whatsNew: whatsNew = newValue
        case .marketingURL: marketingURL = newValue
        case .supportURL: supportURL = newValue
        case .screenshots: screenshots = newValue
        }
    }
}

/// One recorded change to a metadata field, for the timeline.
@Model
final class MetadataChange {
    var date: Date
    var locale: String
    var fieldRaw: String
    var oldValue: String?
    var newValue: String?
    var versionString: String?
    var app: TrackedApp?

    init(date: Date = Date(), locale: String, field: MetadataField, oldValue: String?,
         newValue: String?, versionString: String?, app: TrackedApp?) {
        self.date = date
        self.locale = locale
        self.fieldRaw = field.rawValue
        self.oldValue = oldValue
        self.newValue = newValue
        self.versionString = versionString
        self.app = app
    }

    var field: MetadataField { MetadataField(rawValue: fieldRaw) ?? .name }
}

//
//  Formatters.swift
//  StoreGauge
//
//  Shared date & number formatting helpers.
//

import Foundation

/// Canonical `yyyy-MM-dd` (UTC) day formatter used for metric keys.
enum DayFormatter {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func string(from date: Date) -> String { formatter.string(from: date) }
    static func date(from string: String) -> Date? { formatter.date(from: string) }
}

/// Parses App Store Connect ISO-8601 timestamps like `2025-07-23T05:19:27-07:00`.
enum APIDate {
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        return iso.date(from: string) ?? isoFractional.date(from: string)
    }
}

extension Date {
    /// Midnight (UTC) of the day containing this date.
    var startOfDayUTC: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.startOfDay(for: self)
    }

    static func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: Date()) ?? Date()
    }
}

enum Format {
    /// Compact, human number: 1_234 -> "1.2K", 2_500_000 -> "2.5M".
    static func compact(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        let abs = Swift.abs(value)
        switch abs {
        case 1_000_000...:
            f.maximumFractionDigits = 1
            return (f.string(from: NSNumber(value: value / 1_000_000)) ?? "0") + "M"
        case 1_000...:
            f.maximumFractionDigits = 1
            return (f.string(from: NSNumber(value: value / 1_000)) ?? "0") + "K"
        default:
            f.maximumFractionDigits = 0
            return f.string(from: NSNumber(value: value)) ?? "0"
        }
    }

    static func int(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "0"
    }

    /// Currency string in the given ISO code (e.g. "USD" -> "$1,234.56").
    static func currency(_ amount: Double, code: String, compact: Bool = false) -> String {
        if compact {
            let symbol = currencySymbol(code)
            return symbol + Format.compact(amount)
        }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        f.maximumFractionDigits = amount.rounded() == amount ? 0 : 2
        return f.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    static func currencySymbol(_ code: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        return f.currencySymbol ?? code
    }

    static func percentPlain(_ fraction: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: fraction)) ?? "0%"
    }

    static func percentRate(_ fraction: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: fraction)) ?? "0%"
    }

    static func percent(_ fraction: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.maximumFractionDigits = 1
        f.positivePrefix = f.plusSign
        return f.string(from: NSNumber(value: fraction)) ?? "0%"
    }

    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func relativeDate(_ date: Date) -> String {
        relative.localizedString(for: date, relativeTo: Date())
    }

    static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

/// Maps an App Store territory / country code to a flag emoji.
func flagEmoji(for territoryCode: String) -> String {
    // App Store uses 3-letter ISO territory codes; map common ones to 2-letter.
    let iso2 = territoryToISO2[territoryCode.uppercased()] ?? String(territoryCode.prefix(2)).uppercased()
    guard iso2.count == 2 else { return "🏳️" }
    let base: UInt32 = 127397
    var s = ""
    for scalar in iso2.unicodeScalars {
        if let flag = UnicodeScalar(base + scalar.value) { s.unicodeScalars.append(flag) }
    }
    return s.isEmpty ? "🏳️" : s
}

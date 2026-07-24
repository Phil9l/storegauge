//
//  SubscriptionReport.swift
//  StoreGauge
//
//  Parses Apple's daily SUBSCRIPTION report (a snapshot of active subscriptions
//  by app / subscription / price / country). Rows link to the parent app via
//  "App Apple ID" directly.
//

import Foundation

struct SubRow: Sendable {
    let appAppleID: String
    let subscriptionName: String
    let subscriptionAppleID: String
    let country: String
    let durationMonths: Double
    let proceeds: Double            // developer proceeds per renewal, in `proceedsCurrency`
    let proceedsCurrency: String
    let activeStandard: Int
    let activeTrial: Int
    let activeIntro: Int            // pay-up-front + pay-as-you-go introductory offers

    var paidActive: Int { activeStandard + activeIntro }
    var totalActive: Int { activeStandard + activeTrial + activeIntro }
    /// Proceeds normalised to one month (for MRR estimates).
    var monthlyProceeds: Double { durationMonths > 0 ? proceeds / durationMonths : proceeds }
}

struct SubEventRow: Sendable {
    let event: String
    let quantity: Int
    let appAppleID: String
    let country: String

    /// Normalised category for the UI.
    var category: String {
        switch event.lowercased() {
        case let e where e.contains("subscribe"): return "New"
        case let e where e.contains("cancel"): return "Cancelled"
        case let e where e.contains("refund"): return "Refunds"
        case let e where e.contains("reactivat"): return "Reactivations"
        case let e where e.contains("renew"): return "Renewals"
        case let e where e.contains("convert") || e.contains("paid subscription from"): return "Trial→Paid"
        default: return event
        }
    }
}

enum SubscriptionReport {
    /// Pure TSV parsing — `nonisolated` so it can run off the main actor (see call sites).
    nonisolated static func parseEvents(tsv: String) -> [SubEventRow] {
        var lines = tsv.components(separatedBy: "\n")
        guard lines.count > 1 else { return [] }
        let header = lines.removeFirst().components(separatedBy: "\t")
        func idx(_ n: String) -> Int? { header.firstIndex { $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(n) == .orderedSame } }
        guard let iE = idx("Event") else { return [] }
        let iQ = idx("Quantity"), iA = idx("App Apple ID"), iC = idx("Country")
        func f(_ c: [String], _ i: Int?) -> String { guard let i, c.count > i else { return "" }; return c[i].trimmingCharacters(in: .whitespaces) }
        var rows: [SubEventRow] = []
        for line in lines where !line.isEmpty {
            let c = line.components(separatedBy: "\t")
            let ev = f(c, iE); if ev.isEmpty { continue }
            rows.append(SubEventRow(event: ev, quantity: Int(f(c, iQ)) ?? 1, appAppleID: f(c, iA), country: f(c, iC)))
        }
        return rows
    }

    nonisolated static func parseRows(tsv: String) -> [SubRow] {
        var lines = tsv.components(separatedBy: "\n")
        guard lines.count > 1 else { return [] }
        let header = lines.removeFirst().components(separatedBy: "\t")
        func idx(_ name: String) -> Int? {
            header.firstIndex { $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame }
        }
        let iApp = idx("App Apple ID")
        let iName = idx("Subscription Name")
        let iSubID = idx("Subscription Apple ID")
        let iCountry = idx("Country")
        let iDuration = idx("Standard Subscription Duration")
        let iProceeds = idx("Developer Proceeds")
        let iProceedsCur = idx("Proceeds Currency")
        let iStd = idx("Active Standard Price Subscriptions")
        let iTrial = idx("Active Free Trial Introductory Offer Subscriptions")
        let iPuf = idx("Active Pay Up Front Introductory Offer Subscriptions")
        let iPayg = idx("Active Pay As You Go Introductory Offer Subscriptions")
        guard iApp != nil, iStd != nil else { return [] }

        func f(_ cols: [String], _ i: Int?) -> String {
            guard let i, cols.count > i else { return "" }
            return cols[i].trimmingCharacters(in: .whitespaces)
        }
        func n(_ cols: [String], _ i: Int?) -> Int { Int(f(cols, i)) ?? 0 }

        var rows: [SubRow] = []
        for line in lines where !line.isEmpty {
            let c = line.components(separatedBy: "\t")
            let app = f(c, iApp)
            if app.isEmpty { continue }
            rows.append(SubRow(
                appAppleID: app,
                subscriptionName: f(c, iName),
                subscriptionAppleID: f(c, iSubID),
                country: f(c, iCountry),
                durationMonths: durationToMonths(f(c, iDuration)),
                proceeds: Double(f(c, iProceeds)) ?? 0,
                proceedsCurrency: { let x = f(c, iProceedsCur); return x.isEmpty ? "USD" : x }(),
                activeStandard: n(c, iStd),
                activeTrial: n(c, iTrial),
                activeIntro: n(c, iPuf) + n(c, iPayg)))
        }
        return rows
    }

    nonisolated static func durationToMonths(_ s: String) -> Double {
        let lower = s.lowercased()
        let value = Double(lower.split(separator: " ").first ?? "1") ?? 1
        if lower.contains("year") { return value * 12 }
        if lower.contains("week") { return value * 0.230137 }
        if lower.contains("day") { return value / 30.0 }
        return value == 0 ? 1 : value   // months
    }
}

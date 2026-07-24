//
//  SalesReport.swift
//  StoreGauge
//
//  Parses the daily "SALES / SUMMARY" TSV report into granular rows. In-app
//  purchases and subscriptions appear as separate rows carrying the IAP's own
//  Apple Identifier — they link back to the parent app via "Parent Identifier"
//  (which equals the app's SKU), NOT the Apple Identifier.
//

import Foundation

struct SalesRow: Sendable {
    let appleID: String          // Apple Identifier (app id for app rows, IAP id for IAP rows)
    let sku: String              // SKU of this line item
    let parentIdentifier: String // parent app SKU for IAP rows; empty for app rows
    let country: String
    let currency: String
    let units: Int
    let proceeds: Double         // Developer Proceeds × Units, in `currency`
    let productType: String

    var isIAP: Bool { productType.uppercased().hasPrefix("IA") }
    var isRefund: Bool { units < 0 }
}

enum SalesReport {
    /// Pure TSV parsing — `nonisolated` so it can run off the main actor (see call sites).
    nonisolated static func parseRows(tsv: String) -> [SalesRow] {
        var lines = tsv.components(separatedBy: "\n")
        guard lines.count > 1 else { return [] }
        let header = lines.removeFirst().components(separatedBy: "\t")
        func idx(_ name: String) -> Int? {
            header.firstIndex { $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame }
        }
        guard let iUnits = idx("Units"), let iProceeds = idx("Developer Proceeds"),
              let iApple = idx("Apple Identifier") else { return [] }
        let iSKU = idx("SKU"), iParent = idx("Parent Identifier")
        let iCurrency = idx("Currency of Proceeds"), iCountry = idx("Country Code")
        let iType = idx("Product Type Identifier")

        func field(_ cols: [String], _ i: Int?) -> String {
            guard let i, cols.count > i else { return "" }
            return cols[i].trimmingCharacters(in: .whitespaces)
        }

        var rows: [SalesRow] = []
        for line in lines where !line.isEmpty {
            let cols = line.components(separatedBy: "\t")
            let appleID = field(cols, iApple)
            if appleID.isEmpty { continue }
            let units = Int(field(cols, iUnits)) ?? 0
            let perUnit = Double(field(cols, iProceeds)) ?? 0
            let currency = { let c = field(cols, iCurrency); return c.isEmpty ? "USD" : c }()
            rows.append(SalesRow(
                appleID: appleID,
                sku: field(cols, iSKU),
                parentIdentifier: field(cols, iParent),
                country: field(cols, iCountry),
                currency: currency,
                units: units,
                proceeds: perUnit * Double(units),
                productType: field(cols, iType)))
        }
        return rows
    }
}

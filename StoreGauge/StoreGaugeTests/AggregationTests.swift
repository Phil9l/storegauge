//
//  AggregationTests.swift
//  StoreGaugeTests
//
//  Covers the week-over-week window math behind trend alerts, currency conversion and
//  number formatting. The window logic is a pure function, so it needs no SwiftData store.
//

import Testing
import Foundation
@testable import StoreGauge

struct WeekOverWeekTests {

    private func utc(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// Recent week Jan 14–20 (10/day = 70), previous week Jan 7–13 (5/day = 35).
    @Test func splitsTwoAdjacentWeeks() {
        var points: [(date: Date, value: Double)] = []
        for d in 14...20 { points.append((utc(2026, 1, d), 10)) }
        for d in 7...13  { points.append((utc(2026, 1, d), 5)) }
        let w = SalesWindows.weekOverWeek(points, anchor: utc(2026, 1, 20))
        #expect(w.recent == 70)
        #expect(w.previous == 35)
    }

    /// The anchor day is included in `recent`; the day after it and the day before the
    /// previous window are both excluded (this is what protects against reporting lag).
    @Test func boundariesAreInclusiveOfAnchorAndExclusiveEitherSide() {
        let points: [(date: Date, value: Double)] = [
            (utc(2026, 1, 20), 1),   // anchor → recent
            (utc(2026, 1, 21), 99),  // after anchor → ignored
            (utc(2026, 1, 14), 2),   // first recent day
            (utc(2026, 1, 13), 4),   // last previous day
            (utc(2026, 1, 7),  8),   // first previous day
            (utc(2026, 1, 6), 99),   // before previous window → ignored
        ]
        let w = SalesWindows.weekOverWeek(points, anchor: utc(2026, 1, 20))
        #expect(w.recent == 3)      // 1 + 2
        #expect(w.previous == 12)   // 4 + 8
    }

    @Test func emptyInputIsZero() {
        let w = SalesWindows.weekOverWeek([], anchor: utc(2026, 1, 20))
        #expect(w.recent == 0)
        #expect(w.previous == 0)
    }
}

@MainActor
struct FXTests {

    @Test func sameCurrencyIsIdentity() {
        #expect(FXService.shared.convert(10, from: "USD", to: "USD") == 10)
    }

    @Test func euroConvertsToMoreDollars() {
        // At any sane rate €100 is worth more than $100.
        if let usd = FXService.shared.convert(100, from: "EUR", to: "USD") {
            #expect(usd > 100)
        }
    }
}

@MainActor
struct FormatTests {

    @Test func compactUsesThousandAndMillionSuffixes() {
        #expect(Format.compact(2_000_000).hasSuffix("M"))
        #expect(Format.compact(1_500).hasSuffix("K"))
        #expect(Format.compact(500) == "500")
    }

    @Test func percentPlainRendersWholePercents() {
        #expect(Format.percentPlain(0.5).contains("50"))
    }

    @Test func currencyIncludesTheAmount() {
        #expect(Format.currency(10, code: "USD").contains("10"))
    }
}

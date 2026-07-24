//
//  GooglePlayStatisticsReports.swift
//  StoreGauge
//
//  Parses the aggregated Google Play statistics exports stored in the same
//  private Cloud Storage report bucket as financial reports.
//

import Foundation

struct GoogleInstallStatistic: Sendable {
    let date: Date
    let packageID: String
    let dailyUserInstalls: Double
    let dailyDeviceUpgrades: Double
}

enum GoogleStatisticsReportParser {
    nonisolated static func installs(data: Data) throws -> [GoogleInstallStatistic] {
        guard let text = GoogleFinancialCSV.text(from: data) else {
            throw GooglePlayError.message("Google’s installs CSV uses an unsupported text encoding.")
        }
        let table = GoogleFinancialCSV.rows(text)
        guard let header = table.first else { return [] }
        let columns = columnMap(header)
        guard let dateIndex = columns[normalize("Date")],
              let packageIndex = columns[normalize("Package Name")],
              let installsIndex = columns[normalize("Daily User Installs")],
              let upgradesIndex = columns[normalize("Daily Device Upgrades")] else {
            throw GooglePlayError.message("Google’s installs CSV is missing a required column.")
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        return table.dropFirst().compactMap { row in
            guard let dateText = value(row, at: dateIndex),
                  let date = formatter.date(from: dateText),
                  let package = value(row, at: packageIndex), !package.isEmpty else { return nil }
            return GoogleInstallStatistic(
                date: calendar.startOfDay(for: date),
                packageID: package,
                dailyUserInstalls: value(row, at: installsIndex).flatMap(GoogleFinancialCSV.number) ?? 0,
                dailyDeviceUpgrades: value(row, at: upgradesIndex).flatMap(GoogleFinancialCSV.number) ?? 0
            )
        }
    }

    private nonisolated static func normalize(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{feff}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private nonisolated static func columnMap(_ header: [String]) -> [String: Int] {
        Dictionary(header.enumerated().map { (normalize($0.element), $0.offset) },
                   uniquingKeysWith: { first, _ in first })
    }

    private nonisolated static func value(_ row: [String], at index: Int) -> String? {
        guard row.indices.contains(index) else { return nil }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

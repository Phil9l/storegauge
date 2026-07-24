//
//  FXService.swift
//  StoreGauge
//
//  Converts developer proceeds between currencies. Uses live ECB rates from the
//  free Frankfurter API when available, falling back to a built-in approximate
//  table so a combined income figure is always available offline.
//

import Foundation

@MainActor
@Observable
final class FXService {
    static let shared = FXService()

    /// Units of currency per 1 USD. `live` is fetched; `fallback` is embedded.
    private(set) var live: [String: Double] = [:]
    private(set) var lastUpdated: Date?
    var usingLiveRates: Bool { !live.isEmpty }

    private struct Frankfurter: Decodable { let base: String; let rates: [String: Double] }

    func refreshIfNeeded() async {
        if let last = lastUpdated, Date().timeIntervalSince(last) < 6 * 3600 { return }
        await refresh()
    }

    func refresh() async {
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=USD") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(Frankfurter.self, from: data)
            var map = decoded.rates
            map["USD"] = 1.0
            live = map
            lastUpdated = Date()
        } catch {
            // keep whatever we had; fallback table still works
        }
    }

    /// 1 USD in `code`.
    private func perUSD(_ code: String) -> Double? {
        live[code] ?? FXService.fallbackPerUSD[code]
    }

    /// Converts `amount` from `from` currency to `to` currency. Returns nil only
    /// if both live and fallback lack a needed rate.
    func convert(_ amount: Double, from: String, to: String) -> Double? {
        if from == to { return amount }
        guard let fromRate = perUSD(from), let toRate = perUSD(to), fromRate != 0 else { return nil }
        let usd = amount / fromRate
        return usd * toRate
    }

    /// Approximate mid-decade USD rates for currencies (incl. some not covered by ECB).
    static let fallbackPerUSD: [String: Double] = [
        "USD": 1, "EUR": 0.92, "GBP": 0.79, "JPY": 150, "CNY": 7.2, "RMB": 7.2,
        "AUD": 1.5, "CAD": 1.36, "CHF": 0.88, "HKD": 7.8, "SGD": 1.34, "NZD": 1.63,
        "SEK": 10.5, "NOK": 10.7, "DKK": 6.9, "PLN": 4.0, "CZK": 23, "HUF": 360,
        "RON": 4.6, "BGN": 1.8, "HRK": 6.9, "TRY": 32, "ILS": 3.7, "AED": 3.67,
        "SAR": 3.75, "QAR": 3.64, "KWD": 0.31, "INR": 83, "IDR": 15700, "MYR": 4.7,
        "THB": 36, "PHP": 56, "VND": 24500, "KRW": 1330, "TWD": 32, "RUB": 90,
        "UAH": 39, "KZT": 450, "MXN": 17, "BRL": 5.0, "CLP": 950, "COP": 3900,
        "PEN": 3.7, "ARS": 900, "ZAR": 18.5, "EGP": 48, "NGN": 1500, "PKR": 278,
        "BDT": 110, "LKR": 300, "NPR": 133,
    ]

    /// Currencies offered in the display-currency picker.
    static let commonDisplayCurrencies = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF", "CNY", "INR", "BRL", "MXN", "KRW", "SGD", "SEK", "PLN", "TRY", "RUB", "UAH"]
}

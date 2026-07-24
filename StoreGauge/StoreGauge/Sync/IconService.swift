//
//  IconService.swift
//  StoreGauge
//
//  Resolves app artwork via the public App Store lookup or a Google Play public
//  listing. Provider APIs intentionally do not expose icon artwork.
//

import Foundation

@MainActor
enum IconService {
    private struct Lookup: Decodable {
        struct Result: Decodable { let artworkUrl512: String?; let artworkUrl100: String? }
        let results: [Result]
    }

    private static var cache: [String: String] = [:]

    static func iconURL(for remoteIdentifier: String, platform: StorePlatform = .appleAppStore) async -> String? {
        let cacheKey = "\(platform.rawValue)|\(remoteIdentifier)"
        if let cached = cache[cacheKey] { return cached }
        let result: String?
        switch platform {
        case .appleAppStore:
            result = await appleIconURL(appStoreID: remoteIdentifier)
        case .googlePlay:
            result = await googlePlayIconURL(packageName: remoteIdentifier)
        }
        if let result { cache[cacheKey] = result }
        return result
    }

    private static func appleIconURL(appStoreID: String) async -> String? {
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(appStoreID)") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(Lookup.self, from: data)
            if let art = decoded.results.first?.artworkUrl512 ?? decoded.results.first?.artworkUrl100 {
                return art.replacingOccurrences(of: "100x100", with: "512x512")
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func googlePlayIconURL(packageName: String) async -> String? {
        guard var components = URLComponents(string: "https://play.google.com/store/apps/details") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "id", value: packageName),
            URLQueryItem(name: "hl", value: "en"),
            URLQueryItem(name: "gl", value: "US"),
        ]
        guard let url = components.url else { return nil }
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 StoreGauge/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else { return nil }
            let patterns = [
                #"<meta[^>]+property=[\"']og:image[\"'][^>]+content=[\"']([^\"']+)[\"']"#,
                #"<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+property=[\"']og:image[\"']"#,
                #"<meta[^>]+itemprop=[\"']image[\"'][^>]+content=[\"']([^\"']+)[\"']"#,
                #"<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+itemprop=[\"']image[\"']"#,
            ]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                let range = NSRange(html.startIndex..<html.endIndex, in: html)
                guard let match = regex.firstMatch(in: html, range: range),
                      let capture = Range(match.range(at: 1), in: html) else { continue }
                let value = String(html[capture])
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                if URL(string: value) != nil { return value }
            }
        } catch {
            return nil
        }
        return nil
    }
}

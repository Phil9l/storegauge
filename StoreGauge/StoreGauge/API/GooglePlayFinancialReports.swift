//
//  GooglePlayFinancialReports.swift
//  StoreGauge
//
//  Reads exports from the developer account's private Google Play Cloud Storage
//  report bucket. Reports are kept local and normalized into daily metrics; raw
//  transaction rows are never persisted or logged.
//

import Foundation

struct GoogleStorageObject: Decodable, Sendable {
    let name: String
    let updated: String?
    let size: String?
}

@MainActor
final class GoogleCloudStorageClient {
    private static let storageBase = "https://storage.googleapis.com"

    let credentials: GoogleServiceAccountCredentials
    let bucket: String
    private let session: URLSession

    init(credentials: GoogleServiceAccountCredentials, bucket: String, session: URLSession? = nil) throws {
        self.credentials = credentials
        self.bucket = try Self.normalizeBucket(bucket)
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 90
            configuration.waitsForConnectivity = true
            self.session = URLSession(configuration: configuration)
        }
    }

    /// A successful empty listing is valid for a new account with no reports yet.
    func verifyConnection() async throws {
        _ = try await listObjects(prefix: "stats/installs/", maxResults: 1)
        DiagnosticLog.record("Google Play · Report bucket verified · \(bucket)")
    }

    func listObjects(prefix: String, maxResults: Int = 1_000) async throws -> [GoogleStorageObject] {
        struct Response: Decodable {
            let items: [GoogleStorageObject]?
            let nextPageToken: String?
        }

        var output: [GoogleStorageObject] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(string: Self.storageBase + "/storage/v1/b/\(Self.pathSegment(bucket))/o")!
            components.queryItems = [
                URLQueryItem(name: "prefix", value: prefix),
                URLQueryItem(name: "maxResults", value: String(min(maxResults, 1_000))),
                URLQueryItem(name: "pageToken", value: pageToken),
            ].filter { $0.value != nil }
            let data = try await request(url: components.url!, operation: "List reports")
            let response: Response
            do {
                response = try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw GooglePlayError.message("Google Cloud Storage returned an unreadable report listing.")
            }
            output.append(contentsOf: response.items ?? [])
            if output.count >= maxResults { break }
            pageToken = response.nextPageToken
        } while pageToken?.isEmpty == false
        return Array(output.prefix(maxResults))
    }

    func download(object name: String) async throws -> Data {
        var components = URLComponents(string: Self.storageBase + "/download/storage/v1/b/\(Self.pathSegment(bucket))/o/\(Self.pathSegment(name))")!
        components.queryItems = [URLQueryItem(name: "alt", value: "media")]
        let data = try await request(url: components.url!, operation: "Download \(name)")
        DiagnosticLog.record("Google Play · Report downloaded · \(name) · \(data.count) bytes")
        return data
    }

    private func request(url: URL, operation: String, attempt: Int = 0) async throws -> Data {
        let token = try await GoogleOAuth.accessToken(
            for: credentials,
            scopes: [GoogleOAuthScope.storageReadOnly]
        )
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            DiagnosticLog.record("Google Play · \(operation) · Network failed · \(error.localizedDescription)")
            throw GooglePlayError.message("Google Play reports network error: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw GooglePlayError.message("Google Cloud Storage returned no HTTP response.")
        }
        if (200...299).contains(http.statusCode) { return data }
        if http.statusCode == 401, attempt == 0 {
            GoogleOAuth.invalidate(clientEmail: credentials.clientEmail)
            return try await self.request(url: url, operation: operation, attempt: 1)
        }
        let fallback: String
        if http.statusCode == 403 {
            fallback = "The service account can’t read this report bucket. In Play Console, grant it Global “View app information”; financial exports also require Global “View financial data”."
        } else if http.statusCode == 404 {
            fallback = "Google couldn’t find this report bucket. Copy the complete pubsite_prod_rev_… bucket ID from Play Console."
        } else {
            fallback = "Google Cloud Storage request failed (HTTP \(http.statusCode))."
        }
        let error = GooglePlayError.from(data: data, statusCode: http.statusCode, fallback: fallback)
        DiagnosticLog.record("Google Play · \(operation) · HTTP \(http.statusCode) · \(error.detail)")
        throw error
    }

    static func normalizeBucket(_ value: String) throws -> String {
        do {
            return try AccountFieldValidation.normalizeGoogleReportBucket(value)
        } catch {
            throw GooglePlayError.message(
                (error as? LocalizedError)?.errorDescription
                    ?? "Enter the Google Play report bucket ID, such as pubsite_prod_rev_0123456789."
            )
        }
    }

    private static func pathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

// MARK: - ZIP + CSV

enum GoogleFinancialArchive {
    enum ArchiveError: LocalizedError {
        case invalidZIP
        case unsupportedCompression(UInt16)
        case reportTooLarge
        case noCSV

        var errorDescription: String? {
            switch self {
            case .invalidZIP: return "The Google financial report ZIP is invalid."
            case .unsupportedCompression(let method): return "The Google financial report uses unsupported ZIP compression method \(method)."
            case .reportTooLarge: return "The uncompressed Google financial report is larger than 256 MB."
            case .noCSV: return "The Google financial report ZIP contains no CSV file."
            }
        }
    }

    /// Extracts the first CSV entry using the central directory, so ZIPs that use
    /// data descriptors are handled correctly. Google currently uses stored or
    /// raw-DEFLATE entries.
    nonisolated static func csvData(from data: Data) throws -> Data {
        guard data.count >= 22 else { throw ArchiveError.invalidZIP }
        let minimum = max(0, data.count - 65_557)
        guard let eocd = stride(from: data.count - 22, through: minimum, by: -1).first(where: {
            data.uint32LE(at: $0) == 0x0605_4b50
        }) else { throw ArchiveError.invalidZIP }

        let entryCount = Int(data.uint16LE(at: eocd + 10))
        var cursor = Int(data.uint32LE(at: eocd + 16))
        for _ in 0..<entryCount {
            guard cursor + 46 <= data.count, data.uint32LE(at: cursor) == 0x0201_4b50 else {
                throw ArchiveError.invalidZIP
            }
            let method = data.uint16LE(at: cursor + 10)
            let compressedSize = Int(data.uint32LE(at: cursor + 20))
            let uncompressedSize = Int(data.uint32LE(at: cursor + 24))
            let nameLength = Int(data.uint16LE(at: cursor + 28))
            let extraLength = Int(data.uint16LE(at: cursor + 30))
            let commentLength = Int(data.uint16LE(at: cursor + 32))
            let localOffset = Int(data.uint32LE(at: cursor + 42))
            guard cursor + 46 + nameLength <= data.count else { throw ArchiveError.invalidZIP }
            let nameData = data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
            let name = String(data: nameData, encoding: .utf8) ?? ""

            if name.lowercased().hasSuffix(".csv") {
                guard uncompressedSize <= 256 * 1_024 * 1_024,
                      localOffset + 30 <= data.count,
                      data.uint32LE(at: localOffset) == 0x0403_4b50 else {
                    throw uncompressedSize > 256 * 1_024 * 1_024 ? ArchiveError.reportTooLarge : ArchiveError.invalidZIP
                }
                let localNameLength = Int(data.uint16LE(at: localOffset + 26))
                let localExtraLength = Int(data.uint16LE(at: localOffset + 28))
                let start = localOffset + 30 + localNameLength + localExtraLength
                let end = start + compressedSize
                guard start >= 0, end <= data.count else { throw ArchiveError.invalidZIP }
                let compressed = data.subdata(in: start..<end)
                switch method {
                case 0:
                    return compressed
                case 8:
                    guard let inflated = Gzip.inflate(compressed, expectedSize: uncompressedSize) else {
                        throw ArchiveError.invalidZIP
                    }
                    return inflated
                default:
                    throw ArchiveError.unsupportedCompression(method)
                }
            }
            cursor += 46 + nameLength + extraLength + commentLength
        }
        throw ArchiveError.noCSV
    }
}

private extension Data {
    nonisolated func uint16LE(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return UInt16(self[index(startIndex, offsetBy: offset)]) |
            (UInt16(self[index(startIndex, offsetBy: offset + 1)]) << 8)
    }

    nonisolated func uint32LE(at offset: Int) -> UInt32 {
        UInt32(uint16LE(at: offset)) | (UInt32(uint16LE(at: offset + 2)) << 16)
    }
}

enum GoogleFinancialCSV {
    nonisolated static func text(from data: Data) -> String? {
        if data.starts(with: [0xff, 0xfe]) {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        if data.starts(with: [0xfe, 0xff]) {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        }
        if data.starts(with: [0xef, 0xbb, 0xbf]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
    }

    /// RFC 4180-style CSV parser with escaped quotes and embedded newlines.
    nonisolated static func rows(_ text: String) -> [[String]] {
        let bytes = Array(text.utf8)
        var rows: [[String]] = []
        var row: [String] = []
        var field: [UInt8] = []
        var quoted = false
        var i = 0

        func decodedField() -> String { String(decoding: field, as: UTF8.self) }
        func finishField() { row.append(decodedField()); field.removeAll(keepingCapacity: true) }
        func finishRow() {
            finishField()
            if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
            row.removeAll(keepingCapacity: true)
        }

        while i < bytes.count {
            let byte = bytes[i]
            if quoted {
                if byte == 0x22 {
                    if i + 1 < bytes.count, bytes[i + 1] == 0x22 {
                        field.append(0x22); i += 1
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(byte)
                }
            } else {
                switch byte {
                case 0x22 where field.isEmpty: quoted = true
                case 0x2c: finishField()
                case 0x0a: finishRow()
                case 0x0d: break
                default: field.append(byte)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { finishRow() }
        return rows
    }

    nonisolated static func number(_ value: String) -> Double? {
        let cleaned = value
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if cleaned.hasPrefix("("), cleaned.hasSuffix(")") {
            return Double(cleaned.dropFirst().dropLast()).map { -$0 }
        }
        return Double(cleaned)
    }
}

struct GoogleEstimatedSale: Sendable {
    let date: Date
    let packageID: String
    let currency: String
    let grossAmount: Double
    let orderDelta: Double
}

struct GoogleEarning: Sendable {
    let date: Date
    let packageID: String
    let merchantCurrency: String
    let netAmount: Double
}

enum GoogleFinancialReportParser {
    nonisolated static func estimatedSales(data: Data) throws -> [GoogleEstimatedSale] {
        guard let text = GoogleFinancialCSV.text(from: data) else {
            throw GooglePlayError.message("Google’s estimated-sales CSV uses an unsupported text encoding.")
        }
        let table = GoogleFinancialCSV.rows(text)
        guard let header = table.first else { return [] }
        let columns = columnMap(header)
        guard let dateIndex = columns[normalize("Order Charged Date")],
              let packageIndex = columns[normalize("Package ID")],
              let statusIndex = columns[normalize("Financial Status")],
              let currencyIndex = columns[normalize("Currency of Sale")],
              let amountIndex = columns[normalize("Charged Amount")] else {
            throw GooglePlayError.message("Google’s estimated-sales CSV is missing a required column.")
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        return table.dropFirst().compactMap { row in
            guard let dateText = row[safe: dateIndex],
                  let date = formatter.date(from: dateText),
                  let package = row[safe: packageIndex], !package.isEmpty,
                  let currency = row[safe: currencyIndex], !currency.isEmpty,
                  let rawAmount = row[safe: amountIndex].flatMap(GoogleFinancialCSV.number),
                  let status = row[safe: statusIndex]?.lowercased() else { return nil }
            let isRefund = status.contains("refund")
            let isPartialRefund = status.contains("partial")
            return GoogleEstimatedSale(
                date: utcCalendar.startOfDay(for: date),
                packageID: package,
                currency: currency.uppercased(),
                grossAmount: isRefund ? -abs(rawAmount) : abs(rawAmount),
                orderDelta: isRefund ? (isPartialRefund ? 0 : -1) : 1
            )
        }
    }

    nonisolated static func earnings(data: Data) throws -> [GoogleEarning] {
        guard let text = GoogleFinancialCSV.text(from: data) else {
            throw GooglePlayError.message("Google’s earnings CSV uses an unsupported text encoding.")
        }
        let table = GoogleFinancialCSV.rows(text)
        guard let header = table.first else { return [] }
        let columns = columnMap(header)
        guard let dateIndex = columns[normalize("Transaction Date")],
              let typeIndex = columns[normalize("Transaction Type")],
              let packageIndex = columns[normalize("Package ID")],
              let currencyIndex = columns[normalize("Merchant Currency")],
              let amountIndex = columns[normalize("Amount (Merchant Currency)")] else {
            throw GooglePlayError.message("Google’s earnings CSV is missing a required column.")
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        formatter.dateFormat = "MMM d, yyyy"
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        return table.dropFirst().compactMap { row in
            guard let dateText = row[safe: dateIndex],
                  let date = formatter.date(from: dateText),
                  let type = row[safe: typeIndex]?.lowercased(),
                  let package = row[safe: packageIndex], !package.isEmpty,
                  let currency = row[safe: currencyIndex], !currency.isEmpty,
                  let rawAmount = row[safe: amountIndex].flatMap(GoogleFinancialCSV.number) else { return nil }
            return GoogleEarning(
                date: utcCalendar.startOfDay(for: date),
                packageID: package,
                merchantCurrency: currency.uppercased(),
                netAmount: signedEarningAmount(rawAmount, transactionType: type)
            )
        }
    }

    /// Earnings rows describe both money received and deductions. Normalize the
    /// known transaction types because exports encountered in the wild have used
    /// both signed and unsigned representations.
    nonisolated static func signedEarningAmount(_ amount: Double, transactionType: String) -> Double {
        let type = transactionType.lowercased()
        if type.contains("refund") {
            return (type.contains("google fee") || type.contains("tax")) ? abs(amount) : -abs(amount)
        }
        if type.contains("google fee") || type == "tax" || type.contains("tax rebill") {
            return -abs(amount)
        }
        if type.contains("charge") { return abs(amount) }
        return amount // Google-defined adjustments retain their supplied sign.
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
}

private extension Array where Element == String {
    nonisolated subscript(safe index: Int) -> String? {
        indices.contains(index) ? self[index].trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }
}

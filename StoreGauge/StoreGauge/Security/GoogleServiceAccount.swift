//
//  GoogleServiceAccount.swift
//  StoreGauge
//
//  Google service-account credentials and OAuth token exchange. The downloaded
//  JSON payload stays in Keychain; StoreGauge signs short-lived RS256 assertions
//  locally with Security.framework and never sends the private key to StoreGauge.
//

import Foundation
import Security

struct GoogleServiceAccountCredentials: Codable, Equatable, Sendable {
    let type: String
    let projectID: String
    let privateKeyID: String
    let privateKey: String
    let clientEmail: String
    let clientID: String?
    let tokenURI: String?

    enum CodingKeys: String, CodingKey {
        case type
        case projectID = "project_id"
        case privateKeyID = "private_key_id"
        case privateKey = "private_key"
        case clientEmail = "client_email"
        case clientID = "client_id"
        case tokenURI = "token_uri"
    }

    var tokenEndpoint: URL {
        URL(string: tokenURI ?? "https://oauth2.googleapis.com/token")!
    }

    static func decode(json: String) throws -> Self {
        guard let data = json.data(using: .utf8) else {
            throw GooglePlayError.message("The service-account JSON is not valid UTF-8.")
        }
        let credentials: Self
        do {
            credentials = try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw GooglePlayError.message("Invalid service-account JSON. Choose the complete JSON key downloaded from Google Cloud.")
        }
        guard credentials.type == "service_account",
              !credentials.projectID.isEmpty,
              !credentials.privateKeyID.isEmpty,
              !credentials.clientEmail.isEmpty,
              credentials.privateKey.contains("PRIVATE KEY")
        else {
            throw GooglePlayError.message("This is not a complete Google service-account key.")
        }
        return credentials
    }
}

enum GoogleOAuthScope {
    static let androidPublisher = "https://www.googleapis.com/auth/androidpublisher"
    static let developerReporting = "https://www.googleapis.com/auth/playdeveloperreporting"
    static let storageReadOnly = "https://www.googleapis.com/auth/devstorage.read_only"
}

@MainActor
enum GoogleOAuth {
    private struct CachedToken {
        let value: String
        let expiresAt: Date
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
        }
    }

    private static var cache: [String: CachedToken] = [:]

    static func accessToken(for credentials: GoogleServiceAccountCredentials,
                            scopes: [String]) async throws -> String {
        let normalizedScopes = scopes.sorted()
        let cacheKey = credentials.clientEmail + "|" + normalizedScopes.joined(separator: " ")
        if let cached = cache[cacheKey], cached.expiresAt > Date().addingTimeInterval(300) {
            return cached.value
        }

        let assertion = try GoogleServiceAccountJWT.assertion(
            credentials: credentials,
            scopes: normalizedScopes
        )
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:jwt-bearer"),
            URLQueryItem(name: "assertion", value: assertion),
        ]

        var request = URLRequest(url: credentials.tokenEndpoint)
        request.httpMethod = "POST"
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GooglePlayError.message("Couldn’t contact Google OAuth: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw GooglePlayError.message("Google OAuth returned no HTTP response.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw GooglePlayError.from(data: data, statusCode: http.statusCode,
                                       fallback: "Google rejected the service-account credentials.")
        }

        let token: TokenResponse
        do {
            token = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw GooglePlayError.message("Google OAuth returned an unreadable token response.")
        }
        cache[cacheKey] = CachedToken(
            value: token.accessToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn))
        )
        return token.accessToken
    }

    static func invalidate(clientEmail: String) {
        cache = cache.filter { !$0.key.hasPrefix(clientEmail + "|") }
    }
}

enum GoogleServiceAccountJWT {
    static func assertion(credentials: GoogleServiceAccountCredentials,
                          scopes: [String],
                          now: Date = Date()) throws -> String {
        let header: [String: String] = [
            "alg": "RS256",
            "kid": credentials.privateKeyID,
            "typ": "JWT",
        ]
        let payload: [String: Any] = [
            "iss": credentials.clientEmail,
            "scope": scopes.joined(separator: " "),
            "aud": credentials.tokenEndpoint.absoluteString,
            "iat": Int(now.timeIntervalSince1970),
            "exp": Int(now.addingTimeInterval(3600).timeIntervalSince1970),
        ]
        let headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let signingInput = base64url(headerData) + "." + base64url(payloadData)
        let key = try GoogleRSA.privateKey(fromPEM: credentials.privateKey)

        var signingError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            Data(signingInput.utf8) as CFData,
            &signingError
        ) as Data? else {
            let detail = signingError?.takeRetainedValue().localizedDescription ?? "Unknown signing error"
            throw GooglePlayError.message("Couldn’t sign the Google access token: \(detail)")
        }
        return signingInput + "." + base64url(signature)
    }
}

enum GoogleRSA {
    static func privateKey(fromPEM pem: String) throws -> SecKey {
        let isPKCS1 = pem.contains("BEGIN RSA PRIVATE KEY")
        let body = pem
            .replacingOccurrences(of: "\\n", with: "\n")
            .split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let der = Data(base64Encoded: body) else {
            throw GooglePlayError.message("The private key in the service-account JSON is invalid.")
        }
        let keyData = isPKCS1 ? der : try unwrapPKCS8(der)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        var keyError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &keyError) else {
            let detail = keyError?.takeRetainedValue().localizedDescription ?? "Unknown key error"
            throw GooglePlayError.message("Couldn’t read the Google private key: \(detail)")
        }
        return key
    }

    /// A service-account JSON key contains PKCS#8. Security.framework imports an
    /// RSA private key as PKCS#1, stored inside PKCS#8's privateKey OCTET STRING.
    static func unwrapPKCS8(_ der: Data) throws -> Data {
        var top = DERReader(data: der)
        let sequence = try top.read(tag: 0x30)
        var fields = DERReader(data: sequence)
        _ = try fields.read(tag: 0x02) // version
        _ = try fields.read(tag: 0x30) // rsaEncryption algorithm identifier
        return try fields.read(tag: 0x04)
    }
}

private struct DERReader {
    let data: Data
    private(set) var offset = 0

    mutating func read(tag expectedTag: UInt8) throws -> Data {
        guard offset < data.count, data[offset] == expectedTag else {
            throw GooglePlayError.message("The Google private key uses an unsupported DER format.")
        }
        offset += 1
        let length = try readLength()
        guard length >= 0, offset + length <= data.count else {
            throw GooglePlayError.message("The Google private key is truncated.")
        }
        let result = data.subdata(in: offset..<(offset + length))
        offset += length
        return result
    }

    private mutating func readLength() throws -> Int {
        guard offset < data.count else {
            throw GooglePlayError.message("The Google private key is truncated.")
        }
        let first = Int(data[offset])
        offset += 1
        if first & 0x80 == 0 { return first }

        let byteCount = first & 0x7f
        guard byteCount > 0, byteCount <= 4, offset + byteCount <= data.count else {
            throw GooglePlayError.message("The Google private key has an invalid DER length.")
        }
        var length = 0
        for _ in 0..<byteCount {
            length = (length << 8) | Int(data[offset])
            offset += 1
        }
        return length
    }
}

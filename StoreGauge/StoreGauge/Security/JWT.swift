//
//  JWT.swift
//  StoreGauge
//
//  ES256 (ECDSA P-256 / SHA-256) JSON Web Tokens for App Store Connect, signed
//  with CryptoKit — no third-party dependency. Tokens are cached per key id and
//  refreshed shortly before Apple's 20-minute maximum lifetime.
//

import Foundation
import CryptoKit

/// Everything needed to authenticate one App Store Connect request.
struct ASCCredentials: Sendable, Equatable {
    let issuerID: String
    let keyID: String
    let p8PEM: String
}

enum JWT {
    struct SigningError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct Cached { let token: String; let expiresAt: Date }
    private static var cache: [String: Cached] = [:]

    /// Returns a valid bearer token, reusing a cached one when possible.
    static func token(for creds: ASCCredentials) throws -> String {
        let now = Date()
        if let c = cache[creds.keyID], c.expiresAt > now.addingTimeInterval(120) {
            return c.token
        }
        let ttl: TimeInterval = 60 * 18 // 18 min, under Apple's 20 min cap
        let token = try make(creds: creds, now: now, ttl: ttl)
        cache[creds.keyID] = Cached(token: token, expiresAt: now.addingTimeInterval(ttl))
        return token
    }

    static func invalidate(keyID: String) { cache[keyID] = nil }

    static func make(creds: ASCCredentials, now: Date = Date(), ttl: TimeInterval = 60 * 18) throws -> String {
        let header: [String: String] = ["alg": "ES256", "kid": creds.keyID, "typ": "JWT"]
        let payload: [String: Any] = [
            "iss": creds.issuerID,
            "iat": Int(now.timeIntervalSince1970),
            "exp": Int(now.addingTimeInterval(ttl).timeIntervalSince1970),
            "aud": "appstoreconnect-v1",
        ]
        let headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let signingInput = base64url(headerData) + "." + base64url(payloadData)

        let key = try privateKey(from: creds.p8PEM)
        let signature = try key.signature(for: Data(signingInput.utf8))
        return signingInput + "." + base64url(signature.rawRepresentation)
    }

    static func privateKey(from pem: String) throws -> P256.Signing.PrivateKey {
        let normalized = normalizePEM(pem)
        do {
            return try P256.Signing.PrivateKey(pemRepresentation: normalized)
        } catch {
            throw SigningError(message: "Invalid .p8 private key. Paste the full contents of your AuthKey_XXXXXXXXXX.p8 file.")
        }
    }

    /// Accepts a full PEM, a PEM with escaped newlines, or a bare base64 body.
    static func normalizePEM(_ raw: String) -> String {
        let s = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if s.contains("BEGIN") { return s }

        let body = s.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
        var lines = ["-----BEGIN PRIVATE KEY-----"]
        var idx = body.startIndex
        while idx < body.endIndex {
            let end = body.index(idx, offsetBy: 64, limitedBy: body.endIndex) ?? body.endIndex
            lines.append(String(body[idx..<end]))
            idx = end
        }
        lines.append("-----END PRIVATE KEY-----")
        return lines.joined(separator: "\n")
    }
}

/// Base64URL (RFC 4648) without padding.
func base64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

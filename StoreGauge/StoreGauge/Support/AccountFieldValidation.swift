//
//  AccountFieldValidation.swift
//  StoreGauge
//
//  Shared, local format checks for account fields entered on macOS and iOS.
//

import Foundation

enum AccountFieldValidation {
    struct FieldError: LocalizedError, Equatable {
        let message: String
        var errorDescription: String? { message }
    }

    private static let issuerIDPattern =
        #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#
    private static let keyIDPattern = #"^[A-Za-z0-9]{10}$"#
    private static let vendorNumberPattern = #"^[0-9]+$"#
    private static let googleReportBucketPattern = #"^pubsite_prod_rev_[0-9]+$"#

    static func isValidIssuerID(_ value: String) -> Bool {
        matches(value.trimmedForValidation, issuerIDPattern)
    }

    static func isValidKeyID(_ value: String) -> Bool {
        matches(value.trimmedForValidation, keyIDPattern)
    }

    static func isValidVendorNumber(_ value: String) -> Bool {
        let value = value.trimmedForValidation
        return value.isEmpty || matches(value, vendorNumberPattern)
    }

    static func isValidGoogleReportBucket(_ value: String) -> Bool {
        let value = value.trimmedForValidation
        return value.isEmpty || (try? normalizeGoogleReportBucket(value)) != nil
    }

    static func validateApple(issuerID: String, keyID: String, vendorNumber: String) throws {
        guard isValidIssuerID(issuerID) else {
            throw FieldError(
                message: "Issuer ID must be a UUID in the form 00000000-0000-0000-0000-000000000000."
            )
        }
        guard isValidKeyID(keyID) else {
            throw FieldError(message: "Key ID must contain exactly 10 letters or digits.")
        }
        guard isValidVendorNumber(vendorNumber) else {
            throw FieldError(message: "Vendor Number must contain digits only.")
        }
    }

    static func validateGoogle(reportBucket: String) throws {
        guard isValidGoogleReportBucket(reportBucket) else {
            throw FieldError(
                message: "The report bucket must be pubsite_prod_rev_ followed by the numeric developer account ID."
            )
        }
    }

    static func normalizedKeyID(_ value: String) -> String {
        value.trimmedForValidation.uppercased()
    }

    static func normalizeGoogleReportBucket(_ value: String) throws -> String {
        var bucket = value.trimmedForValidation
        if bucket.lowercased().hasPrefix("gs://") {
            bucket.removeFirst(5)
        }
        bucket = bucket.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        guard matches(bucket, googleReportBucketPattern) else {
            throw FieldError(
                message: "Enter the Google Play report bucket ID, such as pubsite_prod_rev_0123456789."
            )
        }
        return bucket
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}

private extension String {
    var trimmedForValidation: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

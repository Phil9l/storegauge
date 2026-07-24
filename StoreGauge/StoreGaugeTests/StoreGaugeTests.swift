//
//  StoreGaugeTests.swift
//  StoreGaugeTests
//
//  Report-parsing tests. These parsers run off the main actor during sync, so the
//  functions are `nonisolated` and testable without any MainActor hop.
//

import Testing
import Foundation
import Security
import SwiftData
@testable import StoreGauge

struct SalesReportTests {

    /// A minimal Sales report: an app sale, an in-app purchase, a refund and an update row.
    /// Columns are looked up by header name, so only the referenced ones need to be present.
    private static let tsv = """
    Units\tDeveloper Proceeds\tApple Identifier\tSKU\tParent Identifier\tCurrency of Proceeds\tCountry Code\tProduct Type Identifier
    5\t0.70\t12345\tmyapp\t\tUSD\tUS\t1F
    3\t1.40\t99999\tmyapp.pro\tmyapp\tUSD\tUS\tIA1
    -1\t0.70\t12345\tmyapp\t\tUSD\tDE\t1F
    2\t0.00\t12345\tmyapp\t\tGBP\tGB\t7F
    """

    @Test func parsesAllRows() {
        #expect(SalesReport.parseRows(tsv: Self.tsv).count == 4)
    }

    @Test func appRowUnitsAndProceeds() throws {
        let rows = SalesReport.parseRows(tsv: Self.tsv)
        let app = try #require(rows.first)
        #expect(app.units == 5)
        #expect(abs(app.proceeds - 3.5) < 0.0001)   // per-unit 0.70 × 5
        #expect(app.isIAP == false)
        #expect(app.isRefund == false)
        #expect(app.country == "US")
    }

    @Test func iapRowDetectedAndLinkedToParent() throws {
        let iap = try #require(SalesReport.parseRows(tsv: Self.tsv).first { $0.isIAP })
        #expect(iap.parentIdentifier == "myapp")
        #expect(abs(iap.proceeds - 4.2) < 0.0001)    // 1.40 × 3
    }

    @Test func refundHasNegativeUnits() throws {
        let refund = try #require(SalesReport.parseRows(tsv: Self.tsv).first { $0.isRefund })
        #expect(refund.units == -1)
        #expect(refund.proceeds < 0)
    }

    @Test func updateRowKeepsCurrency() throws {
        let update = try #require(SalesReport.parseRows(tsv: Self.tsv).first { $0.productType == "7F" })
        #expect(update.currency == "GBP")
    }

    @Test func emptyInputYieldsNoRows() {
        #expect(SalesReport.parseRows(tsv: "").isEmpty)
        #expect(SalesReport.parseRows(tsv: "Units\tDeveloper Proceeds\tApple Identifier").isEmpty)
    }

    @Test func missingCurrencyDefaultsToUSD() {
        let tsv = "Units\tDeveloper Proceeds\tApple Identifier\tCurrency of Proceeds\n4\t1.00\t7\t"
        let row = SalesReport.parseRows(tsv: tsv).first
        #expect(row?.currency == "USD")
    }
}

struct SubscriptionReportTests {

    @Test func parsesActiveCounts() throws {
        let tsv = """
        App Apple ID\tSubscription Name\tSubscription Apple ID\tCountry\tStandard Subscription Duration\tDeveloper Proceeds\tProceeds Currency\tActive Standard Price Subscriptions\tActive Free Trial Introductory Offer Subscriptions\tActive Pay Up Front Introductory Offer Subscriptions\tActive Pay As You Go Introductory Offer Subscriptions
        12345\tPro Monthly\t555\tUS\t1 Month\t6.99\tUSD\t100\t10\t0\t0
        """
        let row = try #require(SubscriptionReport.parseRows(tsv: tsv).first)
        #expect(row.activeStandard == 100)
        #expect(row.activeTrial == 10)
        #expect(row.paidActive == 100)          // standard + intro
        #expect(row.totalActive == 110)         // + trials
        #expect(abs(row.durationMonths - 1) < 0.0001)
        #expect(abs(row.monthlyProceeds - 6.99) < 0.0001)
    }

    @Test(arguments: [
        ("1 Month", 1.0), ("1 Year", 12.0), ("6 Months", 6.0), ("3 Days", 0.1),
    ])
    func durationToMonths(_ input: String, _ expected: Double) {
        #expect(abs(SubscriptionReport.durationToMonths(input) - expected) < 0.001)
    }

    @Test func weeklyDurationIsFractionalMonth() {
        #expect(abs(SubscriptionReport.durationToMonths("1 Week") - 0.230137) < 0.0001)
    }

    @Test func eventCategoriesNormalised() {
        let tsv = """
        Event\tQuantity\tApp Apple ID\tCountry
        Subscribe\t5\t12345\tUS
        Cancel\t2\t12345\tUS
        Renew\t20\t12345\tUS
        Refund\t1\t12345\tUS
        """
        let rows = SubscriptionReport.parseEvents(tsv: tsv)
        let byCategory = Dictionary(grouping: rows, by: \.category).mapValues { $0.reduce(0) { $0 + $1.quantity } }
        #expect(byCategory["New"] == 5)
        #expect(byCategory["Cancelled"] == 2)
        #expect(byCategory["Renewals"] == 20)
        #expect(byCategory["Refunds"] == 1)
    }
}

@MainActor
struct StoreProviderTests {

    @Test func demoAccountsAreRecognizedForEitherStore() {
        let apple = Account(name: "Apple demo", issuerID: Account.demoMarker, keyID: "DEMO")
        let google = Account(name: "Google demo", issuerID: "", keyID: "DEMO",
                             platform: .googlePlay, externalAccountID: Account.demoMarker)
        let real = Account(name: "Real", issuerID: "issuer", keyID: "key")

        #expect(apple.isDemo)
        #expect(google.isDemo)
        #expect(!real.isDemo)
    }

    @Test func demoSeederCreatesStableRepresentativeData() throws {
        let schema = Schema([Account.self, TrackedApp.self, Review.self, MetricPoint.self,
                             StatusEvent.self, MetadataSnapshot.self, MetadataChange.self,
                             ChartAnnotation.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let account = Account(name: "Demo", issuerID: Account.demoMarker, keyID: "DEMO",
                              vendorNumber: "DEMO")
        context.insert(account)

        try DemoDataSeeder.seed(account: account, context: context)

        #expect(account.apps.count == 2)
        #expect(account.lastSyncedAt != nil)
        #expect(account.lastSyncError == nil)
        #expect(try context.fetchCount(FetchDescriptor<Review>()) == 8)
        #expect(try context.fetchCount(FetchDescriptor<MetricPoint>()) == 1_260)
        #expect(try context.fetch(FetchDescriptor<MetricPoint>()).contains { $0.kind == .proceeds })

        try DemoDataSeeder.seed(account: account, context: context)
        #expect(account.apps.count == 2)
        #expect(try context.fetchCount(FetchDescriptor<Review>()) == 8)
    }

    @Test func archivingDisablesTrackingWithoutDeletingTheApp() {
        let app = TrackedApp(appStoreID: "123", bundleID: "com.example.app", name: "Example")

        #expect(!app.isArchived)
        #expect(app.isTracked)

        app.isArchived = true
        #expect(app.isArchived)
        #expect(!app.isTracked)

        app.isArchived = false
        #expect(!app.isArchived)
        #expect(app.isTracked)
    }

    @Test func providerCapabilitiesDescribeCurrentAndPlannedConnectors() {
        let apple = StoreProviderRegistry.definition(for: .appleAppStore)
        let google = StoreProviderRegistry.definition(for: .googlePlay)

        #expect(apple.isConnectorAvailable)
        #expect(apple.capabilities.contains(.phasedReleases))
        #expect(apple.capabilities.contains(.builds))
        #expect(google.isConnectorAvailable)
        #expect(google.capabilities.contains(.reviews))
        #expect(google.capabilities.contains(.reviewResponses))
        #expect(google.capabilities.contains(.releaseStatus))
        #expect(google.capabilities.contains(.analytics))
        #expect(google.capabilities.contains(.vitals))
        #expect(!google.capabilities.contains(.phasedReleases))
        #expect(!google.capabilities.contains(.betaTesting))
        #expect(!google.capabilities.contains(.sales))
        #expect(google.capabilities.contains(.grossSales))
        #expect(google.capabilities.contains(.earnings))
        #expect(!google.capabilities.contains(.responseDeletion))
    }

    @Test func identicalRemoteIDsRemainDistinctAcrossStores() {
        let appleAccount = Account(name: "Apple", issuerID: "issuer", keyID: "key")
        let googleAccount = Account(name: "Google", issuerID: "", keyID: "", platform: .googlePlay)
        let appleApp = TrackedApp(appStoreID: "same-id", bundleID: "com.example.app", name: "Example",
                                  account: appleAccount)
        let googleApp = TrackedApp(appStoreID: "same-id", bundleID: "com.example.app", name: "Example",
                                   account: googleAccount)

        #expect(appleApp.remoteIdentifier == googleApp.remoteIdentifier)
        #expect(appleApp.platform == .appleAppStore)
        #expect(googleApp.platform == .googlePlay)
        #expect(appleApp.storageIdentity != googleApp.storageIdentity)
    }

    @Test func reviewAndMetricIDsAreScopedToTheLocalApp() {
        let first = TrackedApp(appStoreID: "1", bundleID: "com.example.one", name: "One")
        let second = TrackedApp(appStoreID: "2", bundleID: "com.example.two", name: "Two")
        let firstReview = Review(id: "review-1", rating: 5, title: "Great", body: "Nice",
                                 reviewer: "A", territory: "US", createdDate: .now, app: first)
        let secondReview = Review(id: "review-1", rating: 5, title: "Great", body: "Nice",
                                  reviewer: "A", territory: "US", createdDate: .now, app: second)
        let firstMetric = MetricPoint.makeKey(app: first, kind: .units, day: .now, currency: nil)
        let secondMetric = MetricPoint.makeKey(app: second, kind: .units, day: .now, currency: nil)

        #expect(firstReview.remoteIdentifier == "review-1")
        #expect(firstReview.id != secondReview.id)
        #expect(firstMetric != secondMetric)
    }

    @Test func reviewTranslationCacheIsScopedToItsTargetLanguage() {
        let review = Review(id: "review-translation", rating: 4, title: "Sehr gut",
                            body: "Die App ist hilfreich.", reviewer: "A", territory: "DE",
                            createdDate: .now)
        review.translatedTitle = "Very good"
        review.translatedBody = "The app is helpful."
        review.translationSourceLanguage = "de"
        review.translationTargetLanguage = "en"

        #expect(review.hasTranslation(to: Locale.Language(identifier: "en-US")))
        #expect(!review.hasTranslation(to: Locale.Language(identifier: "fr")))

        review.clearTranslation()
        #expect(review.translatedBody == nil)
        #expect(review.translationTargetLanguage == nil)
        #expect(!review.hasTranslation(to: Locale.Language(identifier: "en")))
    }
}

struct GoogleFinancialReportTests {

    @Test func estimatedSalesUseHeadersAndSignRefunds() throws {
        let csv = """
        Extra,Charged Amount,Currency of Sale,Financial Status,Package ID,Order Charged Date
        ignored,"12,345.67",USD,charged,com.example.app,2026-07-10
        ignored,4.50,USD,partial refund,com.example.app,2026-07-11
        """
        let rows = try GoogleFinancialReportParser.estimatedSales(data: Data(csv.utf8))

        #expect(rows.count == 2)
        #expect(rows[0].packageID == "com.example.app")
        #expect(abs(rows[0].grossAmount - 12_345.67) < 0.001)
        #expect(rows[0].orderDelta == 1)
        #expect(rows[1].grossAmount == -4.5)
        #expect(rows[1].orderDelta == 0) // a partial refund does not remove the order
    }

    @Test func earningsNormalizeChargesFeesTaxesAndRefunds() throws {
        let csv = """
        Package ID,Transaction Type,Amount (Merchant Currency),Merchant Currency,Transaction Date,Future Column
        com.example.app,Charge,10.00,EUR,"Jul 1, 2026",x
        com.example.app,Google fee,1.00,EUR,"Jul 1, 2026",x
        com.example.app,Tax,2.00,EUR,"Jul 1, 2026",x
        com.example.app,Charge refund,4.00,EUR,"Jul 2, 2026",x
        com.example.app,Google fee refund,0.40,EUR,"Jul 2, 2026",x
        """
        let rows = try GoogleFinancialReportParser.earnings(data: Data(csv.utf8))

        #expect(rows.count == 5)
        #expect(abs(rows.reduce(0) { $0 + $1.netAmount } - 3.4) < 0.001)
        #expect(Set(rows.map(\.merchantCurrency)) == ["EUR"])
    }

    @Test func readsUTF16CSVAndEscapedQuotes() throws {
        let csv = """
        Order Charged Date,Package ID,Financial Status,Currency of Sale,Charged Amount,Product Title
        2026-07-10,com.example.app,charged,USD,2.99,"A ""quoted"", title"
        """
        var encoded = Data([0xff, 0xfe])
        encoded.append(try #require(csv.data(using: .utf16LittleEndian)))

        let rows = try GoogleFinancialReportParser.estimatedSales(data: encoded)
        #expect(rows.count == 1)
        #expect(rows[0].grossAmount == 2.99)
    }

    @Test func extractsStoredCSVFromZIPCentralDirectory() throws {
        let csv = Data("a,b\n1,2\n".utf8)
        let archive = storedZIP(filename: "salesreport.csv", payload: csv)
        #expect(try GoogleFinancialArchive.csvData(from: archive) == csv)
    }

    private func storedZIP(filename: String, payload: Data) -> Data {
        let name = Data(filename.utf8)
        var local = Data()
        append32(0x0403_4b50, to: &local)
        append16(20, to: &local); append16(0, to: &local); append16(0, to: &local)
        append16(0, to: &local); append16(0, to: &local); append32(0, to: &local)
        append32(UInt32(payload.count), to: &local); append32(UInt32(payload.count), to: &local)
        append16(UInt16(name.count), to: &local); append16(0, to: &local)
        local.append(name); local.append(payload)

        var central = Data()
        append32(0x0201_4b50, to: &central)
        append16(20, to: &central); append16(20, to: &central)
        append16(0, to: &central); append16(0, to: &central)
        append16(0, to: &central); append16(0, to: &central); append32(0, to: &central)
        append32(UInt32(payload.count), to: &central); append32(UInt32(payload.count), to: &central)
        append16(UInt16(name.count), to: &central); append16(0, to: &central); append16(0, to: &central)
        append16(0, to: &central); append16(0, to: &central); append32(0, to: &central)
        append32(0, to: &central); central.append(name)

        var result = local
        let centralOffset = result.count
        result.append(central)
        append32(0x0605_4b50, to: &result)
        append16(0, to: &result); append16(0, to: &result)
        append16(1, to: &result); append16(1, to: &result)
        append32(UInt32(central.count), to: &result); append32(UInt32(centralOffset), to: &result)
        append16(0, to: &result)
        return result
    }

    private func append16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xff)); data.append(UInt8((value >> 8) & 0xff))
    }

    private func append32(_ value: UInt32, to data: inout Data) {
        append16(UInt16(value & 0xffff), to: &data)
        append16(UInt16((value >> 16) & 0xffff), to: &data)
    }
}

struct GoogleStatisticsReportTests {

    @Test func installCountryRowsCanBeAggregatedIntoDailyTotals() throws {
        let csv = """
        Date,Package Name,Country,Current Device Installs,Installs on active devices,Daily Device Installs,Daily Device Uninstalls,Daily Device Upgrades,Current User Installs,Total User Installs,Daily User Installs,Daily User Uninstalls
        2026-07-10,com.example.app,US,100,90,8,1,3,80,120,7,1
        2026-07-10,com.example.app,DE,50,45,5,0,2,40,60,4,0
        """
        let rows = try GoogleStatisticsReportParser.installs(data: Data(csv.utf8))

        #expect(rows.count == 2)
        #expect(rows.reduce(0) { $0 + $1.dailyUserInstalls } == 11)
        #expect(rows.reduce(0) { $0 + $1.dailyDeviceUpgrades } == 5)
        #expect(Set(rows.map(\.packageID)) == ["com.example.app"])
    }

    @Test func readsGoogleUTF16InstallExport() throws {
        let csv = """
        Date,Package Name,Country,Daily Device Upgrades,Daily User Installs
        2026-07-11,com.example.app,US,2,9
        """
        var encoded = Data([0xff, 0xfe])
        encoded.append(try #require(csv.data(using: .utf16LittleEndian)))

        let row = try #require(GoogleStatisticsReportParser.installs(data: encoded).first)
        #expect(row.dailyUserInstalls == 9)
        #expect(row.dailyDeviceUpgrades == 2)
    }
}

struct GooglePlayResponseTests {
    private struct ReleaseList: Decodable {
        let releases: [String]?
    }

    @Test func noContentCanRepresentAnEmptyReleaseList() throws {
        let decoded = try GooglePlayResponseDecoder.decode(
            ReleaseList.self,
            from: Data(),
            emptyResponse: ReleaseList(releases: nil)
        )
        #expect(decoded.releases == nil)
    }

    @Test func preservesReviewerEmojiWhenDecodingGoogleJSON() throws {
        struct Response: Decodable {
            struct Review: Decodable {
                struct Comment: Decodable {
                    struct UserComment: Decodable { let text: String }
                    let userComment: UserComment
                }
                let comments: [Comment]
            }
            let reviews: [Review]
        }
        let json = #"{"reviews":[{"comments":[{"userComment":{"text":"Works perfectly 🙌🏽 — love it ❤️🚀"}}]}]}"#
        let response = try GooglePlayResponseDecoder.decode(Response.self, from: Data(json.utf8))

        #expect(response.reviews[0].comments[0].userComment.text == "Works perfectly 🙌🏽 — love it ❤️🚀")
    }

    @MainActor
    @Test func decodesGoogleDecimalVitalRateAndCalendarDay() throws {
        let json = #"{"rows":[{"aggregationPeriod":"DAILY","startTime":{"year":2026,"month":7,"day":10,"timeZone":{"id":"America/Los_Angeles"}},"metrics":[{"metric":"crashRate","decimalValue":{"value":"0.0125"}}]}]}"#
        let response = try JSONDecoder().decode(GooglePlayVitalRateResponse.self,
                                                from: Data(json.utf8))
        let point = try #require(response.points(metric: "crashRate").first)

        #expect(abs(point.value - 0.0125) < 0.000_001)
        #expect(DayFormatter.string(from: point.date) == "2026-07-10")
    }

    @MainActor
    @Test func usesGoogleDailyFreshnessAsTheExclusiveVitalsEndDate() throws {
        let json = #"{"freshnessInfo":{"freshnesses":[{"aggregationPeriod":"DAILY","latestEndTime":{"year":2026,"month":7,"day":18,"timeZone":{"id":"America/Los_Angeles"}}}]}}"#
        let metadata = try JSONDecoder().decode(GooglePlayVitalMetricSet.self,
                                                from: Data(json.utf8))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let end = try #require(metadata.latestDailyEndDate(calendar: calendar))

        #expect(calendar.component(.year, from: end) == 2026)
        #expect(calendar.component(.month, from: end) == 7)
        #expect(calendar.component(.day, from: end) == 18)
    }

    @MainActor
    @Test func classifiesOnlyRetryableGoogleFailuresAsTransient() {
        #expect(GooglePlayError.message("Unavailable", statusCode: 503).isTransient)
        #expect(GooglePlayError.message("Rate limited", statusCode: 429).isTransient)
        #expect(!GooglePlayError.message("Bad request", statusCode: 400).isTransient)
    }
}

struct ReviewUnicodeTests {

    @Test func preservesReviewerEmojiWhenDecodingAppStoreJSON() throws {
        let json = #"{"data":[{"type":"customerReviews","id":"review-emoji","attributes":{"rating":5,"title":"Wonderful 😊","body":"Family loves it 👨‍👩‍👧‍👦 — thank you ❤️🚀","reviewerNickname":"Maya","createdDate":"2026-07-24T10:00:00Z","territory":"USA"}}],"included":[],"links":{},"meta":{}}"#
        let response = try JSONDecoder().decode(ReviewsResponse.self, from: Data(json.utf8))
        let review = try #require(response.data.first?.attributes)

        #expect(review.title == "Wonderful 😊")
        #expect(review.body == "Family loves it 👨‍👩‍👧‍👦 — thank you ❤️🚀")
    }

    @MainActor
    @Test func preservesReviewerEmojiThroughLocalPersistence() throws {
        let schema = Schema([Review.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let expected = "So useful 🙌🏽 — fixed my workflow 👩🏾‍💻❤️"
        context.insert(Review(
            id: "review-emoji",
            rating: 5,
            title: "Fantastic 🚀",
            body: expected,
            reviewer: "Maya",
            territory: "US",
            createdDate: .now
        ))
        try context.save()

        let stored = try #require(context.fetch(FetchDescriptor<Review>()).first)
        #expect(stored.body == expected)
        #expect(stored.title == "Fantastic 🚀")
    }
}

struct GoogleServiceAccountTests {

    @Test func decodesDownloadedCredentialShape() throws {
        let json = #"{"type":"service_account","project_id":"example-project","private_key_id":"key-1","private_key":"-----BEGIN PRIVATE KEY-----\nAA==\n-----END PRIVATE KEY-----\n","client_email":"storegauge@example-project.iam.gserviceaccount.com","client_id":"123","token_uri":"https://oauth2.googleapis.com/token"}"#
        let credentials = try GoogleServiceAccountCredentials.decode(json: json)

        #expect(credentials.projectID == "example-project")
        #expect(credentials.privateKeyID == "key-1")
        #expect(credentials.clientEmail == "storegauge@example-project.iam.gserviceaccount.com")
        #expect(credentials.tokenEndpoint.absoluteString == "https://oauth2.googleapis.com/token")
    }

    @Test func unwrapsPKCS8PrivateKeyPayload() throws {
        let wrapped = Data([0x30, 0x0e,
                            0x02, 0x01, 0x00,
                            0x30, 0x05, 0x06, 0x03, 0x2a, 0x03, 0x04,
                            0x04, 0x02, 0x30, 0x00])
        #expect(try GoogleRSA.unwrapPKCS8(wrapped) == Data([0x30, 0x00]))
    }

    @Test func signsAVerifiableRS256Assertion() throws {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2_048,
        ]
        var creationError: Unmanaged<CFError>?
        let privateKey = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, &creationError))
        var exportError: Unmanaged<CFError>?
        let keyData = try #require(SecKeyCopyExternalRepresentation(privateKey, &exportError) as Data?)
        let pemBody = keyData.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        let pem = "-----BEGIN RSA PRIVATE KEY-----\n\(pemBody)\n-----END RSA PRIVATE KEY-----\n"
        let credentials = GoogleServiceAccountCredentials(
            type: "service_account",
            projectID: "example-project",
            privateKeyID: "key-1",
            privateKey: pem,
            clientEmail: "storegauge@example-project.iam.gserviceaccount.com",
            clientID: nil,
            tokenURI: nil
        )

        let assertion = try GoogleServiceAccountJWT.assertion(
            credentials: credentials,
            scopes: [GoogleOAuthScope.androidPublisher],
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let pieces = assertion.split(separator: ".")
        #expect(pieces.count == 3)
        let signingInput = pieces.prefix(2).joined(separator: ".")
        let signature = try #require(base64URLData(String(pieces[2])))
        let publicKey = try #require(SecKeyCopyPublicKey(privateKey))
        var verificationError: Unmanaged<CFError>?

        #expect(SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            Data(signingInput.utf8) as CFData,
            signature as CFData,
            &verificationError
        ))
    }

    private func base64URLData(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}

struct AccountFieldValidationTests {

    @Test func validatesAppleAccountFieldFormats() throws {
        #expect(AccountFieldValidation.isValidIssuerID("01234567-89ab-cdef-0123-456789abcdef"))
        #expect(!AccountFieldValidation.isValidIssuerID("01234567-89ab-cdef"))
        #expect(AccountFieldValidation.isValidKeyID("AB12CD34EF"))
        #expect(!AccountFieldValidation.isValidKeyID("AB12-CD34EF"))
        #expect(AccountFieldValidation.isValidVendorNumber(""))
        #expect(AccountFieldValidation.isValidVendorNumber("00123456"))
        #expect(!AccountFieldValidation.isValidVendorNumber("12 345"))

        try AccountFieldValidation.validateApple(
            issuerID: "01234567-89ab-cdef-0123-456789abcdef",
            keyID: "ab12cd34ef",
            vendorNumber: "00123456"
        )
        #expect(AccountFieldValidation.normalizedKeyID(" ab12cd34ef ") == "AB12CD34EF")
    }

    @Test func validatesAndNormalizesGoogleReportBuckets() throws {
        #expect(AccountFieldValidation.isValidGoogleReportBucket(""))
        #expect(AccountFieldValidation.isValidGoogleReportBucket("pubsite_prod_rev_0123456789"))
        #expect(AccountFieldValidation.isValidGoogleReportBucket("gs://pubsite_prod_rev_0123456789/stats/"))
        #expect(!AccountFieldValidation.isValidGoogleReportBucket("some-other-bucket"))
        #expect(!AccountFieldValidation.isValidGoogleReportBucket("pubsite_prod_rev_account"))
        #expect(
            try AccountFieldValidation.normalizeGoogleReportBucket(
                "gs://pubsite_prod_rev_0123456789/stats/"
            ) == "pubsite_prod_rev_0123456789"
        )
    }
}

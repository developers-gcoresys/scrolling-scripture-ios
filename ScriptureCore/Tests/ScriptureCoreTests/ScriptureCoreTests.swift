import XCTest
@testable import ScriptureCore

final class ScriptureModelsTests: XCTestCase {
    private let editionJSON = """
    {
      "translation": "Test Edition",
      "abbreviation": "TST",
      "source": "https://example.org",
      "sourceUpdated": "2026-01-01",
      "books": [
        {
          "id": "GEN",
          "name": "Genesis",
          "chapters": [
            {
              "number": 1,
              "verses": [
                { "number": "1", "text": "In the beginning|strong=\\"H1234\\" God created the heavens." },
                { "number": "2", "text": "The earth was formless and empty." }
              ]
            },
            {
              "number": 2,
              "verses": [
                { "number": "1", "text": "Thus the heavens and the earth were finished." }
              ]
            }
          ]
        },
        {
          "id": "PSA",
          "name": "Psalms",
          "chapters": [
            {
              "number": 23,
              "verses": [
                { "number": "1", "text": "Yahweh is my shepherd; I shall lack nothing." }
              ]
            }
          ]
        }
      ]
    }
    """.data(using: .utf8)!

    func testLoadsEditionAndCleansInlineMarkup() throws {
        let edition = try ScriptureLibrary.load(data: editionJSON)
        XCTAssertEqual(edition.translation, "Test Edition")
        XCTAssertEqual(edition.books.count, 2)
        XCTAssertEqual(edition.books[0].chapters.count, 2)
        XCTAssertEqual(edition.books[0].chapters[0].verses[0].text, "In the beginning God created the heavens.")
        XCTAssertFalse(edition.books[0].chapters[0].verses[0].text.contains("strong"))
    }

    func testRejectsEmptyEdition() {
        let empty = #"{"translation":"x","abbreviation":"x","source":"x","sourceUpdated":"x","books":[]}"#.data(using: .utf8)!
        XCTAssertThrowsError(try ScriptureLibrary.load(data: empty)) { error in
            XCTAssertEqual(error as? ScriptureLibraryError, .emptyEdition)
        }
    }

    func testNavigatorMovesAcrossChaptersAndBooks() throws {
        let edition = try ScriptureLibrary.load(data: editionJSON)
        let start = VerseLocation(bookIndex: 0, chapterIndex: 0, verseIndex: 1)
        XCTAssertEqual(ScriptureNavigator.reference(in: edition, location: start), "Genesis 1:2")

        let next = ScriptureNavigator.nextChapter(in: edition, from: start)
        XCTAssertEqual(next, VerseLocation(bookIndex: 0, chapterIndex: 1, verseIndex: 0))
        let nextBook = ScriptureNavigator.nextChapter(in: edition, from: next!)
        XCTAssertEqual(nextBook, VerseLocation(bookIndex: 1, chapterIndex: 0, verseIndex: 0))
        XCTAssertNil(ScriptureNavigator.nextChapter(in: edition, from: nextBook!))
    }

    func testSearchMatchesReferenceAndTextIgnoringCase() throws {
        let edition = try ScriptureLibrary.load(data: editionJSON)
        XCTAssertEqual(ScriptureSearch.search("psalm", in: edition).first?.reference, "Psalms 23:1")
        let results = ScriptureSearch.search("SHEPHERD", in: edition)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].location, VerseLocation(bookIndex: 1, chapterIndex: 0, verseIndex: 0))
        XCTAssertTrue(ScriptureSearch.search("x", in: edition).isEmpty)
    }
}

final class ProAndAdsTests: XCTestCase {
    func testAdPolicyRequiresInteractionCooldownAndSessionCap() {
        var session = AdSession(swipesPerAd: 12, cooldown: 300, maxAdsPerSession: 2)
        let start = Date(timeIntervalSince1970: 1_000_000)

        for _ in 0..<11 {
            XCTAssertFalse(session.recordPageChange(at: start))
        }
        XCTAssertTrue(session.recordPageChange(at: start))
        session.markAdShown(at: start)
        XCTAssertEqual(session.adsShown, 1)

        for _ in 0..<11 {
            XCTAssertFalse(session.recordPageChange(at: start.addingTimeInterval(60)))
        }
        // Cooldown has not elapsed.
        XCTAssertFalse(session.recordPageChange(at: start.addingTimeInterval(60)))

        for _ in 0..<12 {
            _ = session.recordPageChange(at: start.addingTimeInterval(301))
        }
        XCTAssertTrue(session.recordPageChange(at: start.addingTimeInterval(302)))
        session.markAdShown(at: start.addingTimeInterval(302))
        XCTAssertEqual(session.adsShown, 2)

        for _ in 0..<50 {
            XCTAssertFalse(session.recordPageChange(at: start.addingTimeInterval(10_000)))
        }
        XCTAssertEqual(session.adsRemaining, 0)
    }

    func testEntitlementDecodesFractionalISO8601AndChecksExpiry() throws {
        let json = """
        {"appId":"bible","isPro":true,"status":"active","productId":"pro_monthly",
         "expiresAt":"2027-01-09T12:00:00.000Z","willRenew":true}
        """.data(using: .utf8)!
        let entitlement = try ProEntitlement.decode(from: json)
        XCTAssertTrue(entitlement.isPro)
        XCTAssertEqual(entitlement.productId, "pro_monthly")
        XCTAssertTrue(entitlement.isActivePro(at: Date(timeIntervalSince1970: 1_780_000_000)))
        XCTAssertFalse(entitlement.isActivePro(at: Date(timeIntervalSince1970: 1_900_000_000)))
    }

    func testEntitlementWithoutExpiryIsNotPro() {
        let entitlement = ProEntitlement(appId: "bible", isPro: true, status: "active", productId: nil, expiresAt: nil, willRenew: false)
        XCTAssertFalse(entitlement.isActivePro())
    }
}

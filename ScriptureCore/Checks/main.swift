import Foundation
import ScriptureCore

// Lightweight checks for environments with Command Line Tools only (no XCTest).
// Run with `swift run CoreChecks`. Xcode users can run `swift test` instead.

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

let editionJSON = """
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
        { "number": 1, "verses": [
          { "number": "1", "text": "In the beginning|strong=\\"H1234\\" God created the heavens." },
          { "number": "2", "text": "The earth was formless and empty." }
        ]},
        { "number": 2, "verses": [
          { "number": "1", "text": "Thus the heavens and the earth were finished." }
        ]}
      ]
    },
    {
      "id": "PSA",
      "name": "Psalms",
      "chapters": [
        { "number": 23, "verses": [
          { "number": "1", "text": "Yahweh is my shepherd; I shall lack nothing." }
        ]}
      ]
    }
  ]
}
""".data(using: .utf8)!

let edition = try ScriptureLibrary.load(data: editionJSON)
expect(edition.books.count == 2, "edition should have two books")
expect(edition.books[0].chapters[0].verses[0].text == "In the beginning God created the heavens.", "Strong's markup should be removed")
expect(ScriptureNavigator.reference(in: edition, location: VerseLocation(bookIndex: 0, chapterIndex: 1, verseIndex: 0)) == "Genesis 2:1", "reference")
expect(ScriptureSearch.search("psalm", in: edition).first?.reference == "Psalms 23:1", "search by book name")
expect(ScriptureSearch.search("SHEPHERD", in: edition).count == 1, "search should be case-insensitive")

var session = AdSession(swipesPerAd: 12, cooldown: 300, maxAdsPerSession: 2)
let start = Date(timeIntervalSince1970: 1_000_000)
for _ in 0..<11 { expect(!session.recordPageChange(at: start), "ad should not be due early") }
expect(session.recordPageChange(at: start), "ad should be due at 12 interactions")
session.markAdShown(at: start)
for _ in 0..<12 { _ = session.recordPageChange(at: start.addingTimeInterval(60)) }
expect(!session.recordPageChange(at: start.addingTimeInterval(60)), "cooldown should block")
for _ in 0..<12 { _ = session.recordPageChange(at: start.addingTimeInterval(301)) }
expect(session.recordPageChange(at: start.addingTimeInterval(302)), "second ad should be due after cooldown")
session.markAdShown(at: start.addingTimeInterval(302))
for _ in 0..<50 { expect(!session.recordPageChange(at: start.addingTimeInterval(10_000)), "session cap") }

let entitlementJSON = """
{"appId":"bible","isPro":true,"status":"active","productId":"pro_monthly",
 "expiresAt":"2027-01-09T12:00:00.000Z","willRenew":true}
""".data(using: .utf8)!
let entitlement = try ProEntitlement.decode(from: entitlementJSON)
expect(entitlement.isActivePro(at: Date(timeIntervalSince1970: 1_780_000_000)), "entitlement should be active before expiry")
expect(!entitlement.isActivePro(at: Date(timeIntervalSince1970: 1_900_000_000)), "entitlement should expire")

// Offline explanation pack round-trip in a temporary directory.
let packDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("scripture-core-pack-\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: packDirectory) }
let packItems = [
    OfflineExplanation(reference: "John 3:16", explanation: "A concise explanation.", citations: ["John 3:14-15"]),
    OfflineExplanation(reference: "Psalm 23:1", explanation: "Another explanation.", citations: [])
]
try OfflineExplanationStore.save(packItems, appId: "bible", packVersion: 3, directory: packDirectory)
expect(OfflineExplanationStore.version(directory: packDirectory) == 3, "pack version should round-trip")
expect(OfflineExplanationStore.load(directory: packDirectory) == packItems, "pack items should round-trip")
OfflineExplanationStore.clear(directory: packDirectory)
expect(OfflineExplanationStore.load(directory: packDirectory).isEmpty, "cleared pack should be empty")
expect(OfflineExplanationStore.version(directory: packDirectory) == nil, "cleared pack should have no version")

// Guard against a truncated or silently drifted bundled edition. If this check
// fails after an intentional content update, review the text and update counts.
let bundledEditionURL = URL(fileURLWithPath: "../App/Resources/world_english_bible.json")
if FileManager.default.fileExists(atPath: bundledEditionURL.path) {
    let bundled = try ScriptureLibrary.load(contentsOf: bundledEditionURL)
    expect(bundled.books.count == 66, "bundled edition should have 66 books")
    expect(bundled.books.first?.name == "Genesis", "bundled edition should start with Genesis")
    expect(bundled.books.last?.name == "Revelation", "bundled edition should end with Revelation")
    let chapters = bundled.books.reduce(0) { $0 + $1.chapters.count }
    let verses = bundled.books.reduce(0) { total, book in
        total + book.chapters.reduce(0) { $0 + $1.verses.count }
    }
    expect(chapters == 1189, "bundled edition should have 1189 chapters")
    expect(verses == 31103, "bundled edition should have 31103 verses")
    expect(!bundled.books.contains { $0.chapters.contains { $0.verses.contains { $0.text.contains("|strong=") } } }, "inline Strong's markup should be removed")
} else {
    print("Skipping bundled-edition check: run from ScriptureCore/ with App/Resources present.")
}

print("ScriptureCore checks passed")

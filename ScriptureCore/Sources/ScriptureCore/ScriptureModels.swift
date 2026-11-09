import Foundation

public struct ReaderVerse: Codable, Hashable, Identifiable, Sendable {
    public let number: String
    public let text: String

    public var id: String { number }

    public init(number: String, text: String) {
        self.number = number
        self.text = text
    }
}

public struct ReaderChapter: Codable, Hashable, Identifiable, Sendable {
    public let number: Int
    public let verses: [ReaderVerse]

    public var id: Int { number }

    public init(number: Int, verses: [ReaderVerse]) {
        self.number = number
        self.verses = verses
    }
}

public struct ReaderBook: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let chapters: [ReaderChapter]

    public init(id: String, name: String, chapters: [ReaderChapter]) {
        self.id = id
        self.name = name
        self.chapters = chapters
    }
}

public struct ScriptureEdition: Codable, Hashable, Sendable {
    public let translation: String
    public let abbreviation: String
    public let source: String
    public let sourceUpdated: String
    public let books: [ReaderBook]

    public init(translation: String, abbreviation: String, source: String, sourceUpdated: String, books: [ReaderBook]) {
        self.translation = translation
        self.abbreviation = abbreviation
        self.source = source
        self.sourceUpdated = sourceUpdated
        self.books = books
    }
}

public enum ScriptureLibraryError: Error, Equatable {
    case emptyEdition
    case malformedEdition
}

public enum ScriptureLibrary {
    private static let strongTag = try! NSRegularExpression(pattern: #"\|strong="[HG]\d+""#)
    private static let spacingBeforePunctuation = try! NSRegularExpression(pattern: #"\s+([,.;:!?])"#)
    private static let spacingAfterOpeningQuote = try! NSRegularExpression(pattern: #"([“‘])\s+"#)
    private static let spacingBeforeClosingQuote = try! NSRegularExpression(pattern: #"\s+([’'])"#)
    private static let spacingAfterApostrophe = try! NSRegularExpression(pattern: #"([’'])\s+(?=[A-Za-z])"#)
    private static let repeatedWhitespace = try! NSRegularExpression(pattern: #"\s+"#)

    /// Removes inline Strong's-number markup that leaked into some public-domain
    /// source editions and normalizes spacing around punctuation.
    public static func cleanInlineStudyMarkup(_ text: String) -> String {
        guard text.contains("|strong=") else { return text }
        var result = text
        func replace(_ regex: NSRegularExpression, with template: String) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: template)
        }
        replace(strongTag, with: "")
        replace(spacingBeforePunctuation, with: "$1")
        replace(spacingAfterOpeningQuote, with: "$1")
        replace(spacingBeforeClosingQuote, with: "$1")
        replace(spacingAfterApostrophe, with: "$1")
        replace(repeatedWhitespace, with: " ")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func load(data: Data) throws -> ScriptureEdition {
        guard let edition = try? JSONDecoder().decode(ScriptureEdition.self, from: data) else {
            throw ScriptureLibraryError.malformedEdition
        }
        guard !edition.books.isEmpty, edition.books.contains(where: { !$0.chapters.isEmpty }) else {
            throw ScriptureLibraryError.emptyEdition
        }
        return ScriptureEdition(
            translation: edition.translation,
            abbreviation: edition.abbreviation,
            source: edition.source,
            sourceUpdated: edition.sourceUpdated,
            books: edition.books.map { book in
                ReaderBook(
                    id: book.id,
                    name: book.name,
                    chapters: book.chapters.map { chapter in
                        ReaderChapter(
                            number: chapter.number,
                            verses: chapter.verses.map { verse in
                                ReaderVerse(number: verse.number, text: cleanInlineStudyMarkup(verse.text))
                            }
                        )
                    }
                )
            }
        )
    }

    public static func load(contentsOf url: URL) throws -> ScriptureEdition {
        try load(data: Data(contentsOf: url))
    }
}

public struct VerseLocation: Hashable, Sendable {
    public var bookIndex: Int
    public var chapterIndex: Int
    public var verseIndex: Int

    public init(bookIndex: Int, chapterIndex: Int, verseIndex: Int) {
        self.bookIndex = bookIndex
        self.chapterIndex = chapterIndex
        self.verseIndex = verseIndex
    }
}

public enum ScriptureNavigator {
    public static func reference(in edition: ScriptureEdition, location: VerseLocation) -> String? {
        guard edition.books.indices.contains(location.bookIndex) else { return nil }
        let book = edition.books[location.bookIndex]
        guard book.chapters.indices.contains(location.chapterIndex) else { return nil }
        let chapter = book.chapters[location.chapterIndex]
        guard chapter.verses.indices.contains(location.verseIndex) else { return nil }
        return "\(book.name) \(chapter.number):\(chapter.verses[location.verseIndex].number)"
    }

    public static func nextChapter(in edition: ScriptureEdition, from location: VerseLocation) -> VerseLocation? {
        guard edition.books.indices.contains(location.bookIndex) else { return nil }
        let book = edition.books[location.bookIndex]
        if book.chapters.indices.contains(location.chapterIndex + 1) {
            return VerseLocation(bookIndex: location.bookIndex, chapterIndex: location.chapterIndex + 1, verseIndex: 0)
        }
        if edition.books.indices.contains(location.bookIndex + 1) {
            return VerseLocation(bookIndex: location.bookIndex + 1, chapterIndex: 0, verseIndex: 0)
        }
        return nil
    }

    public static func previousChapter(in edition: ScriptureEdition, from location: VerseLocation) -> VerseLocation? {
        guard edition.books.indices.contains(location.bookIndex) else { return nil }
        if location.chapterIndex > 0 {
            return VerseLocation(bookIndex: location.bookIndex, chapterIndex: location.chapterIndex - 1, verseIndex: 0)
        }
        guard edition.books.indices.contains(location.bookIndex - 1) else { return nil }
        let previousBook = edition.books[location.bookIndex - 1]
        guard let lastChapter = previousBook.chapters.indices.last else { return nil }
        return VerseLocation(bookIndex: location.bookIndex - 1, chapterIndex: lastChapter, verseIndex: 0)
    }

    public static func verseKey(book: ReaderBook, chapter: ReaderChapter, verse: ReaderVerse) -> String {
        "\(book.id):\(chapter.number):\(verse.number)"
    }
}

public struct VerseSearchResult: Identifiable, Hashable, Sendable {
    public let bookIndex: Int
    public let chapterIndex: Int
    public let verseIndex: Int
    public let reference: String
    public let text: String

    public var id: String { "\(bookIndex):\(chapterIndex):\(verseIndex)" }

    public var location: VerseLocation {
        VerseLocation(bookIndex: bookIndex, chapterIndex: chapterIndex, verseIndex: verseIndex)
    }
}

public enum ScriptureSearch {
    /// Case- and diacritic-insensitive search over references and verse text.
    /// The result limit keeps the UI responsive on large editions.
    public static func search(_ query: String, in edition: ScriptureEdition, limit: Int = 300) -> [VerseSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var results: [VerseSearchResult] = []

        for (bookIndex, book) in edition.books.enumerated() {
            for (chapterIndex, chapter) in book.chapters.enumerated() {
                for (verseIndex, verse) in chapter.verses.enumerated() {
                    let reference = "\(book.name) \(chapter.number):\(verse.number)"
                    guard reference.range(of: trimmed, options: options) != nil || verse.text.range(of: trimmed, options: options) != nil else {
                        continue
                    }
                    results.append(
                        VerseSearchResult(
                            bookIndex: bookIndex,
                            chapterIndex: chapterIndex,
                            verseIndex: verseIndex,
                            reference: reference,
                            text: verse.text
                        )
                    )
                    if results.count >= limit { return results }
                }
            }
        }
        return results
    }
}

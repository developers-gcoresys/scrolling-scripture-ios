import Foundation
import SwiftUI
import ScriptureCore

enum ReaderTheme: String, CaseIterable, Identifiable {
    case parchment
    case midnight
    case forest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .parchment: return "Parchment"
        case .midnight: return "Midnight"
        case .forest: return "Forest"
        }
    }

    var background: Color {
        switch self {
        case .parchment: return Color(red: 0.97, green: 0.95, blue: 0.90)
        case .midnight: return Color(red: 0.06, green: 0.09, blue: 0.12)
        case .forest: return Color(red: 0.11, green: 0.16, blue: 0.11)
        }
    }

    var foreground: Color {
        switch self {
        case .parchment: return Color(red: 0.14, green: 0.20, blue: 0.17)
        case .midnight: return Color(red: 0.94, green: 0.93, blue: 0.89)
        case .forest: return Color(red: 0.85, green: 0.91, blue: 0.81)
        }
    }

    var secondary: Color {
        switch self {
        case .parchment: return Color(red: 0.42, green: 0.47, blue: 0.43)
        case .midnight: return Color(red: 0.62, green: 0.68, blue: 0.70)
        case .forest: return Color(red: 0.60, green: 0.68, blue: 0.57)
        }
    }
}

@MainActor
final class ReaderModel: ObservableObject {
    static let editionAsset = "world_english_bible"
    static let appId = "bible"

    @Published private(set) var edition: ScriptureEdition?
    @Published private(set) var loadError: String?
    @Published var location = VerseLocation(bookIndex: 0, chapterIndex: 0, verseIndex: 0)
    @Published var scrollVerseID: String?
    @Published var theme: ReaderTheme = .parchment {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }
    @Published var fontSize: Double = 25 {
        didSet { defaults.set(fontSize, forKey: Keys.fontSize) }
    }
    @Published var favorites: Set<String> = [] {
        didSet { defaults.set(Array(favorites), forKey: Keys.favorites) }
    }
    @Published var notes: [String: String] = [:] {
        didSet { defaults.set(notes, forKey: Keys.notes) }
    }
    @Published var showingBookPicker = false
    @Published var showingSearch = false
    @Published var showingFavorites = false
    @Published var showingSettings = false
    @Published var editingNoteFor: VerseSnapshot?

    let pro: ProManager
    let ads: AdsManager
    private let defaults = UserDefaults.standard
    private var adSession = AdSession()
    private var started = false

    init(pro: ProManager, ads: AdsManager) {
        self.pro = pro
        self.ads = ads
        loadSettings()
        loadEdition()
    }

    var books: [ReaderBook] { edition?.books ?? [] }
    var currentBook: ReaderBook? { books.indices.contains(location.bookIndex) ? books[location.bookIndex] : nil }
    var currentChapter: ReaderChapter? {
        guard let currentBook, currentBook.chapters.indices.contains(location.chapterIndex) else { return nil }
        return currentBook.chapters[location.chapterIndex]
    }
    var verses: [ReaderVerse] { currentChapter?.verses ?? [] }
    var currentVerse: ReaderVerse? {
        guard verses.indices.contains(location.verseIndex) else { return verses.first }
        return verses[location.verseIndex]
    }
    var currentReference: String? {
        guard let edition else { return nil }
        return ScriptureNavigator.reference(in: edition, location: location)
    }
    var chapterLabel: String {
        guard let book = currentBook, let chapter = currentChapter else { return "" }
        return "\(book.name) \(chapter.number)"
    }
    var translationLabel: String { edition?.translation ?? "Scripture" }

    func start() {
        guard !started else { return }
        started = true
        pro.start()
        ads.start()
        if scrollVerseID == nil { reveal(location) }
    }

    func loadEdition() {
        guard let url = Bundle.main.url(forResource: Self.editionAsset, withExtension: "json") else {
            loadError = "The bundled edition is missing. Run tools/sync-content.sh before building."
            return
        }
        do {
            let loaded = try ScriptureLibrary.load(contentsOf: url)
            edition = loaded
            let start = savedLocation(in: loaded) ?? initialLocation(in: loaded)
            location = start
            scrollVerseID = loaded.books[safe: start.bookIndex]?.chapters[safe: start.chapterIndex]?.verses[safe: start.verseIndex]?.id
                ?? loaded.books[safe: start.bookIndex]?.chapters[safe: start.chapterIndex]?.verses.first?.id
        } catch {
            loadError = "The bundled edition could not be read."
        }
    }

    func reveal(_ target: VerseLocation) {
        guard let edition else { return }
        guard edition.books.indices.contains(target.bookIndex) else { return }
        let book = edition.books[target.bookIndex]
        guard book.chapters.indices.contains(target.chapterIndex) else { return }
        let chapter = book.chapters[target.chapterIndex]
        let verseIndex = min(max(0, target.verseIndex), max(0, chapter.verses.count - 1))
        let resolved = VerseLocation(bookIndex: target.bookIndex, chapterIndex: target.chapterIndex, verseIndex: verseIndex)
        location = resolved
        scrollVerseID = chapter.verses.indices.contains(verseIndex) ? chapter.verses[verseIndex].id : nil
        persistLocation()
    }

    func openChapter(bookIndex: Int, chapterIndex: Int) {
        reveal(VerseLocation(bookIndex: bookIndex, chapterIndex: chapterIndex, verseIndex: 0))
    }

    func openSearchResult(_ result: VerseSearchResult) {
        reveal(result.location)
        showingSearch = false
    }

    func openFavorite(key: String) {
        guard let location = location(forKey: key) else { return }
        reveal(location)
        showingFavorites = false
    }

    func nextChapter() {
        guard let edition, let next = ScriptureNavigator.nextChapter(in: edition, from: location) else { return }
        reveal(next)
    }

    func previousChapter() {
        guard let edition, let previous = ScriptureNavigator.previousChapter(in: edition, from: location) else { return }
        reveal(previous)
    }

    func randomVerse() {
        guard let edition, !edition.books.isEmpty else { return }
        let bookIndex = Int.random(in: edition.books.indices)
        let book = edition.books[bookIndex]
        guard !book.chapters.isEmpty else { return }
        let chapterIndex = Int.random(in: book.chapters.indices)
        let chapter = book.chapters[chapterIndex]
        guard !chapter.verses.isEmpty else { return }
        let verseIndex = Int.random(in: chapter.verses.indices)
        reveal(VerseLocation(bookIndex: bookIndex, chapterIndex: chapterIndex, verseIndex: verseIndex))
    }

    /// Called by the paging scroll view. Only adjacent verse changes count toward
    /// the interaction-triggered ad policy; chapter jumps do not.
    func scrollPositionChanged(to verseID: String?) {
        guard let verseID, let chapter = currentChapter,
              let verseIndex = chapter.verses.firstIndex(where: { $0.id == verseID }) else { return }
        let previous = location
        let updated = VerseLocation(bookIndex: previous.bookIndex, chapterIndex: previous.chapterIndex, verseIndex: verseIndex)
        guard updated != previous else { return }
        location = updated
        persistLocation()
        let isAdjacentPage = abs(updated.verseIndex - previous.verseIndex) == 1
        guard isAdjacentPage, !pro.isPro else { return }
        guard adSession.recordPageChange(at: Date()) else { return }
        if ads.presentInterstitialIfAvailable() {
            adSession.markAdShown(at: Date())
        }
    }

    func verseKey(_ verse: ReaderVerse) -> String? {
        guard let book = currentBook, let chapter = currentChapter else { return nil }
        return ScriptureNavigator.verseKey(book: book, chapter: chapter, verse: verse)
    }

    func isFavorite(_ verse: ReaderVerse) -> Bool {
        guard let key = verseKey(verse) else { return false }
        return favorites.contains(key)
    }

    func toggleFavorite(_ verse: ReaderVerse) {
        guard let key = verseKey(verse) else { return }
        if favorites.contains(key) { favorites.remove(key) } else { favorites.insert(key) }
    }

    func note(for verse: ReaderVerse) -> String? {
        guard let key = verseKey(verse) else { return nil }
        return notes[key]
    }

    func saveNote(_ text: String, for snapshot: VerseSnapshot) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            notes.removeValue(forKey: snapshot.key)
        } else {
            notes[snapshot.key] = String(trimmed.prefix(4000))
        }
    }

    func snapshot(_ verse: ReaderVerse) -> VerseSnapshot? {
        guard let key = verseKey(verse), let reference = currentReference else { return nil }
        return VerseSnapshot(key: key, reference: reference, text: verse.text, note: notes[key])
    }

    func search(_ query: String) -> [VerseSearchResult] {
        guard let edition else { return [] }
        return ScriptureSearch.search(query, in: edition)
    }

    var favoriteItems: [FavoriteItem] {
        guard let edition else { return [] }
        return favorites.compactMap { key in
            guard let location = location(forKey: key) else { return nil }
            let book = edition.books[location.bookIndex]
            let chapter = book.chapters[location.chapterIndex]
            guard chapter.verses.indices.contains(location.verseIndex) else { return nil }
            let verse = chapter.verses[location.verseIndex]
            return FavoriteItem(
                key: key,
                reference: "\(book.name) \(chapter.number):\(verse.number)",
                text: verse.text,
                location: location
            )
        }
        .sorted { $0.reference.localizedStandardCompare($1.reference) == .orderedAscending }
    }

    func location(forKey key: String) -> VerseLocation? {
        guard let edition else { return nil }
        let parts = key.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3,
              let bookIndex = edition.books.firstIndex(where: { $0.id == parts[0] }),
              let chapterNumber = Int(parts[1]) else { return nil }
        let book = edition.books[bookIndex]
        guard let chapterIndex = book.chapters.firstIndex(where: { $0.number == chapterNumber }) else { return nil }
        let chapter = book.chapters[chapterIndex]
        guard let verseIndex = chapter.verses.firstIndex(where: { $0.number == parts[2] }) else { return nil }
        return VerseLocation(bookIndex: bookIndex, chapterIndex: chapterIndex, verseIndex: verseIndex)
    }

    private func initialLocation(in edition: ScriptureEdition) -> VerseLocation {
        if let bookIndex = edition.books.firstIndex(where: { $0.id == "PSA" }),
           let chapterIndex = edition.books[bookIndex].chapters.firstIndex(where: { $0.number == 23 }) {
            return VerseLocation(bookIndex: bookIndex, chapterIndex: chapterIndex, verseIndex: 0)
        }
        return VerseLocation(bookIndex: 0, chapterIndex: 0, verseIndex: 0)
    }

    private func savedLocation(in edition: ScriptureEdition) -> VerseLocation? {
        guard defaults.object(forKey: Keys.bookIndex) != nil else { return nil }
        let candidate = VerseLocation(
            bookIndex: defaults.integer(forKey: Keys.bookIndex),
            chapterIndex: defaults.integer(forKey: Keys.chapterIndex),
            verseIndex: defaults.integer(forKey: Keys.verseIndex)
        )
        guard edition.books.indices.contains(candidate.bookIndex) else { return nil }
        let book = edition.books[candidate.bookIndex]
        guard book.chapters.indices.contains(candidate.chapterIndex) else { return nil }
        let chapter = book.chapters[candidate.chapterIndex]
        guard chapter.verses.indices.contains(candidate.verseIndex) else { return nil }
        return candidate
    }

    private func loadSettings() {
        if let saved = defaults.string(forKey: Keys.theme), let theme = ReaderTheme(rawValue: saved) {
            self.theme = theme
        }
        let savedSize = defaults.double(forKey: Keys.fontSize)
        if savedSize >= 18 { fontSize = savedSize }
        if let savedFavorites = defaults.stringArray(forKey: Keys.favorites) {
            favorites = Set(savedFavorites)
        }
        if let savedNotes = defaults.dictionary(forKey: Keys.notes) as? [String: String] {
            notes = savedNotes
        }
    }

    private func persistLocation() {
        defaults.set(location.bookIndex, forKey: Keys.bookIndex)
        defaults.set(location.chapterIndex, forKey: Keys.chapterIndex)
        defaults.set(location.verseIndex, forKey: Keys.verseIndex)
    }

    /// Removes device-only reader data when the user deletes their account.
    func clearLocalReaderData() {
        favorites = []
        notes = [:]
        defaults.removeObject(forKey: Keys.favorites)
        defaults.removeObject(forKey: Keys.notes)
        OfflineExplanationStore.clear()
    }

    private enum Keys {
        static let theme = "reader.theme"
        static let fontSize = "reader.fontSize"
        static let favorites = "reader.favorites"
        static let notes = "reader.notes"
        static let bookIndex = "reader.bookIndex"
        static let chapterIndex = "reader.chapterIndex"
        static let verseIndex = "reader.verseIndex"
    }
}

struct VerseSnapshot: Identifiable, Hashable {
    let key: String
    let reference: String
    let text: String
    let note: String?

    var id: String { key }
}

struct FavoriteItem: Identifiable, Hashable {
    let key: String
    let reference: String
    let text: String
    let location: VerseLocation

    var id: String { key }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

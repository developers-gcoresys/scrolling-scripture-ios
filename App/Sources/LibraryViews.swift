import SwiftUI
import ScriptureCore

struct BookPickerView: View {
    @EnvironmentObject private var model: ReaderModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.books) { book in
                NavigationLink {
                    ChapterGridView(book: book) { chapterIndex in
                        if let bookIndex = model.books.firstIndex(where: { $0.id == book.id }) {
                            model.openChapter(bookIndex: bookIndex, chapterIndex: chapterIndex)
                        }
                        dismiss()
                    }
                } label: {
                    Text(book.name)
                }
            }
            .navigationTitle("Books")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ChapterGridView: View {
    let book: ReaderBook
    let onSelect: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(book.chapters.enumerated()), id: \.element.id) { index, chapter in
                    Button {
                        onSelect(index)
                    } label: {
                        Text("\(chapter.number)")
                            .font(.body.monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle(book.name)
    }
}

struct SearchView: View {
    @EnvironmentObject private var model: ReaderModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [VerseSearchResult] = []

    var body: some View {
        NavigationStack {
            List(results) { result in
                Button {
                    model.openSearchResult(result)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.reference)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(result.text)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 2)
                }
            }
            .overlay {
                if query.count >= 2 && results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Verse or reference")
            .onChange(of: query) { _, newValue in
                results = model.search(newValue)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct FavoritesView: View {
    @EnvironmentObject private var model: ReaderModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.favoriteItems.isEmpty {
                    ContentUnavailableView(
                        "No favorites yet",
                        systemImage: "heart",
                        description: Text("Long-press a verse to add it to favorites.")
                    )
                } else {
                    List(model.favoriteItems) { item in
                        Button {
                            model.openFavorite(key: item.key)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.reference)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(item.text)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Favorites")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct NoteEditorView: View {
    @EnvironmentObject private var model: ReaderModel
    @Environment(\.dismiss) private var dismiss
    let snapshot: VerseSnapshot
    @State private var text: String

    init(snapshot: VerseSnapshot) {
        self.snapshot = snapshot
        _text = State(initialValue: snapshot.note ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(snapshot.reference)
                    .font(.headline)
                Text(snapshot.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 180)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Your note stays on this device.")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .padding()
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.saveNote(text, for: snapshot)
                        dismiss()
                    }
                }
            }
        }
    }
}

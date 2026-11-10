import SwiftUI
import ScriptureCore

struct ReaderScreen: View {
    @EnvironmentObject private var model: ReaderModel
    @EnvironmentObject private var pro: ProManager
    @EnvironmentObject private var ads: AdsManager

    var body: some View {
        VStack(spacing: 0) {
            ReaderTopBar()
            pager
            ReaderBottomBar()
            if ads.adsEnabled && !pro.isPro && ads.consentReady {
                Divider()
                BannerAdView(unitID: ads.bannerUnitID)
                    .frame(height: 50)
                    .background(model.theme.background)
            }
        }
        .background(model.theme.background.ignoresSafeArea())
        .onChange(of: pro.isPro) { _, isPro in
            ads.setEnabled(!isPro)
        }
        .task {
            ads.setEnabled(!pro.isPro)
        }
        .sheet(isPresented: $model.showingBookPicker) {
            BookPickerView().environmentObject(model)
        }
        .sheet(isPresented: $model.showingSearch) {
            SearchView().environmentObject(model)
        }
        .sheet(isPresented: $model.showingFavorites) {
            FavoritesView().environmentObject(model)
        }
        .sheet(isPresented: $model.showingSettings) {
            SettingsView()
                .environmentObject(model)
                .environmentObject(pro)
                .environmentObject(ads)
        }
        .sheet(item: $model.editingNoteFor) { snapshot in
            NoteEditorView(snapshot: snapshot).environmentObject(model)
        }
    }

    private var pager: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(model.verses) { verse in
                    VersePage(
                        verse: verse,
                        reference: reference(for: verse),
                        note: model.note(for: verse),
                        isFavorite: model.isFavorite(verse)
                    )
                    .containerRelativeFrame(.vertical)
                    .id(verse.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $model.scrollVerseID)
        .onChange(of: model.scrollVerseID) { _, newValue in
            model.scrollPositionChanged(to: newValue)
        }
    }

    private func reference(for verse: ReaderVerse) -> String {
        guard let book = model.currentBook, let chapter = model.currentChapter else { return "" }
        return "\(book.name) \(chapter.number):\(verse.number)"
    }
}

private struct ReaderTopBar: View {
    @EnvironmentObject private var model: ReaderModel

    var body: some View {
        HStack(spacing: 18) {
            Button {
                model.showingBookPicker = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.chapterLabel)
                        .font(.headline)
                        .foregroundStyle(model.theme.foreground)
                    Text(model.translationLabel)
                        .font(.caption)
                        .foregroundStyle(model.theme.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            icon("magnifyingglass", label: "Search") { model.showingSearch = true }
            icon("heart", label: "Favorites") { model.showingFavorites = true }
            icon("textformat.size", label: "Settings") { model.showingSettings = true }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(model.theme.background)
    }

    private func icon(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(model.theme.secondary)
                .frame(width: 34, height: 34)
        }
        .accessibilityLabel(label)
    }
}

private struct VersePage: View {
    @EnvironmentObject private var model: ReaderModel
    @EnvironmentObject private var pro: ProManager

    let verse: ReaderVerse
    let reference: String
    let note: String?
    let isFavorite: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verse.number)
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.theme.secondary)

            Text(verse.text)
                .font(.system(size: model.fontSize, weight: .regular, design: .serif))
                .foregroundStyle(model.theme.foreground)
                .lineSpacing(model.fontSize * 0.32)
                .fixedSize(horizontal: false, vertical: true)

            if let note, !note.isEmpty {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(model.theme.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(model.theme.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            }

            Spacer(minLength: 20)

            HStack {
                Text(reference)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(model.theme.secondary)
                Spacer()
                if isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(model.theme.secondary)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(model.theme.background)
        .contextMenu {
            Button {
                model.toggleFavorite(verse)
            } label: {
                Label(isFavorite ? "Remove favorite" : "Favorite", systemImage: isFavorite ? "heart.slash" : "heart")
            }
            Button {
                model.editingNoteFor = model.snapshot(verse)
            } label: {
                Label(note == nil ? "Add note" : "Edit note", systemImage: "square.and.pencil")
            }
            ShareLink(item: shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            if !pro.isPro {
                Button {
                    model.showingSettings = true
                } label: {
                    Label("Go Pro — remove ads", systemImage: "sparkles")
                }
            }
        }
    }

    private var shareText: String {
        "\(reference)\n\(verse.text)\n— \(model.translationLabel)"
    }
}

private struct ReaderBottomBar: View {
    @EnvironmentObject private var model: ReaderModel
    @EnvironmentObject private var pro: ProManager

    var body: some View {
        HStack(spacing: 26) {
            control("chevron.up", label: "Previous chapter") { model.previousChapter() }
            control("shuffle", label: "Random verse") { model.randomVerse() }
            control("chevron.down", label: "Next chapter") { model.nextChapter() }

            if let verse = model.currentVerse {
                ShareLink(item: "\(model.currentReference ?? "")\n\(verse.text)\n— \(model.translationLabel)") {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(model.theme.secondary)
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel("Share verse")
            }

            Spacer(minLength: 0)

            Button {
                model.showingSettings = true
            } label: {
                Text(pro.isPro ? "Pro ✓" : "Go Pro")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.theme.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(model.theme.secondary.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(model.theme.background)
    }

    private func control(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(model.theme.secondary)
                .frame(width: 34, height: 34)
        }
        .accessibilityLabel(label)
    }
}

import SwiftUI
import WidgetKit

private struct DailyVerse: Codable {
    let reference: String
    let text: String
}

private struct DailyVerseFile: Codable {
    let verses: [DailyVerse]
}

private enum WidgetContent {
    static let verses: [DailyVerse] = {
        guard let url = Bundle.main.url(forResource: "widget_verses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(DailyVerseFile.self, from: data) else {
            return []
        }
        return file.verses
    }()

    static func verse(for date: Date) -> DailyVerse? {
        guard !verses.isEmpty else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let days = Int(calendar.startOfDay(for: date).timeIntervalSinceReferenceDate / 86_400)
        let index = ((days % verses.count) + verses.count) % verses.count
        return verses[index]
    }
}

struct ScriptureEntry: TimelineEntry {
    let date: Date
    let reference: String
    let text: String
}

struct ScriptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScriptureEntry {
        ScriptureEntry(
            date: Date(),
            reference: "John 3:16",
            text: "For God so loved the world, that he gave his one and only Son…"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ScriptureEntry) -> Void) {
        completion(entry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScriptureEntry>) -> Void) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let entries = (0..<7).compactMap { offset -> ScriptureEntry? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return entry(for: day)
        }
        completion(Timeline(entries: entries.isEmpty ? [entry(for: Date())] : entries, policy: .atEnd))
    }

    private func entry(for date: Date) -> ScriptureEntry {
        guard let verse = WidgetContent.verse(for: date) else {
            return ScriptureEntry(date: date, reference: "Scrolling Bible", text: "Open the app to read today's verse.")
        }
        return ScriptureEntry(date: date, reference: verse.reference, text: verse.text)
    }
}

struct ScriptureWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScriptureEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.reference)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(red: 0.36, green: 0.43, blue: 0.39))
            Text(entry.text)
                .font(.system(size: family == .systemSmall ? 14 : 17, design: .serif))
                .lineLimit(family == .systemSmall ? 6 : 5)
                .minimumScaleFactor(0.75)
                .foregroundStyle(Color(red: 0.15, green: 0.21, blue: 0.18))
            Spacer(minLength: 0)
            Text("Scrolling Bible")
                .font(.caption2)
                .foregroundStyle(Color(red: 0.36, green: 0.43, blue: 0.39).opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            Color(red: 0.97, green: 0.96, blue: 0.93)
        }
    }
}

@main
struct ScriptureWidget: Widget {
    let kind = "ScriptureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScriptureProvider()) { entry in
            ScriptureWidgetView(entry: entry)
        }
        .configurationDisplayName("Verse of the day")
        .description("A scripture verse that changes each day.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

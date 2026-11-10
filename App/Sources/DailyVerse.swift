import Foundation
import UserNotifications

struct DailyVerseItem: Codable, Equatable {
    let reference: String
    let text: String
}

private struct DailyVerseFile: Codable {
    let verses: [DailyVerseItem]
}

/// The same small rotation used by the home-screen widget, so the notification
/// and widget show the same verse on the same day.
enum DailyVerseSource {
    static func load() -> [DailyVerseItem] {
        guard let url = Bundle.main.url(forResource: "widget_verses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(DailyVerseFile.self, from: data) else {
            return []
        }
        return file.verses
    }

    static func verse(on date: Date, from verses: [DailyVerseItem]) -> DailyVerseItem? {
        guard !verses.isEmpty else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let days = Int(calendar.startOfDay(for: date).timeIntervalSinceReferenceDate / 86_400)
        let index = ((days % verses.count) + verses.count) % verses.count
        return verses[index]
    }
}

/// Schedules 30 days of 8:00 notifications. Each launch refreshes the window so
/// the rotation never runs out; disabling removes all pending requests.
enum DailyVerseNotifier {
    static let defaultsKey = "reader.dailyVerseNotification"
    private static let identifierPrefix = "daily-verse-"
    private static let daysAhead = 30

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    /// Returns false when the user declines the system permission.
    static func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else { return false }
            UserDefaults.standard.set(true, forKey: defaultsKey)
            await schedule()
            return true
        } catch {
            return false
        }
    }

    static func disable() async {
        UserDefaults.standard.set(false, forKey: defaultsKey)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    static func refreshIfEnabled() async {
        guard isEnabled else { return }
        await schedule()
    }

    private static var identifiers: [String] {
        (0..<daysAhead).map { "\(identifierPrefix)\($0)" }
    }

    private static func schedule() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        let verses = DailyVerseSource.load()
        guard !verses.isEmpty else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fireDate = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day),
                  fireDate > Date(),
                  let verse = DailyVerseSource.verse(on: day, from: verses) else { continue }
            let content = UNMutableNotificationContent()
            content.title = verse.reference
            content.body = verse.text
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(identifierPrefix)\(offset)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }
}

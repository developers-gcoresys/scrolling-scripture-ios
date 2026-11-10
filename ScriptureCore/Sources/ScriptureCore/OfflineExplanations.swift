import Foundation

/// One curated explanation in the downloadable Pro offline pack.
public struct OfflineExplanation: Codable, Equatable, Sendable {
    public let reference: String
    public let explanation: String
    public let citations: [String]

    public init(reference: String, explanation: String, citations: [String]) {
        self.reference = reference
        self.explanation = explanation
        self.citations = citations
    }
}

/// Reads and writes the Pro explanation pack in Application Support. The pack
/// is only downloaded for an entitled account and is never bundled with the app.
public enum OfflineExplanationStore {
    public static let fileName = "offline_explanations.json"

    private struct StoredPack: Codable {
        let appId: String
        let packVersion: Int
        let savedAt: Date
        let items: [OfflineExplanation]
    }

    public static func defaultDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    public static func save(
        _ items: [OfflineExplanation],
        appId: String,
        packVersion: Int,
        directory: URL? = nil
    ) throws {
        guard let directory = directory ?? defaultDirectory() else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pack = StoredPack(appId: appId, packVersion: packVersion, savedAt: Date(), items: items)
        let data = try JSONEncoder().encode(pack)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    public static func load(directory: URL? = nil) -> [OfflineExplanation] {
        guard let pack = loadPack(directory: directory) else { return [] }
        return pack.items
    }

    public static func version(directory: URL? = nil) -> Int? {
        loadPack(directory: directory)?.packVersion
    }

    public static func clear(directory: URL? = nil) {
        guard let directory = directory ?? defaultDirectory() else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }

    private static func loadPack(directory: URL? = nil) -> StoredPack? {
        guard let directory = directory ?? defaultDirectory() else { return nil }
        let file = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(StoredPack.self, from: data)
    }
}

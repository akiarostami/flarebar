import Foundation

/// Accounts and projects as JSON in a directory.
public struct ConfigStore: Sendable {
    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("config.json")
    }

    /// ~/Library/Application Support/Flarebar
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Flarebar", isDirectory: true)
    }

    /// A missing file is an empty config.
    public func load() throws -> Config {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Config() }
        return try JSONDecoder().decode(Config.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ config: Config) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: fileURL, options: .atomic)
    }
}

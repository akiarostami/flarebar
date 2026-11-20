import Foundation

/// The last good snapshots on disk, so the popover has data at launch and when Cloudflare is unreachable.
public struct SnapshotCache: Sendable {
    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("snapshots.json")
    }

    /// A missing or unreadable file is an empty cache.
    public func load() -> [AccountSnapshot] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        // Dates use the default numeric coding, which keeps fractional seconds.
        return (try? JSONDecoder().decode([AccountSnapshot].self, from: data)) ?? []
    }

    public func save(_ snapshots: [AccountSnapshot]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshots).write(to: fileURL, options: .atomic)
    }
}

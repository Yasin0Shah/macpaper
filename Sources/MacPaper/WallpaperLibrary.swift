import Foundation

final class WallpaperLibrary {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let folder = base.appendingPathComponent("MacPaper/Wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private var indexURL: URL {
        Self.folder.deletingLastPathComponent().appendingPathComponent("library.json")
    }

    func load() -> [WallpaperItem] {
        guard let data = try? Data(contentsOf: indexURL),
              let items = try? JSONDecoder().decode([WallpaperItem].self, from: data) else {
            return []
        }
        return items.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func add(_ item: WallpaperItem) {
        var items = load()
        items.removeAll { $0.relativePath == item.relativePath }
        items.insert(item, at: 0)
        save(items)
    }

    func delete(_ item: WallpaperItem) {
        try? FileManager.default.removeItem(at: item.fileURL)
        save(load().filter { $0.id != item.id })
    }

    func makeOutputURL(named title: String) -> URL {
        let slug = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return Self.folder.appendingPathComponent("\(slug)-\(stamp).mp4")
    }

    private func save(_ items: [WallpaperItem]) {
        let data = try? JSONEncoder().encode(items)
        try? data?.write(to: indexURL, options: .atomic)
    }
}

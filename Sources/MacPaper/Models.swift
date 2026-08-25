import CoreMedia
import Foundation

struct ConvertSettings: Equatable {
    enum Quality: String, CaseIterable, Identifiable {
        case battery = "Battery"
        case balanced = "Balanced"
        case high = "High"

        var id: String { rawValue }

        var maxLongEdge: CGFloat {
            switch self {
            case .battery: return 1280
            case .balanced: return 1920
            case .high: return 3840
            }
        }

        var framesPerSecond: Int32 {
            switch self {
            case .battery: return 24
            case .balanced: return 30
            case .high: return 30
            }
        }

        var help: String {
            switch self {
            case .battery: return "720p-class HEVC, 24 fps. Lightest on CPU and battery."
            case .balanced: return "1080p HEVC, 30 fps. Best default for most videos."
            case .high: return "Up to 4K HEVC. Sharpest, largest files."
            }
        }
    }

    enum Fit: String, CaseIterable, Identifiable {
        case fill = "Fill screen"
        case fit = "Fit (letterbox)"

        var id: String { rawValue }
    }

    var quality: Quality = .balanced
    var fit: Fit = .fill
    var muteAudio = true
}

struct WallpaperItem: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var relativePath: String
    var createdAt: Date

    var fileURL: URL {
        WallpaperLibrary.folder.appendingPathComponent(relativePath)
    }

    init(id: UUID, title: String, fileURL: URL, createdAt: Date) {
        self.id = id
        self.title = title
        self.relativePath = fileURL.lastPathComponent
        self.createdAt = createdAt
    }
}

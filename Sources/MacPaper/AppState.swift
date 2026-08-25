import AppKit
import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var sourceURL: URL?
    @Published var sourceDuration: Double = 0
    @Published var sourceSize: CGSize = .zero
    @Published var previewPlayer: AVPlayer?

    @Published var settings = ConvertSettings()
    @Published var isConverting = false
    @Published var convertProgress: Double = 0
    @Published var statusMessage: String = "Drop a video to turn it into a looping wallpaper."
    @Published var errorMessage: String?

    @Published var library: [WallpaperItem] = []
    @Published var selectedLibraryID: WallpaperItem.ID?
    @Published var screens: [DisplayInfo] = []
    @Published var selectedDisplayIDs: Set<CGDirectDisplayID> = []

    let engine = WallpaperEngine()
    let libraryStore = WallpaperLibrary()
    private let converter = VideoConverter()
    private var observingScreens = false

    var selectedItem: WallpaperItem? {
        library.first(where: { $0.id == selectedLibraryID })
    }

    func refreshScreens() {
        screens = NSScreen.screens.map(DisplayInfo.init)
        if selectedDisplayIDs.isEmpty {
            selectedDisplayIDs = Set(screens.map(\.displayID))
        } else {
            selectedDisplayIDs = selectedDisplayIDs.intersection(Set(screens.map(\.displayID)))
            if selectedDisplayIDs.isEmpty {
                selectedDisplayIDs = Set(screens.map(\.displayID))
            }
        }
        if !observingScreens {
            observingScreens = true
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshScreens()
                    self?.engine.relayout(using: NSScreen.screens)
                }
            }
        }
    }

    func loadLibrary() {
        library = libraryStore.load()
    }

    func pickVideo() {
        let panel = NSOpenPanel()
        panel.title = "Choose a video"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadSource(url)
    }

    func loadSource(_ url: URL) {
        errorMessage = nil
        sourceURL = url
        selectedLibraryID = nil
        Task { await inspect(url) }
    }

    func inspect(_ url: URL) async {
        previewPlayer?.pause()
        previewPlayer = nil

        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            sourceDuration = duration.seconds.isFinite ? duration.seconds : 0
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let rendered = size.applying(transform)
                sourceSize = CGSize(width: abs(rendered.width), height: abs(rendered.height))
            }
            let player = AVPlayer(url: url)
            player.isMuted = true
            previewPlayer = player
            statusMessage = url.lastPathComponent
        } catch {
            errorMessage = "Could not read this video. MacPaper supports MP4, MOV, and M4V."
        }
    }

    func convertAndApply() {
        guard let sourceURL else { return }
        Task { await convert(sourceURL, apply: true) }
    }

    func convertOnly() {
        guard let sourceURL else { return }
        Task { await convert(sourceURL, apply: false) }
    }

    func applySelected() {
        guard let item = selectedItem else { return }
        apply(url: item.fileURL)
    }

    func applyOriginal() {
        guard let sourceURL else { return }
        apply(url: sourceURL)
    }

    func apply(url: URL) {
        let targets = NSScreen.screens.filter { selectedDisplayIDs.contains($0.displayID) }
        guard !targets.isEmpty else {
            errorMessage = "Select at least one display."
            return
        }
        engine.play(url: url, on: targets)
        statusMessage = "Wallpaper playing. Keep MacPaper running so it stays on the desktop."
    }

    func stopWallpaper() {
        engine.stop()
        statusMessage = "Wallpaper stopped."
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        libraryStore.delete(item)
        library = libraryStore.load()
        selectedLibraryID = nil
    }

    func selectLibraryItem(_ item: WallpaperItem) {
        selectedLibraryID = item.id
        sourceURL = item.fileURL
        Task { await inspect(item.fileURL) }
    }

    private func convert(_ source: URL, apply: Bool) async {
        isConverting = true
        convertProgress = 0
        errorMessage = nil
        statusMessage = "Encoding wallpaper…"

        let filename = source.deletingPathExtension().lastPathComponent
        let output = libraryStore.makeOutputURL(named: filename)

        do {
            let result = try await converter.convert(
                source: source,
                output: output,
                settings: settings,
                screenSize: primaryTargetSize
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.convertProgress = progress
                }
            }

            let item = WallpaperItem(
                id: UUID(),
                title: filename,
                fileURL: result,
                createdAt: Date()
            )
            libraryStore.add(item)
            library = libraryStore.load()
            selectedLibraryID = item.id
            statusMessage = "Saved \(result.lastPathComponent)"
            await inspect(result)
            if apply {
                self.apply(url: result)
            }
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Conversion failed."
        }

        isConverting = false
    }

    private var primaryTargetSize: CGSize {
        let screen = NSScreen.screens.first(where: { selectedDisplayIDs.contains($0.displayID) }) ?? NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let scale = screen?.backingScaleFactor ?? 2
        return CGSize(width: frame.width * scale, height: frame.height * scale)
    }
}

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let size: CGSize

    var displayID: CGDirectDisplayID { id }

    init(screen: NSScreen) {
        id = screen.displayID
        name = screen.localizedName
        size = screen.frame.size
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? 0
    }
}

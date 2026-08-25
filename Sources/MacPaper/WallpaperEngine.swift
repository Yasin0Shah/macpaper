import AppKit
import AVFoundation
import Combine

@MainActor
final class WallpaperEngine: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var isPaused = false

    private var windows: [CGDirectDisplayID: WallpaperWindow] = [:]
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    func play(url: URL, on screens: [NSScreen]) {
        stop()

        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue

        for screen in screens {
            let window = WallpaperWindow(screen: screen)
            let view = PlayerView(player: queue)
            window.contentView = view
            window.orderBack(nil)
            windows[screen.displayID] = window
        }

        queue.play()
        isPlaying = true
        isPaused = false
    }

    func pause() {
        player?.pause()
        isPaused = player != nil
    }

    func resume() {
        player?.play()
        isPaused = false
    }

    func stop() {
        player?.pause()
        looper = nil
        player = nil
        windows.values.forEach { $0.orderOut(nil); $0.close() }
        windows.removeAll()
        isPlaying = false
        isPaused = false
    }

    func relayout(using screens: [NSScreen]) {
        guard isPlaying, let player else { return }
        for (id, window) in windows {
            if let screen = screens.first(where: { $0.displayID == id }) {
                window.setFrame(screen.frame, display: true)
            } else {
                window.orderOut(nil)
                window.close()
                windows.removeValue(forKey: id)
            }
        }
        for screen in screens where windows[screen.displayID] == nil {
            let window = WallpaperWindow(screen: screen)
            window.contentView = PlayerView(player: player)
            window.orderBack(nil)
            windows[screen.displayID] = window
        }
    }
}

final class WallpaperWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: true)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        isOpaque = true
        hasShadow = false
        ignoresMouseEvents = true
        backgroundColor = .black
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        sharingType = .none
        animationBehavior = .none
        collectionBehavior.insert(.transient)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PlayerView: NSView {
    private let playerLayer = AVPlayerLayer()

    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

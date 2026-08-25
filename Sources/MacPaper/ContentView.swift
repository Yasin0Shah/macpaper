import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            LibrarySidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            HStack(spacing: 0) {
                PreviewPane()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                InspectorPane()
                    .frame(width: 300)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Could not convert video", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}

struct LibrarySidebar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Wallpapers")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 8)

            if state.library.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Converted videos will show up here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(state.library, selection: $state.selectedLibraryID) { item in
                    Button {
                        state.selectLibraryItem(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.body)
                                .lineLimit(1)
                            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .tag(item.id)
                    .contextMenu {
                        Button("Apply") { state.selectLibraryItem(item); state.applySelected() }
                        Button("Delete", role: .destructive) {
                            state.selectedLibraryID = item.id
                            state.deleteSelected()
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(.ultraThinMaterial)
    }
}

struct PreviewPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let player = state.previewPlayer {
                    VideoPlayer(player: player)
                        .onAppear { player.play() }
                } else {
                    DropZoneView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(20)

            HStack {
                Text(state.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                if state.engine.isPlaying {
                    Label(state.engine.isPaused ? "Paused" : "Playing on desktop", systemImage: "sparkles.tv")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }
}

struct DropZoneView: View {
    @EnvironmentObject private var state: AppState
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.document")
                .font(.system(size: 44, weight: .light))
            Text("Drop a video here")
                .font(.title2.weight(.semibold))
            Text("MP4, MOV, or M4V. MacPaper encodes it as looping HEVC and plays it behind your desktop icons.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Choose Video…") {
                state.pickVideo()
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.primary.opacity(0.12),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
                )
        )
        .onDrop(of: [UTType.fileURL, UTType.movie], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    state.loadSource(url)
                }
            }
            return true
        }
    }
}

struct InspectorPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let url = state.sourceURL {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(url.lastPathComponent)
                            .font(.headline)
                            .lineLimit(2)
                        if state.sourceSize != .zero {
                            Text("\(Int(state.sourceSize.width))×\(Int(state.sourceSize.height))  ·  \(formatDuration(state.sourceDuration))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No video selected")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Encode") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Quality", selection: $state.settings.quality) {
                            ForEach(ConvertSettings.Quality.allCases) { quality in
                                Text(quality.rawValue).tag(quality)
                            }
                        }
                        Text(state.settings.quality.help)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Framing", selection: $state.settings.fit) {
                            ForEach(ConvertSettings.Fit.allCases) { fit in
                                Text(fit.rawValue).tag(fit)
                            }
                        }

                        Toggle("Mute audio", isOn: $state.settings.muteAudio)
                    }
                    .pickerStyle(.menu)
                    .padding(6)
                }

                GroupBox("Displays") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(state.screens) { screen in
                            Toggle(isOn: displayBinding(screen.displayID)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(screen.name)
                                    Text("\(Int(screen.size.width))×\(Int(screen.size.height))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(6)
                }

                if state.isConverting {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: state.convertProgress)
                        Text("Encoding \(Int(state.convertProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 8) {
                    Button {
                        state.convertAndApply()
                    } label: {
                        Text("Convert & Apply")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(state.sourceURL == nil || state.isConverting)

                    Button {
                        state.convertOnly()
                    } label: {
                        Text("Convert Only")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(state.sourceURL == nil || state.isConverting)

                    Button {
                        state.applyOriginal()
                    } label: {
                        Text("Apply Original Video")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(state.sourceURL == nil || state.isConverting)

                    if state.engine.isPlaying {
                        HStack {
                            Button(state.engine.isPaused ? "Resume" : "Pause") {
                                if state.engine.isPaused {
                                    state.engine.resume()
                                } else {
                                    state.engine.pause()
                                }
                            }
                            Button("Stop", role: .destructive) {
                                state.stopWallpaper()
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func displayBinding(_ id: CGDirectDisplayID) -> Binding<Bool> {
        Binding(
            get: { state.selectedDisplayIDs.contains(id) },
            set: { on in
                if on {
                    state.selectedDisplayIDs.insert(id)
                } else if state.selectedDisplayIDs.count > 1 {
                    state.selectedDisplayIDs.remove(id)
                }
            }
        )
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

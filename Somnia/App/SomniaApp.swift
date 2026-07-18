import SwiftUI

// MARK: - InceptionApp
// Wires together: AudioEngine → SceneController → EnvironmentDetector → UI

@main
struct SomniaApp: App {

    @StateObject private var audioEngine: AudioEngine
    @StateObject private var sceneController: SceneController
    @StateObject private var detector: EnvironmentDetector

    init() {
        let engine     = AudioEngine()
        let det        = EnvironmentDetector(audioEngine: engine)   // engine owns the mic
        let controller = SceneController(audioEngine: engine)

        _audioEngine     = StateObject(wrappedValue: engine)
        _detector        = StateObject(wrappedValue: det)
        _sceneController = StateObject(wrappedValue: controller)
    }

    @State private var isReady = AssetStore.shared.isImported
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if isReady {
                ContentView()
                    .environmentObject(audioEngine)
                    .environmentObject(sceneController)
                    .environmentObject(detector)
                    .onAppear { setupApp() }
            } else {
                // No content imported yet — the first-run gate.
                ImportView(onReady: { isReady = true })
            }
        }
        // Dreams run for long stretches without touch — keep the screen awake so it
        // doesn't dim and auto-lock. Re-asserted on foreground (iOS clears it on
        // background).
        .onChange(of: scenePhase) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = (phase == .active)
        }
    }

    private func setupApp() {
        // Without this the rules array is empty, every match list comes back empty,
        // and induce silently does nothing.
        sceneController.sceneRules = SceneController.defaultRules

        // Decode the interaction sounds up front — the first press is audibly late
        // otherwise.
        SoundPlayer.shared.preload()

        sceneController.bind(to: detector)

        // Scenes come from the user's imported content, not the app bundle.
        sceneController.loadSceneLibrary(from: AssetStore.scenesDir)

        detector.startDetection()
        Task { await detector.requestHealthAccess() }
        // Start the map's ambient Overture once the library has loaded.
        Task { await sceneController.startMapAmbient() }
    }
}

// MARK: - ContentView
// The map is the root. The original has no tab bar — it's a single dream map with
// a pull-down drawer (about / tutorial / news), and the dream itself takes over the
// whole screen once induced.

struct ContentView: View {

    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var sceneController: SceneController
    @EnvironmentObject var detector: EnvironmentDetector

    @State private var showDream = false
    @State private var kickReason: KickReason?
    @StateObject private var mapProvider = MapSnapshotProvider()
    @State private var mazeSize: CGSize = .zero

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            DreamMazeView(
                sceneController: sceneController,
                audioEngine: audioEngine,
                unlockedIds: unlockedIds,
                currentId: sceneController.currentScene?.info.id,
                mapImage: mapProvider.image,
                onInduce: induce,
                onSelect: { dream, infinity in
                    sceneController.isInfinite = infinity
                    Task { try? await sceneController.play(sceneId: dream.id) }
                },
                onMazeSize: { size in
                    mazeSize = size
                    mapProvider.update(
                        latitude: detector.state.latitude,
                        longitude: detector.state.longitude,
                        size: size
                    )
                }
            )

            DrawerView()
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showDream) {
            DreamView(
                audioEngine: audioEngine,
                sceneController: sceneController,
                detector: detector
            )
        }
        .fullScreenCover(item: $kickReason) { kick in
            KickView(reason: kick.text) { kickReason = nil }
        }
        // The dream takes over the screen the moment one starts loading (so its
        // loading state shows), and drops back to the map when it ends.
        .onChange(of: sceneController.activeDream?.info.id) { _, id in
            showDream = id != nil
        }
        // A dream that collapses on its own wakes you with the kick. Ejecting
        // doesn't — you chose to leave, so there's nothing to wake from.
        .onChange(of: sceneController.lastCollapseReason) { _, reason in
            guard let reason else { return }
            kickReason = KickReason(text: reason)
        }
        // Refresh the satellite map when a location fix arrives or the user moves.
        .onChange(of: detector.state.latitude) { _, lat in
            mapProvider.update(latitude: lat, longitude: detector.state.longitude, size: mazeSize)
        }
        .onReceive(detector.$mood) { newMood in
            audioEngine.setMoodAutomatic(newMood)
        }
    }

    /// A dream is currently treated as unlocked if its scene is present. The original
    /// persisted real unlock state per sceneId (DateOfUnlock/LocationOfUnlock) —
    /// that progression isn't implemented yet.
    private var unlockedIds: Set<Int> {
        // Use the keys scenes were installed under (their real sceneId), not each
        // bundle's info.id — Reverie is keyed at 0 but its bundle carries no id.
        Set(sceneController.availableSceneIds)
    }

    /// The original's induction: pick the dream matching current conditions rather
    /// than letting the user choose. Routed through the existing rules engine.
    private func induce() {
        // The centre button is the "let the world pick" path — not infinity.
        sceneController.isInfinite = false
        Task { await sceneController.evaluateRules(for: detector.state) }
    }
}

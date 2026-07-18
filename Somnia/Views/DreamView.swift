import SwiftUI

// MARK: - DreamView
// Remake of DreamViewController — the dream itself.
//
// The original is deliberately bare: the red vignette, the dream's title, an
// infinity toggle and an eject button. "The true interface is not the screen,
// it's the world around you." Manual control is our addition, kept behind a
// button so the default experience stays environment-driven.

public struct DreamView: View {

    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var sceneController: SceneController
    @ObservedObject var detector: EnvironmentDetector

    @Environment(\.dismiss) private var dismiss
    @AppStorage("manualControlEnabled") private var manualControlAvailable = false

    @State private var isInfinite = false
    @State private var showManualPad = false
    @State private var isDragging = false
    @State private var dragPoint: CGPoint = .zero
    @State private var entering = true
    @State private var countdown = 3

    public init(audioEngine: AudioEngine, sceneController: SceneController, detector: EnvironmentDetector) {
        self.audioEngine = audioEngine
        self.sceneController = sceneController
        self.detector = detector
    }

    public var body: some View {
        ZStack {
            // Background fills the whole screen, under the Dynamic Island and home
            // indicator. Only the background ignores the safe area.
            Image(dream: "dream-background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            // The vignette breathes with the dream's energy — the only ambient
            // motion on the screen, so the dream feels alive while idle.
            Color.black
                .opacity(Double(0.35 - audioEngine.mood.energy * 0.3))
                .blendMode(.multiply)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 2.5), value: audioEngine.mood.energy)

            // Content stays inside the safe area — the GeometryReader here is not
            // extended, so the header clears the island and the footer clears the
            // home indicator.
            GeometryReader { geo in
                ZStack {
                    if isLoading {
                        loadingState
                            .frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        if showManualPad {
                            manualPad(in: geo.size)
                        }

                        VStack {
                            header
                            Spacer()
                            footer
                        }
                        .padding(.vertical, 24)
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onAppear {
            // Reflect the mode the dream was entered in (infinity from a tile card).
            isInfinite = sceneController.isInfinite
            // Interaction sounds would cut across the music.
            SoundPlayer.shared.play(.sceneStart)
            SoundPlayer.shared.isMuted = true
            entering = true
            Task { await runEntrySequence() }
        }
        .onDisappear { SoundPlayer.shared.isMuted = false }
    }

    // MARK: - Loading

    /// The deliberate 3-2-1 entry sequence — a fixed intro, not tied to how fast
    /// the stems load (which is near-instant and would flash by), and it never
    /// re-shows on the way out because `entering` only resets on a fresh appear.
    private var isLoading: Bool { entering }

    private var loadingState: some View {
        VStack(spacing: 26) {
            Text(sceneController.activeDream?.info.name.uppercased() ?? "DREAMING")
                .font(.system(size: 22, weight: .ultraLight, design: .serif))
                .foregroundStyle(.white.opacity(0.85))
                .tracking(6)

            Text("\(countdown)")
                .font(.system(size: 44, weight: .ultraLight, design: .serif))
                .foregroundStyle(.white.opacity(0.7))
                .contentTransition(.numericText(countsDown: true))
                .animation(.easeInOut(duration: 0.4), value: countdown)

            Text("Constructing your Dreams…")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(1)
        }
    }

    /// Runs 3 → 2 → 1, then reveals the dream once its stems are actually loaded.
    private func runEntrySequence() async {
        for n in stride(from: 3, through: 1, by: -1) {
            countdown = n
            try? await Task.sleep(for: .seconds(1))
        }
        while sceneController.currentScene == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        withAnimation(.easeInOut(duration: 0.5)) { entering = false }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Text(sceneController.currentScene?.info.name.lowercased() ?? "dreaming")
                .font(.system(size: 26, weight: .ultraLight, design: .serif))
                .foregroundStyle(.white.opacity(0.85))
                .tracking(8)
                .animation(.easeInOut(duration: 1.2), value: sceneController.currentScene?.info.id)

            Text(detector.state.isQuiet ? "the world around you is quiet" : "the world around you is now in your dream")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
                .tracking(2)
                .animation(.easeInOut(duration: 1.5), value: detector.state.isQuiet)

            // Tells you the mic is being fed back through the dream — the moment to
            // speak and hear yourself transformed. The bar shows live mic level, so
            // you can see the mic is being captured even before you trust your ears.
            if audioEngine.voiceActive {
                VStack(spacing: 6) {
                    Label("your voice is in the dream", systemImage: "waveform")
                        .font(.system(size: 9, weight: .light))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(1)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.1))
                            Capsule()
                                .fill(.white.opacity(0.5))
                                .frame(width: geo.size.width * CGFloat(min(1, audioEngine.micLevel * 1.5)))
                        }
                    }
                    .frame(width: 120, height: 3)
                    .animation(.linear(duration: 0.1), value: audioEngine.micLevel)
                }
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: audioEngine.voiceActive)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 18) {
            if manualControlAvailable {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showManualPad.toggle() }
                    SoundPlayer.shared.play(showManualPad ? .sliderUp : .sliderDown, volume: 0.5)
                    if !showManualPad { audioEngine.endManualMood(returnToAutoAfter: 0) }
                } label: {
                    Text(showManualPad ? "release" : "take control")
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(.white.opacity(showManualPad ? 0.9 : 0.45))
                        .tracking(3)
                        .textCase(.uppercase)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .overlay(
                            Capsule().stroke(.white.opacity(showManualPad ? 0.4 : 0.15), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 40) {
                // Infinity — stay in this dream rather than letting it collapse.
                Button {
                    isInfinite.toggle()
                    // Actually suppresses collapse — the dream runs until you eject.
                    sceneController.isInfinite = isInfinite
                    SoundPlayer.shared.play(.infinity)
                } label: {
                    Image(dream: isInfinite ? "infinite-on" : "infinite-off")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 26)
                }
                .buttonStyle(.plain)
                // Limbo can't be held open — you're locked in for 3'40" and it ends
                // on its own.
                .disabled(sceneController.currentScene?.info.id == 310)
                .opacity(sceneController.currentScene?.info.id == 310 ? 0.3 : 1)

                Button(action: eject) {
                    Image(dream: "eject")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .disabled(sceneController.currentScene?.info.id == 310)
                .opacity(sceneController.currentScene?.info.id == 310 ? 0.3 : 1)
            }

            Text("Press eject to leave your dreamworld.")
                .font(.system(size: 9, weight: .light))
                .foregroundStyle(.white.opacity(0.22))
                .tracking(1)
        }
    }

    // MARK: - Manual control

    private func manualPad(in size: CGSize) -> some View {
        ZStack {
            // Only active while the pad is showing, so the default dream can't be
            // steered by accident.
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            dragPoint = value.location
                            audioEngine.setMoodManual(MoodVector(
                                energy: Float(1 - value.location.y / size.height),
                                valence: Float(value.location.x / size.width)
                            ))
                        }
                        .onEnded { _ in
                            isDragging = false
                            // Hold the manual mood briefly, then hand back to the world.
                            audioEngine.endManualMood(returnToAutoAfter: 5)
                        }
                )

            if isDragging {
                Circle()
                    .stroke(.white.opacity(0.35), lineWidth: 0.5)
                    .frame(width: 46, height: 46)
                    .position(dragPoint)
                    .allowsHitTesting(false)
            }

            VStack {
                Spacer()
                Text("energy \(Int(audioEngine.mood.energy * 100))   ·   mood \(Int(audioEngine.mood.valence * 100))")
                    .font(.system(size: 9, weight: .light).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(2)
                    .padding(.bottom, 150)
            }
        }
    }

    // MARK: - Actions

    private func eject() {
        SoundPlayer.shared.isMuted = false
        SoundPlayer.shared.play(.eject)
        audioEngine.stop()
        sceneController.leaveDream()
        dismiss()
    }
}

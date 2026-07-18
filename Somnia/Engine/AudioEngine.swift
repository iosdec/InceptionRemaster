import AVFoundation
import Combine

// MARK: - MoodSource

public enum MoodSource: Equatable {
    case automatic          // driven by EnvironmentDetector
    case manual             // driven by user drag
}

// MARK: - MoodVector

public struct MoodVector: Equatable {
    public var energy: Float   // 0 = calm/still,  1 = high energy/active
    public var valence: Float  // 0 = dark/tense,   1 = bright/happy

    public static let neutral = MoodVector(energy: 0.3, valence: 0.5)
    public static let calm    = MoodVector(energy: 0.1, valence: 0.7)
    public static let dark    = MoodVector(energy: 0.2, valence: 0.1)
    public static let intense = MoodVector(energy: 0.9, valence: 0.2)
    public static let joyful  = MoodVector(energy: 0.8, valence: 0.9)

    public init(energy: Float, valence: Float) {
        self.energy  = max(0, min(1, energy))
        self.valence = max(0, min(1, valence))
    }
}

// MARK: - StemPlayer

private class StemPlayer {
    let stem: AudioStem
    let playerNode: AVAudioPlayerNode
    let pitchNode: AVAudioUnitTimePitch
    var targetVolume: Float = 0
    var currentVolume: Float = 0

    init(stem: AudioStem) {
        self.stem = stem
        self.playerNode = AVAudioPlayerNode()
        self.pitchNode = AVAudioUnitTimePitch()
        pitchNode.rate = 1.0
        pitchNode.pitch = 0
    }
}

// MARK: - AudioEngine

@MainActor
public class AudioEngine: ObservableObject {

    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentScene: SceneBundle?
    @Published public var mood: MoodVector = .neutral
    @Published public private(set) var moodSource: MoodSource = .automatic

    private var manualOverrideTimer: Timer?

    private let engine      = AVAudioEngine()
    private let masterMixer = AVAudioMixerNode()
    private let reverbNode  = AVAudioUnitReverb()
    private let delayNode   = AVAudioUnitDelay()

    // Voice augmentation — the RjDj trick: the mic, pitch-shifted and drenched in
    // reverb/delay, fed back into your ears. grainvoice.pd did this granularly; this
    // is the AVAudioEngine approximation. Kept on its own mixer so it can be muted
    // instantly and gated to headphones (never through the speaker → no feedback).
    private let voicePitch  = AVAudioUnitTimePitch()
    private let voiceDelay  = AVAudioUnitDelay()
    private let voiceReverb = AVAudioUnitReverb()
    private let voiceMixer  = AVAudioMixerNode()
    private var voiceConnected = false
    private var voiceRequested = false

    @Published public private(set) var voiceActive = false

    private var stemPlayers: [StemPlayer] = []
    private var fadeTimer: Timer?
    private var moodCancellable: AnyCancellable?

    public var crossfadeDuration: Double = 8.0

    // MARK: - Init

    public init() {
        configureAudioSession()
        setupGraph()
        // Drive stem volumes from mood — use Combine to avoid per-frame thrash
        moodCancellable = $mood
            .removeDuplicates()
            .sink { [weak self] _ in self?.updateStemVolumes() }
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .playAndRecord so AudioInputMonitor can open a mic tap — scenes are
            // driven by room sound. .defaultToSpeaker is required or playback
            // routes to the earpiece as soon as the category allows recording.
            //
            // No .mixWithOthers: with it, iOS treats us as secondary audio and can
            // decline to keep us alive when the screen locks. Dreams must keep
            // playing on lock, so we take the primary audio slot instead.
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothA2DP, .allowAirPlay]
            )
            try session.setActive(true)
            print("✅ Audio session active (playAndRecord)")
        } catch {
            print("❌ Audio session error: \(error)")
        }

        // Recover from interruptions (phone call, Siri): the engine stops, so restart
        // it and resume when the interruption ends. Without this a call ends the dream.
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: session
        )
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        switch type {
        case .began:
            Task { @MainActor in self.isPlaying = false }
        case .ended:
            let opts = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
            guard opts?.contains(.shouldResume) == true else { return }
            Task { @MainActor in
                try? AVAudioSession.sharedInstance().setActive(true)
                if !self.engine.isRunning { try? self.engine.start() }
                for p in self.stemPlayers { p.playerNode.play() }
                self.isPlaying = true
            }
        @unknown default:
            break
        }
    }

    // MARK: - Graph

    private func setupGraph() {
        engine.attach(masterMixer)
        engine.attach(reverbNode)
        engine.attach(delayNode)

        reverbNode.loadFactoryPreset(.mediumHall)
        reverbNode.wetDryMix = 20

        delayNode.delayTime     = 0.38
        delayNode.feedback      = 15
        delayNode.wetDryMix     = 12
        delayNode.lowPassCutoff = 8000

        let out = engine.mainMixerNode
        engine.connect(masterMixer, to: reverbNode, format: nil)
        engine.connect(reverbNode,  to: delayNode,  format: nil)
        engine.connect(delayNode,   to: out,         format: nil)

        masterMixer.outputVolume = 0.85

        // Voice chain: pitch → delay → reverb → voiceMixer → output. Attached now,
        // but the mic isn't wired in until enableVoice() — connecting the input node
        // without a live input route can fault.
        engine.attach(voicePitch)
        engine.attach(voiceDelay)
        engine.attach(voiceReverb)
        engine.attach(voiceMixer)

        voicePitch.pitch = -250        // shifted down — dreamlike, uncanny
        voiceDelay.delayTime = 0.28
        voiceDelay.feedback = 40
        voiceDelay.wetDryMix = 45
        voiceDelay.lowPassCutoff = 4000
        voiceReverb.loadFactoryPreset(.largeHall2)
        voiceReverb.wetDryMix = 70

        engine.connect(voicePitch,  to: voiceDelay,  format: nil)
        engine.connect(voiceDelay,  to: voiceReverb, format: nil)
        engine.connect(voiceReverb, to: voiceMixer,  format: nil)
        engine.connect(voiceMixer,  to: out,          format: nil)
        voiceMixer.outputVolume = 0   // silent until enabled

        // Route changes (unplugging headphones) must instantly kill voice feedback.
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance()
        )
    }

    // MARK: - Voice Augmentation

    /// True only when headphones (wired, Bluetooth, or AirPlay) are the output — the
    /// mic must never feed the speaker or it howls. This is why the original demanded
    /// a headset.
    private var headphonesConnected: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains {
            [.headphones, .bluetoothA2DP, .bluetoothHFP, .airPlay, .bluetoothLE].contains($0.portType)
        }
    }

    /// Turn the augmented-voice effect on/off. Only takes effect on headphones;
    /// the request is remembered and reconciled whenever the engine (re)starts.
    public func setVoiceAugmentation(_ on: Bool) {
        voiceRequested = on
        reconcileVoice()
    }

    private func reconcileVoice() {
        if voiceRequested, headphonesConnected {
            connectVoiceInput()
            voiceMixer.outputVolume = voiceConnected ? 0.9 : 0
            voiceActive = voiceConnected
            if voiceConnected { print("🎙️ Voice augmentation on") }
        } else {
            voiceMixer.outputVolume = 0
            voiceActive = false
            if voiceRequested { print("🎧 Voice augmentation needs headphones") }
        }
    }

    private func connectVoiceInput() {
        guard !voiceConnected, engine.isRunning else {
            // If the engine isn't running yet, defer — enableVoice is retried on play().
            return
        }
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }   // no live input route
        engine.connect(input, to: voicePitch, format: format)
        voiceConnected = true
    }

    @objc private func handleRouteChange(_ note: Notification) {
        Task { @MainActor in
            // Reconcile in both directions: plugging headphones in can enable a
            // pending request, pulling them out must cut the voice immediately.
            self.reconcileVoice()
            if self.voiceActive, !self.headphonesConnected {
                self.voiceMixer.outputVolume = 0
                self.voiceActive = false
                print("🎧 Headphones removed — voice augmentation muted")
            }
        }
    }

    // MARK: - Load

    public func load(scene: SceneBundle) async throws {
        // 1. Stop and tear down existing players
        stop()
        for p in stemPlayers {
            engine.detach(p.playerNode)
            engine.detach(p.pitchNode)
        }
        stemPlayers.removeAll()

        // 2. Start engine before connecting new nodes
        if !engine.isRunning {
            try engine.start()
            print("✅ AVAudioEngine started")
        }

        // Now that the engine is running, honour any pending voice request.
        reconcileVoice()

        // 3. Load each stem
        print("🎵 Loading \(scene.stems.count) stems for \(scene.info.name)")
        for stem in scene.stems {
            print("  → \(stem.id) at \(stem.url.path)")
            guard FileManager.default.fileExists(atPath: stem.url.path) else {
                print("  ❌ File does not exist: \(stem.url.path)")
                continue
            }
            guard let file = try? AVAudioFile(forReading: stem.url) else {
                print("  ❌ Cannot open AVAudioFile: \(stem.id)")
                continue
            }
            print("  ✅ Opened \(stem.id) — \(file.length) frames, \(file.processingFormat)")

            let frameCount = AVAudioFrameCount(file.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: frameCount) else {
                print("⚠️ Cannot allocate buffer for: \(stem.id)")
                continue
            }

            do {
                try file.read(into: buffer)
            } catch {
                print("⚠️ Cannot read \(stem.id): \(error)")
                continue
            }

            let player = StemPlayer(stem: stem)
            engine.attach(player.playerNode)
            engine.attach(player.pitchNode)
            engine.connect(player.playerNode, to: player.pitchNode, format: file.processingFormat)
            engine.connect(player.pitchNode,  to: masterMixer,      format: file.processingFormat)

            // Use the completion handler overload explicitly to avoid the async
            // overload which blocks until the buffer finishes — never with .loops
            player.playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)

            let initVol: Float = stem.role == .base ? 0.8 : 0.0
            player.playerNode.volume = initVol
            player.currentVolume     = initVol
            player.targetVolume      = initVol

            stemPlayers.append(player)
            print("  🎵 Stem: \(stem.id) [\(stem.role)]")
        }

        currentScene = scene
        print("✅ Scene ready: \(scene.info.name) — \(stemPlayers.count) stems")
    }

    // MARK: - Playback

    public func play() {
        guard !stemPlayers.isEmpty else {
            print("⚠️ play() — no stems loaded")
            return
        }
        guard !isPlaying else { return }

        masterMixer.outputVolume = 0
        for p in stemPlayers { p.playerNode.play() }
        isPlaying = true
        fadeInMaster()
        startFadeLoop()
        updateStemVolumes()
        print("▶️ Playing — \(stemPlayers.count) stems")
    }

    public func stop() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        for p in stemPlayers { p.playerNode.stop() }
        // Voice augmentation belongs to a dream — never let it linger on the map.
        voiceRequested = false
        voiceMixer.outputVolume = 0
        voiceActive = false
        isPlaying = false
    }

    public func pause() {
        for p in stemPlayers { p.playerNode.pause() }
        isPlaying = false
    }

    // MARK: - Mood → Volumes

    private func updateStemVolumes() {
        guard isPlaying else { return }

        let e = mood.energy
        let v = mood.valence
        let d = 1 - v

        for p in stemPlayers {
            let target: Float
            switch p.stem.role {
            case .base:     target = max(0.4, 0.9 - e * 0.3)
            case .energy:   target = e > 0.5 ? (e - 0.5) * 2.0 : 0
            case .dark:     target = d * max(0, e * 1.5)
            case .melodic:  target = (1 - e) * v * 0.9
            case .rhythmic: target = e > 0.4 ? (e - 0.4) * 1.6 : 0
            case .harmonic: target = (v * 0.6) + 0.2 - (d * e * 0.4)
            case .unknown:  target = 0.15
            }
            p.targetVolume = max(0, min(1, target))
        }
    }

    // MARK: - Fade Loop

    private func startFadeLoop() {
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tickFade() }
        }
    }

    private func tickFade() {
        let lerpRate: Float = 0.05   // equivalent to lop~ in Pure Data
        for p in stemPlayers {
            let diff = p.targetVolume - p.currentVolume
            if abs(diff) > 0.001 {
                p.currentVolume += diff * lerpRate
                p.playerNode.volume = p.currentVolume
            } else {
                p.currentVolume = p.targetVolume
                p.playerNode.volume = p.targetVolume
            }
        }
    }

    /// Fades the master out and suspends the players — used before a live morph so
    /// one dream dissolves into the next instead of hard-cutting.
    public func fadeOutMaster(duration: Double = 1.0) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let start = masterMixer.outputVolume
            let step = start / Float(max(1, duration / 0.05))
            var vol = start
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
                guard let self else { t.invalidate(); cont.resume(); return }
                vol = max(0, vol - step)
                Task { @MainActor in self.masterMixer.outputVolume = vol }
                if vol <= 0 { t.invalidate(); cont.resume() }
            }
        }
    }

    private func fadeInMaster() {
        var vol: Float = 0
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            vol = min(0.85, vol + 0.03)
            Task { @MainActor in self.masterMixer.outputVolume = vol }
            if vol >= 0.85 { t.invalidate() }
        }
    }

    // MARK: - Mood Control

    /// Called by the drag gesture — locks out automatic updates
    public func setMoodManual(_ newMood: MoodVector) {
        moodSource = .manual
        mood = newMood
        manualOverrideTimer?.invalidate()
        manualOverrideTimer = nil
    }

    /// Called when drag ends — returns to automatic after a delay.
    /// Pass 0 for immediate switch (e.g. from the toggle button).
    public func endManualMood(returnToAutoAfter delay: Double = 4.0) {
        manualOverrideTimer?.invalidate()
        manualOverrideTimer = nil
        if delay == 0 {
            moodSource = .automatic
        } else {
            manualOverrideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.moodSource = .automatic
                }
            }
        }
    }

    /// Called by EnvironmentDetector — only applies when in automatic mode
    public func setMoodAutomatic(_ newMood: MoodVector) {
        guard moodSource == .automatic else { return }
        mood = newMood
    }

    // MARK: - Effects

    public func setReverbMix(_ mix: Float) { reverbNode.wetDryMix = max(0, min(100, mix)) }
    public func setDelayMix(_ mix: Float)  { delayNode.wetDryMix  = max(0, min(100, mix)) }

    // MARK: - Debug

    public var stemDebugInfo: [(name: String, role: StemRole, volume: Float, target: Float)] {
        stemPlayers.map { ($0.stem.id, $0.stem.role, $0.currentVolume, $0.targetVolume) }
    }
}

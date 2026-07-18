import Foundation
import Combine
import AVFoundation

// MARK: - SceneRule
// The original app had an AirportSceneRule class and a rules array on SceneController.
// This is the modern equivalent — a protocol any rule can conform to.

public protocol SceneRule {
    var priority: Int { get }
    func evaluate(environment: EnvironmentState) -> SceneMatch?
}

public struct SceneMatch {
    public let sceneId: Int         // the original's sceneId, as in SceneInfo.id
    public let reason: String
    public let confidence: Float    // 0–1
}

// MARK: - UnlockRecord

public struct UnlockRecord: Codable {
    public let date: Date
    public let city: String

    private static let key = "unlockRecords"

    static func loadAll() -> [Int: UnlockRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Int: UnlockRecord].self, from: data)
        else { return [:] }
        return decoded
    }

    static func save(_ records: [Int: UnlockRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Built-in Rules
//
// One rule per dream, mirroring the conditions in the original's own
// `undiscovered<id>` strings. Rules key off sceneId rather than filename: the
// bundles are named things like Airport_20110117_B, so matching on "airport"
// never resolved.
//
// Not covered here — these need state EnvironmentDetector doesn't track yet:
//   310 Limbo   — three dreams in a row, the fourth goes to limbo
//   314 Reward  — every hour of accumulated induced dream time
//   317 Shared  — another dreamer at the same location

/// Movement threshold above which the user counts as active, and below which
/// they count as still. Matches the shake detector's scale in EnvironmentDetector.
private enum Motion {
    static let active: Float = 0.18
    static let still: Float = 0.06
}

/// 315 — "induce the induce button while at the airport waiting for your plane"
public struct AirportSceneRule: SceneRule {
    public let priority = 10
    public init() {}
    public func evaluate(environment: EnvironmentState) -> SceneMatch? {
        guard environment.isAtAirport else { return nil }
        return SceneMatch(sceneId: 315, reason: "At airport: \(environment.airportName)", confidence: 0.9)
    }
}

/// 316 — "while you are in Africa"
public struct AfricaSceneRule: SceneRule {
    public let priority = 10
    public init() {}
    public func evaluate(environment: EnvironmentState) -> SceneMatch? {
        guard environment.continent == .africa else { return nil }
        return SceneMatch(sceneId: 316, reason: "In Africa", confidence: 0.9)
    }
}

/// 298 — "during a full moon night"
public struct FullMoonSceneRule: SceneRule {
    public let priority = 9
    public init() {}
    public func evaluate(environment: EnvironmentState) -> SceneMatch? {
        guard environment.isFullMoon, !environment.isDaytime else { return nil }
        return SceneMatch(sceneId: 298, reason: "Full moon tonight", confidence: 0.85)
    }
}

/// 301 — "when travelling fast"
public struct TravellingSceneRule: SceneRule {
    public let priority = 8
    public init() {}
    public func evaluate(environment: EnvironmentState) -> SceneMatch? {
        guard environment.speed > 8 else { return nil }   // ~29 km/h — beyond running
        return SceneMatch(sceneId: 301, reason: "Travelling at \(Int(environment.speed * 3.6))km/h", confidence: 0.8)
    }
}

/// 297 — "during a sunny day and be still"
public struct SunshineSceneRule: SceneRule {
    public let priority = 7
    public init() {}
    public func evaluate(environment: EnvironmentState) -> SceneMatch? {
        guard environment.isSunny, environment.accelerationMagnitude < Motion.still else { return nil }
        return SceneMatch(sceneId: 297, reason: "Sunny and still", confidence: 0.75)
    }
}

/// 300 — "tonight after 11pm ... when you are quiet and still"
public struct SleepSceneRule: SceneRule {
    public let priority = 7
    public init() {}
    public func evaluate(environment: EnvironmentState) -> SceneMatch? {
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= 23 || hour < 5 else { return nil }
        guard environment.isQuiet, environment.accelerationMagnitude < Motion.still else { return nil }
        return SceneMatch(sceneId: 300, reason: "Late, quiet and still", confidence: 0.8)
    }
}

/// 296 — "walk or be active"
public struct ActionSceneRule: SceneRule {
    public let priority = 6
    public init() {}
    public func evaluate(environment: EnvironmentState) -> SceneMatch? {
        guard environment.accelerationMagnitude > Motion.active else { return nil }
        return SceneMatch(sceneId: 296, reason: "Moving", confidence: 0.7)
    }
}

/// 313 — "in a loud place and be still". The mirror of QuietSceneRule.
public struct StillSceneRule: SceneRule {
    public let priority = 5
    public init() {}
    public func evaluate(environment: EnvironmentState) -> SceneMatch? {
        guard !environment.isQuiet, environment.accelerationMagnitude < Motion.still else { return nil }
        return SceneMatch(sceneId: 313, reason: "Loud and still", confidence: 0.65)
    }
}

/// 302 — "at a quiet place and be still"
public struct QuietSceneRule: SceneRule {
    public let priority = 5
    public init() {}
    public func evaluate(environment: EnvironmentState) -> SceneMatch? {
        guard environment.isQuiet, environment.accelerationMagnitude < Motion.still else { return nil }
        return SceneMatch(sceneId: 302, reason: "Quiet and still", confidence: 0.65)
    }
}

/// 0 — Reverie. "When you enter your dreamworld for the first time."
/// Always matches, so induce always resolves to something.
public struct ReverieSceneRule: SceneRule {
    public let priority = 0
    public init() {}
    public func evaluate(environment: EnvironmentState) -> SceneMatch? {
        SceneMatch(sceneId: 0, reason: "Default dream", confidence: 0.1)
    }
}

public extension SceneController {
    /// The full rule set, highest priority first. Without this the rules array is
    /// empty and induce silently does nothing.
    static var defaultRules: [any SceneRule] {
        [
            AirportSceneRule(), AfricaSceneRule(), FullMoonSceneRule(),
            TravellingSceneRule(), SunshineSceneRule(), SleepSceneRule(),
            ActionSceneRule(), StillSceneRule(), QuietSceneRule(),
            ReverieSceneRule(),
        ]
    }
}

// MARK: - SceneController

@MainActor
public class SceneController: ObservableObject {

    @Published public private(set) var currentScene: SceneBundle?
    @Published public private(set) var previousScene: SceneBundle?
    /// The dream being loaded — set before its stems are ready, so the dream screen
    /// can show its title with a loading state instead of freezing on the map.
    @Published public private(set) var pendingScene: SceneBundle?

    /// The dream on screen, whether still loading or playing.
    public var activeDream: SceneBundle? { currentScene ?? pendingScene }
    @Published public private(set) var currentCity: String = ""
    @Published public private(set) var currentAirport: String = ""
    @Published public private(set) var sceneHistory: [SceneInfo] = []
    @Published public private(set) var isTransitioning: Bool = false

    /// Why the last dream ended, for the collapse screen. Nil after an eject.
    @Published public private(set) var lastCollapseReason: String?

    /// When the current dream began — drives the timed dreams and the grace period.
    public private(set) var dreamStartedAt: Date?

    /// Dreams entered back-to-back without returning to the map for long.
    /// "Entering too many dreams within dreams is unstable! Three dreams in a row
    /// and fourth will send you to the undefined dream space of limbo."
    private(set) var consecutiveDreams = 0
    private var lastDreamEndedAt: Date?

    /// Gap after which the chain resets — go do something else and you're safe.
    private let limboChainWindow: TimeInterval = 90

    // The rules array — same concept as sceneRules ivar in original
    public var sceneRules: [any SceneRule] = []

    private var availableScenes: [Int: SceneBundle] = [:]  // sceneId → bundle
    private var scenesDirectory: URL?

    /// Overture — the "Overture Dream", reserved for the intro sequence.
    private var overtureScene: SceneBundle?

    /// The map's looping music (mapview.m4a — the piano theme, a ready-made file).
    /// Kept out of the dream AudioEngine: it's plain background music, not a scene.
    private var mapMusicPlayer: AVAudioPlayer?

    /// When and where each dream was first entered, mirroring the original's
    /// DateOfUnlock/LocationOfUnlock. Shown on the dream info card.
    @Published public private(set) var unlockRecords: [Int: UnlockRecord] = UnlockRecord.loadAll()

    /// Last city seen from the environment, so an unlock can be stamped with it.
    private var lastKnownCity = ""

    private let audioEngine: AudioEngine
    private var environmentCancellable: AnyCancellable?
    private var lastEvaluatedEnvironment: EnvironmentState?

    // MARK: - Init

    public init(audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
    }

    // MARK: - Scene Library

    /// Load all .rj/.rjz files from a directory
    public func loadSceneLibrary(from directory: URL) {
        scenesDirectory = directory

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )

            print("🔍 Scanning: \(directory.path)")
            print("🔍 Found \(files.count) items:")
            for f in files { print("   \(f.lastPathComponent)") }

            for file in files where ["rj", "rjz"].contains(file.pathExtension.lowercased()) {
                do {
                    let bundle = try SceneBundle.load(from: file)
                    // The two undated music bundles carry no sceneId. Overture is the
                    // intro's "Overture Dream" (held for later); Reverie is the
                    // default dream, sceneId 0. The map's own music is mapview.m4a,
                    // handled separately — not a scene.
                    let lname = bundle.info.name.lowercased()
                    if lname == "overture" {
                        overtureScene = bundle
                        print("✅ Loaded intro: Overture")
                        continue
                    }
                    if lname == "reverie" {
                        availableScenes[0] = bundle   // the default dream, sceneId 0
                        print("✅ Loaded default dream: Reverie")
                        continue
                    }
                    // Key by the bundle's own sceneId — filenames vary
                    // (Airport_20110117_B), the id doesn't.
                    availableScenes[bundle.info.id] = bundle
                    print("✅ Loaded scene \(bundle.info.id): \(bundle.info.name)")
                } catch {
                    print("❌ Failed to load \(file.lastPathComponent): \(error)")
                }
            }

            let loaded = availableScenes.keys.sorted().map(String.init).joined(separator: ", ")
            print("✅ Loaded \(availableScenes.count) scenes: [\(loaded)]")
        } catch {
            print("⚠️ Failed to load scene library: \(error)")
        }
    }

    /// Register a pre-loaded scene
    public func register(scene: SceneBundle) {
        availableScenes[scene.info.id] = scene
    }

    // MARK: - Map ambient (Overture)

    /// Play the Overture as the map's ambient bed. Does NOT set currentScene, so the
    /// dream screen stays down — this is background music for the map, not a dream.
    public func startMapAmbient() async {
        guard currentScene == nil else { return }
        if let player = mapMusicPlayer {
            if !player.isPlaying { player.play() }
            return
        }
        let url = AssetStore.soundsDir.appendingPathComponent("mapview.m4a")
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("⚠️ mapview.m4a not imported")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1     // loop the piano theme
            player.volume = 0.7
            player.prepareToPlay()
            player.play()
            mapMusicPlayer = player
            print("🎼 Map music playing: mapview.m4a")
        } catch {
            print("⚠️ Could not start map music: \(error.localizedDescription)")
        }
    }

    private func stopMapAmbient() {
        mapMusicPlayer?.pause()
    }

    // MARK: - Environment Binding

    /// Connect to an EnvironmentDetector.
    ///
    /// This only drives *collapse*. In the original you never fall into a dream
    /// passively — you press induce, and the world decides which one you get. So
    /// while no dream is playing, environment updates do nothing.
    public func bind(to detector: EnvironmentDetector) {
        environmentCancellable = detector.$state
            .debounce(for: .seconds(2), scheduler: RunLoop.main) // don't thrash on every accelerometer tick
            .sink { [weak self] state in
                Task { @MainActor [weak self] in
                    await self?.liveEvaluate(for: state)
                }
            }
    }

    // MARK: - Live morphing
    //
    // While you're in a dream, the world keeps deciding. If your activity starts
    // matching a *different* dream (e.g. you were still in Sunshine, then start
    // moving → Action), the dream morphs into it — a smooth cross-fade, no loading
    // screen. Only if nothing else matches does the current dream collapse.

    private let morphSustain: TimeInterval = 4
    private var morphCandidateId: Int?
    private var morphCandidateSince: Date?

    private func liveEvaluate(for environment: EnvironmentState) async {
        if !environment.city.isEmpty { lastKnownCity = environment.city }

        guard !isInfinite, !isTransitioning,
              let scene = currentScene,
              let startedAt = dreamStartedAt else {
            collapseCandidateSince = nil
            morphCandidateId = nil
            return
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > collapseGracePeriod else { return }

        // Timed dreams (Limbo, Reward) run their course — no morphing out early.
        let isTimed = scene.info.id == 310 || scene.info.id == 314
        if !isTimed, let target = bestMorphTarget(for: environment, excluding: scene.info.id) {
            // Require the new match to hold briefly, so a momentary movement doesn't
            // yank you between dreams.
            if morphCandidateId == target {
                if let since = morphCandidateSince, Date().timeIntervalSince(since) >= morphSustain {
                    morphCandidateId = nil
                    morphCandidateSince = nil
                    await morph(toSceneId: target)
                }
            } else {
                morphCandidateId = target
                morphCandidateSince = Date()
            }
            collapseCandidateSince = nil   // considering a morph, not a collapse
            return
        }
        morphCandidateId = nil

        evaluateCollapse(for: environment, elapsed: elapsed, scene: scene)
    }

    /// The highest-priority *specific* dream (not the always-on default) that the
    /// environment now matches, other than the current one and only if installed.
    private func bestMorphTarget(for environment: EnvironmentState, excluding currentId: Int) -> Int? {
        sceneRules
            .filter { $0.priority > 0 }
            .compactMap { rule -> (Int, Int, Float)? in
                guard let m = rule.evaluate(environment: environment) else { return nil }
                return (m.sceneId, rule.priority, m.confidence)
            }
            .filter { $0.0 != currentId && isInstalled(sceneId: $0.0) }
            .sorted { ($0.1, $0.2) > ($1.1, $1.2) }
            .first?.0
    }

    /// A live cross-fade between dreams: fade the current one out, swap stems, fade
    /// the new one in. currentScene never goes nil, so the dream screen stays up and
    /// the entry countdown doesn't re-run — the change is seamless.
    private func morph(toSceneId id: Int) async {
        guard let next = availableScenes[id] else { return }
        isTransitioning = true
        print("🌗 Morphing \(currentScene?.info.name ?? "?") → \(next.info.name)")

        await audioEngine.fadeOutMaster(duration: 1.2)
        do {
            try await audioEngine.load(scene: next)
            audioEngine.play()               // fades master back in
            applyVoiceAugmentation(for: next.info.id)
            previousScene = currentScene
            currentScene = next
            dreamStartedAt = Date()
            collapseCandidateSince = nil
        } catch {
            print("⚠️ Morph failed: \(error.localizedDescription)")
        }
        isTransitioning = false
    }

    // MARK: - Collapse

    /// Set from the dream's infinity toggle — suppresses collapse entirely.
    public var isInfinite = false {
        didSet { if isInfinite { collapseCandidateSince = nil } }
    }

    /// How long a dream is safe from collapsing after it starts. Conditions wobble
    /// as sensors settle, and collapsing a second after entry feels broken.
    private let collapseGracePeriod: TimeInterval = 15

    /// How long a collapse condition must hold continuously before it fires. Without
    /// this, one stray accelerometer spike ends the dream.
    private let collapseSustain: TimeInterval = 4

    private var collapseCandidateSince: Date?

    /// Ends the dream when its own exit condition holds and nothing else matches.
    /// Called from liveEvaluate after morphing has been ruled out.
    private func evaluateCollapse(for environment: EnvironmentState, elapsed: TimeInterval, scene: SceneBundle) {
        guard let rule = CollapseRules.rule(for: scene.info.id),
              let reason = rule.shouldCollapse(environment: environment, elapsed: elapsed) else {
            collapseCandidateSince = nil    // condition recovered
            return
        }

        // Limbo and Reward end on a timer, not on the world changing — fire at once
        // rather than making the user hold a condition.
        let isTimed = scene.info.id == 310 || scene.info.id == 314
        if isTimed {
            collapse(reason: reason)
            return
        }

        guard let since = collapseCandidateSince else {
            collapseCandidateSince = Date()
            return
        }
        if Date().timeIntervalSince(since) >= collapseSustain {
            collapse(reason: reason)
        }
    }

    /// Dreams whose original bundles process the microphone (grainvoice / *mic* /
    /// record-buffer patches). Entering one routes your voice through the effect;
    /// gated on the Settings mic toggle and, in the engine, on headphones.
    private static let voiceDreams: Set<Int> = [302, 296, 301, 310, 316]

    private func applyVoiceAugmentation(for sceneId: Int) {
        let micEnabled = UserDefaults.standard.object(forKey: "micInputEnabled") as? Bool ?? true
        audioEngine.setVoiceAugmentation(micEnabled && Self.voiceDreams.contains(sceneId))
    }

    private func collapse(reason: String) {
        print("💤 Dream collapsed: \(reason)")
        collapseCandidateSince = nil
        lastCollapseReason = reason
        previousScene = currentScene
        currentScene = nil
        dreamStartedAt = nil
        noteDreamEnded()
        audioEngine.stop()
        // The dream collapsed — the map's Overture resumes underneath the kick.
        Task { await startMapAmbient() }
    }

    // MARK: - Rules Engine

    /// Induce — the world picks your dream. The only way into a dream.
    public func evaluateRules(for environment: EnvironmentState) async {
        guard !isTransitioning else { return }

        // Too many dreams within dreams: the fourth drops you into limbo, whatever
        // the world says.
        if shouldEnterLimbo, let limbo = availableScenes[310] {
            print("🌀 Three dreams in a row — falling into limbo")
            consecutiveDreams = 0
            try? await transition(to: limbo)
            return
        }

        // Run all rules, collect matches, sort by priority + confidence
        let matches = sceneRules
            .compactMap { rule -> (SceneMatch, Int)? in
                guard let match = rule.evaluate(environment: environment) else { return nil }
                return (match, rule.priority)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.confidence > rhs.0.confidence
            }

        // Fall through to the next-best match when the winner's scene isn't
        // installed — otherwise a missing bundle blocks induce entirely.
        for (match, _) in matches {
            if let current = currentScene, current.info.id == match.sceneId { return }

            guard let nextScene = availableScenes[match.sceneId] else {
                print("⚠️ Scene \(match.sceneId) matched but not installed. Reason: \(match.reason)")
                continue
            }

            print("🎬 Entering dream \(match.sceneId) — \(nextScene.info.name) [\(match.reason)]")
            try? await transition(to: nextScene)
            return
        }

        print("⚠️ No installed scene matched. Add .rjz files to the app.")
    }

    // MARK: - Manual Scene Control

    public func play(scene: SceneBundle) async throws {
        try await transition(to: scene)
    }

    public func play(sceneId: Int) async throws {
        guard let scene = availableScenes[sceneId] else {
            print("⚠️ Scene \(sceneId) not installed")
            return
        }
        try await transition(to: scene)
    }

    public func isInstalled(sceneId: Int) -> Bool {
        availableScenes[sceneId] != nil
    }

    public func revertToPreviousScene() async {
        guard let prev = previousScene else { return }
        try? await transition(to: prev)
    }

    /// Eject — leave the dream and return to the map. Clearing currentScene is what
    /// dismisses the dream; without it the rules would immediately re-enter the same
    /// dream on the next environment update.
    public func leaveDream() {
        previousScene = currentScene
        currentScene = nil
        dreamStartedAt = nil
        lastCollapseReason = nil
        collapseCandidateSince = nil
        noteDreamEnded()
        audioEngine.stop()
        // Back on the map — bring the Overture ambient back.
        Task { await startMapAmbient() }
    }

    // MARK: - Transition

    private func transition(to scene: SceneBundle) async throws {
        isTransitioning = true
        previousScene = currentScene
        // Show the dream screen with its title while the stems load — large scenes
        // take a moment, and the map shouldn't just freeze.
        pendingScene = scene

        // The map music keeps its own player; silence it while the dream plays.
        stopMapAmbient()
        try await audioEngine.load(scene: scene)
        audioEngine.play()
        applyVoiceAugmentation(for: scene.info.id)
        pendingScene = nil
        currentScene = scene
        dreamStartedAt = Date()
        lastCollapseReason = nil
        collapseCandidateSince = nil

        // First entry stamps the unlock with the date and city, as the original did.
        if unlockRecords[scene.info.id] == nil {
            unlockRecords[scene.info.id] = UnlockRecord(date: Date(), city: lastKnownCity)
            UnlockRecord.save(unlockRecords)
        }

        if sceneHistory.last?.id != scene.info.id {
            sceneHistory.append(scene.info)
        }

        isTransitioning = false
    }

    // MARK: - Limbo chain

    /// Records a dream ending, for the limbo chain. Dreams entered back-to-back
    /// count; leave a gap and the chain resets.
    private func noteDreamEnded() {
        if let last = lastDreamEndedAt, Date().timeIntervalSince(last) > limboChainWindow {
            consecutiveDreams = 0
        }
        consecutiveDreams += 1
        lastDreamEndedAt = Date()
    }

    /// "Three dreams in a row and fourth will send you to the undefined dream space
    /// of limbo." Checked at induce, before the rules run.
    private var shouldEnterLimbo: Bool {
        guard let last = lastDreamEndedAt else { return false }
        guard Date().timeIntervalSince(last) <= limboChainWindow else { return false }
        return consecutiveDreams >= 3 && isInstalled(sceneId: 310)
    }

    // MARK: - Environment Updates (matching original SceneController update* methods)

    public func updateCity(_ city: String) {
        currentCity = city
    }

    public func updateAirport(_ isAtAirport: Bool, name: String) {
        currentAirport = isAtAirport ? name : ""
    }

    public var availableSceneIds: [Int] {
        availableScenes.keys.sorted()
    }

    public var availableSceneList: [SceneBundle] {
        availableScenes.values.sorted { $0.info.name < $1.info.name }
    }
}

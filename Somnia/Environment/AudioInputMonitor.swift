import AVFoundation
import Combine

// MARK: - AudioInputMonitor
// Live microphone level. This is the sensor RjDj was built around — scenes
// listen to the room and react to it. EnvironmentState.isQuiet is fed from here.
//
// Runs its own AVAudioEngine for input, separate from the playback AudioEngine.
// Both share the AVAudioSession, which AudioEngine configures as .playAndRecord.

@MainActor
public final class AudioInputMonitor: ObservableObject {

    /// Smoothed input level, 0–1, mapped from dBFS.
    @Published public private(set) var level: Float = 0
    /// Unsmoothed level of the most recent buffer — use for transient/clap detection.
    @Published public private(set) var peak: Float = 0
    @Published public private(set) var isQuiet: Bool = true
    @Published public private(set) var isAuthorized: Bool = false

    /// Level below which the room counts as quiet. Hysteresis is applied around it.
    public var quietThreshold: Float = 0.08

    private let engine = AVAudioEngine()
    private var isRunning = false

    // dBFS window we care about. Below minDb is silence, above maxDb is loud.
    private let minDb: Float = -60
    private let maxDb: Float = -10

    // lop~-style one-pole smoothing, matching the fade feel of the audio graph.
    private var smoothed: Float = 0
    private let smoothing: Float = 0.15

    public init() {}

    // MARK: - Permission

    /// Requests mic access. Returns true if granted.
    @discardableResult
    public func requestPermission() async -> Bool {
        let granted = await AVAudioApplication.requestRecordPermission()
        isAuthorized = granted
        return granted
    }

    // MARK: - Start / Stop

    public func start() async {
        guard !isRunning else { return }

        guard await requestPermission() else {
            print("⚠️ Mic permission denied — scenes will run without room input")
            return
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        // A zero sample rate means the session hasn't given us an input route yet.
        guard format.sampleRate > 0 else {
            print("⚠️ No audio input route available")
            return
        }

        // 4096 frames ≈ 93ms at 44.1kHz → ~11 level updates/sec, which is plenty
        // for mood and keeps us off the main thread most of the time.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let rms = Self.rms(of: buffer) else { return }
            Task { @MainActor [weak self] in self?.ingest(rms: rms) }
        }

        do {
            try engine.start()
            isRunning = true
            print("✅ Mic monitor started at \(Int(format.sampleRate))Hz")
        } catch {
            input.removeTap(onBus: 0)
            print("❌ Mic monitor failed to start: \(error)")
        }
    }

    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        smoothed = 0
        level = 0
        peak = 0
        isQuiet = true
    }

    // MARK: - Level pipeline

    /// Runs on the audio thread — must stay allocation-free and lock-free.
    private nonisolated static func rms(of buffer: AVAudioPCMBuffer) -> Float? {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return nil }
        let frames = Int(buffer.frameLength)
        let samples = channels[0]

        var sum: Float = 0
        for i in 0..<frames {
            let s = samples[i]
            sum += s * s
        }
        return (sum / Float(frames)).squareRoot()
    }

    private func ingest(rms: Float) {
        let normalized = normalize(rms: rms)
        peak = normalized

        smoothed += (normalized - smoothed) * smoothing
        level = smoothed

        // Hysteresis — without it, a level hovering at the threshold flaps isQuiet
        // on and off and retriggers scene rules every buffer.
        if isQuiet, smoothed > quietThreshold * 1.5 {
            isQuiet = false
        } else if !isQuiet, smoothed < quietThreshold {
            isQuiet = true
        }
    }

    private func normalize(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        guard db.isFinite else { return 0 }
        let clamped = max(minDb, min(maxDb, db))
        return (clamped - minDb) / (maxDb - minDb)
    }
}

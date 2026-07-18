import AVFoundation

// MARK: - Sound
// The original's interaction sounds, shipped alongside the app.

public enum Sound: String, CaseIterable {
    case induceDown   = "inducebuttondown"
    case induceUp     = "inducebuttonup"
    case eject        = "ejectbuttonoff"
    case infinity     = "infinitybutton"
    case tileInfo     = "tile_info"
    case drawer       = "drawbar_button"
    case zoomIn       = "zoomin"
    case zoomOut      = "zoomout"
    case sceneStart   = "scene_start"
    case kick         = "kick"
    case mapView      = "mapview"
    case sliderUp     = "slider_up"
    case sliderDown   = "slider_down"
    case warning      = "warning"
    case idleProgress = "idle_progress"

    /// A few ship as both .m4a and .wav; the m4a is the one the app uses.
    var fileExtension: String {
        switch self {
        case .idleProgress: return "m4a"
        default: return "m4a"
        }
    }
}

// MARK: - SoundPlayer

@MainActor
public final class SoundPlayer {

    public static let shared = SoundPlayer()

    /// Interaction sounds are muted while a dream plays — they'd cut across the
    /// music, and the original keeps the dream uninterrupted.
    public var isMuted = false

    private var players: [Sound: AVAudioPlayer] = [:]

    private init() {}

    /// Decodes every sound up front. Without this the first play of each is late
    /// by the decode, which is very audible on a button press.
    public func preload() {
        for sound in Sound.allCases {
            // Sounds are extracted from the user's own copy at import, not shipped.
            let url = AssetStore.soundsDir.appendingPathComponent("\(sound.rawValue).\(sound.fileExtension)")
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("⚠️ Sound not imported: \(sound.rawValue).\(sound.fileExtension)")
                continue
            }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                players[sound] = player
            } catch {
                print("⚠️ Cannot load \(sound.rawValue): \(error.localizedDescription)")
            }
        }
        print("✅ Preloaded \(players.count)/\(Sound.allCases.count) sounds")
    }

    public func play(_ sound: Sound, volume: Float = 1.0) {
        guard !isMuted, let player = players[sound] else { return }
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    public func stop(_ sound: Sound) {
        players[sound]?.stop()
    }
}

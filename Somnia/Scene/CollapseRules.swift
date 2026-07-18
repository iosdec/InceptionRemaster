import Foundation

// MARK: - CollapseRule
//
// Every dream in the original has an exit condition as well as an entry one, taken
// from its `currenttext<id>` string ("You can collapse this dream by staying still",
// "If you leave the airport this dream will collapse"). A dream runs until the world
// stops matching it — that's what makes it feel alive rather than like a playlist.

public protocol CollapseRule {
    var sceneId: Int { get }
    /// Non-nil means the dream should collapse; the string is the reason, for the UI.
    func shouldCollapse(environment: EnvironmentState, elapsed: TimeInterval) -> String?
}

/// Shared thresholds with the entry rules. A dream shouldn't collapse the instant
/// you dip below the level that let you in, so the collapse bounds sit outside the
/// entry bounds — this hysteresis is what stops dreams flickering in and out.
enum CollapseBounds {
    static let becameActive: Float = 0.24    // entry rules use 0.18
    static let becameStill: Float = 0.04     // entry rules use 0.06
    static let slowedDown: Double = 5        // entry needs > 8 m/s
}

/// 296 Action — "You can collapse this dream by staying still."
struct ActionCollapse: CollapseRule {
    let sceneId = 296
    func shouldCollapse(environment e: EnvironmentState, elapsed: TimeInterval) -> String? {
        e.accelerationMagnitude < CollapseBounds.becameStill ? "You stopped moving." : nil
    }
}

/// 297 Sunshine — "collapse by being active or by the weather at your location changing"
struct SunshineCollapse: CollapseRule {
    let sceneId = 297
    func shouldCollapse(environment e: EnvironmentState, elapsed: TimeInterval) -> String? {
        if e.accelerationMagnitude > CollapseBounds.becameActive { return "You started moving." }
        if !e.isSunny { return "The sun went in." }
        return nil
    }
}

/// 298 Full Moon — "collapse when the moon is no longer full or at day break"
struct FullMoonCollapse: CollapseRule {
    let sceneId = 298
    func shouldCollapse(environment e: EnvironmentState, elapsed: TimeInterval) -> String? {
        if !e.isFullMoon { return "The moon is no longer full." }
        if e.isDaytime { return "Day break." }
        return nil
    }
}

/// 300 Sleep — "collapse on day break, if you move or make noise"
struct SleepCollapse: CollapseRule {
    let sceneId = 300
    func shouldCollapse(environment e: EnvironmentState, elapsed: TimeInterval) -> String? {
        if e.isDaytime { return "Day break." }
        if e.accelerationMagnitude > CollapseBounds.becameActive { return "You moved." }
        if !e.isQuiet { return "You made noise." }
        return nil
    }
}

/// 301 Travelling — "If you slow down this dream will collapse."
struct TravellingCollapse: CollapseRule {
    let sceneId = 301
    func shouldCollapse(environment e: EnvironmentState, elapsed: TimeInterval) -> String? {
        e.speed < CollapseBounds.slowedDown ? "You slowed down." : nil
    }
}

/// 302 Quiet — "even the slightest movement will collapse this dream"
struct QuietCollapse: CollapseRule {
    let sceneId = 302
    func shouldCollapse(environment e: EnvironmentState, elapsed: TimeInterval) -> String? {
        if e.accelerationMagnitude > CollapseBounds.becameActive { return "You moved." }
        if !e.isQuiet { return "It got loud." }
        return nil
    }
}

/// 313 Still — "collapse by being active or going to a quiet environment"
struct StillCollapse: CollapseRule {
    let sceneId = 313
    func shouldCollapse(environment e: EnvironmentState, elapsed: TimeInterval) -> String? {
        if e.accelerationMagnitude > CollapseBounds.becameActive { return "You started moving." }
        if e.isQuiet { return "It went quiet." }
        return nil
    }
}

/// 315 Airport — "If you leave the airport this dream will collapse."
struct AirportCollapse: CollapseRule {
    let sceneId = 315
    func shouldCollapse(environment e: EnvironmentState, elapsed: TimeInterval) -> String? {
        !e.isAtAirport ? "You left the airport." : nil
    }
}

/// 317 Shared — "If you dream alone this dream will collapse."
/// Inert until nearby-dreamer detection exists.
struct SharedCollapse: CollapseRule {
    let sceneId = 317
    func shouldCollapse(environment e: EnvironmentState, elapsed: TimeInterval) -> String? { nil }
}

/// 310 Limbo — "You will be locked in this dream for 3'40"."
/// The only dream you cannot leave; it ends on its own.
struct LimboCollapse: CollapseRule {
    let sceneId = 310
    static let duration: TimeInterval = 220   // 3'40"
    func shouldCollapse(environment e: EnvironmentState, elapsed: TimeInterval) -> String? {
        elapsed >= Self.duration ? "You surfaced from limbo." : nil
    }
}

/// 314 Reward — "This dream feels long whilst you are in it, but only lasts short time."
struct RewardCollapse: CollapseRule {
    let sceneId = 314
    func shouldCollapse(environment e: EnvironmentState, elapsed: TimeInterval) -> String? {
        elapsed >= 180 ? "The reward faded." : nil
    }
}

public enum CollapseRules {
    /// 0 Reverie and 316 Africa have no collapse condition in the original — they
    /// play through and are left via eject.
    static let all: [any CollapseRule] = [
        ActionCollapse(), SunshineCollapse(), FullMoonCollapse(), SleepCollapse(),
        TravellingCollapse(), QuietCollapse(), StillCollapse(), AirportCollapse(),
        SharedCollapse(), LimboCollapse(), RewardCollapse(),
    ]

    static func rule(for sceneId: Int) -> (any CollapseRule)? {
        all.first { $0.sceneId == sceneId }
    }
}

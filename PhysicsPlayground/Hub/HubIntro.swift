//  HubIntro.swift — the home's arrival choreography as pure functions of time (no RealityKit).
//  The calibration bell is baked into a WAV at a fixed second: `landingTime` must equal it
//  exactly (`HubIntroTests` pins the pair). The beat is a MINIMUM, not a loading measurement;
//  Reduce Motion skips the whole timeline (root dissolve is the entrance then).

import Foundation
import simd

enum HubIntro {

    // MARK: The clock

    /// The wordmark's own fade, from the first frame.
    static let titleFade = 0.7
    /// How long the mark holds centre stage, loading or not.
    static let minimumBeat = 2.0
    /// The flight back to the wall.
    static let flightDuration = 0.65
    /// The instant the mark lands — and the bell strikes. Pinned to `SoundPalette.calibrationLanding` by test.
    static let landingTime = minimumBeat + flightDuration

    /// Cascade starts a little before the mark lands — the room rises to meet it.
    static let cascadeStart = minimumBeat + flightDuration * 0.55
    static let terraceFade = 0.4
    /// Per-exhibit stagger along the arcs, and each pop's own ramp.
    static let exhibitStagger = 0.09
    static let exhibitFade = 0.32
    /// Door signs arrive last — must exceed the sixth miniature's cue
    /// (cascadeStart + 0.12 + 5 × stagger = +0.57); the ordering test holds it.
    static let signDelay = 0.7
    static let signFade = 0.4

    /// Opening pose: eye height for a standing wearer, clear of the catalog window.
    static let titlePose = SIMD3<Float>(0, 1.58, -1.35)
    /// And a shade larger, so the flight reads as settling into place.
    static let titlePoseScale: Float = 1.14

    // MARK: The curves

    /// 0 → 1 over [start, start + span], eased at both ends.
    private static func ramp(_ time: Double, from start: Double,
                             over span: Double) -> Float {
        let x = min(max((time - start) / max(span, 1e-6), 0), 1)
        return Float(x * x * (3 - 2 * x))
    }

    /// The title's fade, from the first frame.
    static func titleOpacity(at time: Double) -> Float {
        ramp(time, from: 0, over: titleFade)
    }

    /// 0 = the centred opening pose, 1 = the wall anchor.
    static func titleBlend(at time: Double) -> Float {
        ramp(time, from: minimumBeat, over: flightDuration)
    }

    /// The terraces, podium and rail — the stage the rest stands on.
    static func stageOpacity(at time: Double) -> Float {
        ramp(time, from: cascadeStart, over: terraceFade)
    }

    /// One miniature's arrival, staggered by its slot along the arcs.
    static func exhibitOpacity(slot: Int, at time: Double) -> Float {
        ramp(time, from: cascadeStart + 0.12 + Double(slot) * exhibitStagger,
             over: exhibitFade)
    }

    /// Rising through the last tenth of scale as it fades up, so arriving reads as landing.
    static func exhibitScale(slot: Int, at time: Double) -> Float {
        0.88 + 0.12 * exhibitOpacity(slot: slot, at: time)
    }

    /// The domain signs, once their terraces are lit.
    static func signOpacity(at time: Double) -> Float {
        ramp(time, from: cascadeStart + signDelay, over: signFade)
    }

    /// True once every curve has landed at 1 — the scene then removes its intro
    /// components and stops touching them (per-frame path goes quiet).
    static func isFinished(at time: Double, exhibitCount: Int) -> Bool {
        let lastExhibit = cascadeStart + 0.12
            + Double(max(exhibitCount - 1, 0)) * exhibitStagger + exhibitFade
        let lastSign = cascadeStart + signDelay + signFade
        return time >= max(landingTime, max(lastExhibit, lastSign))
    }
}

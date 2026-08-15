//
//  HubIntro.swift
//  Physics Playground — Hub
//
//  The home's arrival, as a pure timeline: the wordmark alone, centred
//  and fading in; a held beat; the flight back to its wall position;
//  and the room cascading up behind it — terraces first, then the
//  miniatures in a wave along the arcs, then the door signs.
//
//  PURE FUNCTIONS OF TIME, deliberately. The scene applies these
//  numbers; it never computes them, so the whole choreography is
//  unit-testable without RealityKit — which is the only way the one
//  cross-cutting promise here can be held by a test: the calibration
//  sound's bell is baked into a WAV at a fixed second, and
//  `landingTime` must equal it exactly or the room lands out of sync
//  with its own chime (`HubIntroTests` pins the pair).
//
//  THE BEAT IS A MINIMUM, NOT A MEASUREMENT (owner's call,
//  2026-08-14). A warm launch builds the gallery in well under a
//  second, and an intro gated strictly on loading would flash by
//  before it reads; the beat gives the title its moment and hides
//  whatever loading there is inside it. Reduce Motion skips the whole
//  timeline — the scene's existing root dissolve is the entrance then,
//  with no flying title and no wave.
//

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
    /// The instant the mark lands — and the bell strikes. Pinned to
    /// `SoundPalette.calibrationLanding` by test.
    static let landingTime = minimumBeat + flightDuration

    /// The cascade starts a little before the mark lands, so the room
    /// is rising to meet it rather than waiting for it.
    static let cascadeStart = minimumBeat + flightDuration * 0.55
    static let terraceFade = 0.4
    /// Per-exhibit stagger along the arcs, and each pop's own ramp.
    static let exhibitStagger = 0.09
    static let exhibitFade = 0.32
    /// The door signs arrive last — after the SIXTH miniature's cue
    /// (cascadeStart + 0.12 + 5 × stagger = +0.57), which is what
    /// "last" has to mean with six exhibits in the wave. 0.5 was
    /// before it, and the ordering test said so.
    static let signDelay = 0.7
    static let signFade = 0.4

    /// Where the wordmark holds its opening pose: centred in the view,
    /// nearer and lower than the wall anchor — eye height for a
    /// standing wearer, clear of the catalog window.
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

    /// The pop that goes with it: rising through the last tenth of
    /// scale as it fades up, so arriving reads as landing.
    static func exhibitScale(slot: Int, at time: Double) -> Float {
        0.88 + 0.12 * exhibitOpacity(slot: slot, at: time)
    }

    /// The domain signs, once their terraces are lit.
    static func signOpacity(at time: Double) -> Float {
        ramp(time, from: cascadeStart + signDelay, over: signFade)
    }

    /// True once every curve has landed at 1 — the scene then removes
    /// its intro components and stops touching them, per the house
    /// rule that the per-frame path goes quiet when nothing changes.
    static func isFinished(at time: Double, exhibitCount: Int) -> Bool {
        let lastExhibit = cascadeStart + 0.12
            + Double(max(exhibitCount - 1, 0)) * exhibitStagger + exhibitFade
        let lastSign = cascadeStart + signDelay + signFade
        return time >= max(landingTime, max(lastExhibit, lastSign))
    }
}

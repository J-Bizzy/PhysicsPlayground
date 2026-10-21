//
//  Opening.swift
//  Physics Playground — Hub
//
//  The opening's clock, as the rest of the home reads it: when the worlds
//  land and the bell strikes, when the labs, their names and the wordmark
//  arrive, and when it is over. The opening itself — "Birth of a System"
//  (2026-10-20) — is `OpeningPlan` (the physics, solved once) drawn by
//  `OpeningStage`. Until then it was a field of charged particles that
//  fell through crossed fields, rippled as deep water and settled onto
//  the portals' rims; the git history keeps it.
//

import Foundation

nonisolated enum Opening {
    /// Standard gravity, m/s² — the same g everywhere in the app (the
    /// wordmark's letters fall with it as they arrive).
    static let g = 9.80665

    /// The instant the worlds reach their plinths — and the bell strikes.
    /// Pinned to `SoundPalette.calibrationLanding` by test.
    static let landingTime = OpeningPlan.landingTime
    /// When everything has arrived and the per-frame path can go quiet.
    static let duration = OpeningPlan.duration

    static func isFinished(at time: Double) -> Bool { OpeningPlan.isFinished(at: time) }

    /// The labs on their plinths fade up as the worlds land.
    static func portalOpacity(at time: Double) -> Float { OpeningPlan.labOpacity(at: time) }
    /// …growing out of their worlds into place, exactly 1 once arrived.
    static func portalScale(at time: Double) -> Float { OpeningPlan.labScale(at: time) }
    /// The labels, the More and the wordmark's footing come last.
    static func labelOpacity(at time: Double) -> Float { OpeningPlan.labelOpacity(at: time) }
    /// The machined wordmark rises the last few centimetres as it fades up.
    static func titleOffset(at time: Double) -> Float { OpeningPlan.titleOffset(at: time) }
}

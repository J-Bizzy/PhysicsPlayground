//
//  Opening.swift
//  Physics Playground — Hub
//
//  The home's arrival, as pure functions of its clock: the seven labs rise
//  into place one after another, left to right — each a few centimetres up
//  into its spot as it fades up and grows to full size, easing in with no
//  overshoot — their names come up under them, one soft tone sounds as the
//  last settles, and the wordmark's letters fall and swing into theirs
//  (`HubTitleMotion`). About a second and a half; a walk back from a lab,
//  or Reduce Motion, is a plain fade instead.
//
//  Until 2026-10-21 the opening was "Birth of a System" — a star forming,
//  its worlds flying Kepler transfers onto the labs' plinths — and before
//  that a field of charged particles. Both are in the git history.
//

import Foundation

nonisolated enum Opening {
    /// Standard gravity, m/s² — the same g everywhere in the app (the
    /// wordmark's letters fall with it as they arrive).
    static let g = 9.80665

    // MARK: The labs

    /// Between one lab starting to rise and the next, left to right.
    static let stagger = 0.1
    /// How long one lab takes to rise into place.
    static let rise = 0.6
    /// How far below its place a lab starts, metres.
    static let riseHeight: Float = 0.06
    /// How large it starts, as a share of its size.
    static let startScale: Float = 0.9
    /// The share of its rise a lab takes to fade up.
    static let fadeShare = 0.6

    /// How many labs the home stands; the arrival is timed for them.
    static let labCount = 7

    /// When the last lab is in place.
    static let labsArrived = Double(labCount - 1) * stagger + rise

    /// How far lab `index` (left to right) has come at `t`, 0…1: eased out,
    /// so it moves most at first and comes to rest in its place without
    /// passing it. Exactly 1 from its arrival on.
    static func progress(ofLab index: Int, at t: Double) -> Double {
        let x = min(max((t - Double(index) * stagger) / rise, 0), 1)
        let left = 1 - x
        return 1 - left * left * left
    }

    /// How far lab `index` has faded up: nothing before it starts, whole
    /// before it has risen.
    static func labOpacity(_ index: Int, at t: Double) -> Float {
        let x = min(max((t - Double(index) * stagger) / (rise * fadeShare), 0), 1)
        return Float(x * x * (3 - 2 * x))
    }

    /// Lab `index`'s size, as a share of its own.
    static func labScale(_ index: Int, at t: Double) -> Float {
        startScale + (1 - startScale) * Float(progress(ofLab: index, at: t))
    }

    /// How far below its place lab `index` stands, metres (≤ 0).
    static func labLift(_ index: Int, at t: Double) -> Float {
        -riseHeight * Float(1 - progress(ofLab: index, at: t))
    }

    // MARK: The names, the More and the tone

    /// How long a name takes to come up, from halfway through its lab's rise.
    static let nameFade = 0.3

    /// Lab `index`'s name: up as its lab settles.
    static func nameOpacity(_ index: Int, at t: Double) -> Float {
        let start = Double(index) * stagger + rise / 2
        let x = min(max((t - start) / nameFade, 0), 1)
        return Float(x * x * (3 - 2 * x))
    }

    /// The More (and the machined wordmark's rule, when it stands in): up
    /// with the last names.
    static func moreOpacity(at t: Double) -> Float {
        let x = min(max((t - (labsArrived - nameFade)) / nameFade, 0), 1)
        return Float(x * x * (3 - 2 * x))
    }

    /// The one soft tone, as the last lab comes to rest.
    static let toneTime = labsArrived - 0.15

    // MARK: The wordmark

    /// When the first "Physics" letter is let go; "Playground" follows.
    static let titleStart = 0.25
    /// The machined wordmark's rise, when it stands in for the living one:
    /// metres below its place at the start, and how long it takes.
    static let titleRise: Float = 0.05
    static func titleOffset(at t: Double) -> Float {
        let x = min(max(t / labsArrived, 0), 1)
        let left = 1 - x
        return -titleRise * Float(left * left * left)
    }

    /// The living wordmark's first glint, once its letters are down.
    static let firstGlint = labsArrived + 0.4

    // MARK: Done

    /// When everything has arrived and the per-frame path can go quiet.
    static let duration = labsArrived + nameFade

    static func isFinished(at time: Double) -> Bool { time >= duration }
}

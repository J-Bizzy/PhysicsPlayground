//
//  GaussGrab.swift
//  Physics Playground — Electric Fields module
//
//  The flux meter's own gesture: grab its edge and the surface passes
//  through your fingertip.
//
//  This is the interaction law taken literally. "A quantity with physical
//  extent is changed by changing that extent" — and a Gauss surface is
//  nothing BUT extent: a radius, and (for the open disc) a facing. Both
//  used to be sliders and a segmented picker, three disclosure levels deep
//  in a window panel, which is a strange place to keep the size of a thing
//  you are holding.
//
//  One formula does both, and that is the pleasing part:
//
//      û  = normalise(hand − centre)
//      r′ = clamp(‖hand − centre‖)              // both shapes
//      n′ = normalise(n − (n·û)û)               // the disc only
//
//  `n′` is the old normal with its component along `û` projected out, so it
//  is perpendicular to `û` — which is exactly the statement "your fingertip
//  is on the rim". Pull outward in the disc's own plane and it grows; swing
//  your hand out of that plane and it tilts. Neither is a mode, and there
//  is nothing to switch between: they are two components of one hand
//  position, resolved every frame from scratch.
//
//  ABSOLUTE, like `SpatialTrackControl` and unlike `Bloom`'s grip: nothing
//  accumulates, so the rim cannot drift away from the fingers over a long
//  drag, and letting go and grabbing again changes nothing.
//
//  Why the tilt had to exist at all: the panel has been instructing users
//  to "tilt it edge-on to the field and the flux falls to zero" since the
//  disc was written, and `gaussSurfaceNormal` had exactly two writers in
//  the entire tree — its own declaration and `reset()`, both setting
//  (0,0,1). The app was describing a gesture it did not have.
//

import Foundation
import simd

enum GaussGrab {

    /// What a pinch near the flux meter was aiming at.
    enum Grab: Equatable {
        /// The edge — resize, and tilt if it is a disc.
        case skin
        /// Inside the surface. NOT the meter's: a bubble at full size is
        /// over a metre across, and the interesting thing inside it is
        /// usually a charge. The caller resolves the contents first and
        /// only moves the meter if there is nothing in there.
        case inside
        /// Nowhere near it.
        case miss
    }

    /// How thick the grabbable shell is, for a surface of this radius.
    ///
    /// A fraction alone fails at the small end — 25% of the 8 cm minimum
    /// radius is a 2 cm shell, which is under the positional noise of a
    /// tracked hand — so it takes whichever of the two is thicker. A
    /// constant alone fails at the large end, where 4 cm of a 55 cm bubble
    /// is a sliver you would have to aim at.
    static func skinBand(forRadius radius: Double) -> Double {
        max(radius * 0.25, 0.04)
    }

    static func classify(hand: SIMD3<Double>,
                         center: SIMD3<Double>,
                         radius: Double) -> Grab {
        let distance = simd_distance(hand, center)
        let band = skinBand(forRadius: radius)
        if distance > radius + band { return .miss }
        if distance >= radius - band { return .skin }
        return .inside
    }

    /// The radius that puts the surface's edge under the hand.
    static func radius(forHand hand: SIMD3<Double>,
                       center: SIMD3<Double>,
                       range: ClosedRange<Double>) -> Double {
        let distance = simd_distance(hand, center)
        return min(max(distance, range.lowerBound), range.upperBound)
    }

    /// The facing that puts the hand on the disc's rim.
    ///
    /// Returns `normal` unchanged in the one case with no answer: a hand on
    /// the disc's AXIS, where "the rim passes through here" describes every
    /// orientation equally and the projection collapses to nothing. Leaving
    /// the disc where it was is the only non-arbitrary option — inventing a
    /// facing would make it snap to a direction the user did not choose.
    static func normal(forHand hand: SIMD3<Double>,
                       center: SIMD3<Double>,
                       normal current: SIMD3<Double>) -> SIMD3<Double> {
        let toHand = hand - center
        let reach = simd_length(toHand)
        guard reach > 1e-9 else { return current }
        let unit = toHand / reach

        let projected = current - simd_dot(current, unit) * unit
        let magnitude = simd_length(projected)
        // Below this the hand is within ~0.06 rad of the axis and the
        // projection is numerical noise pointing anywhere at all.
        guard magnitude > 1e-3 else { return current }
        return projected / magnitude
    }
}

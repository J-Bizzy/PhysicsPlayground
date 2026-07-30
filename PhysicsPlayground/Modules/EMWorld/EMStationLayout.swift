//
//  EMStationLayout.swift
//  Physics Playground — Electricity & Magnetism
//
//  Where each bench stands in the merged E&M world.
//
//  Circuits and Magnetism were written as separate modules, so both
//  were authored around the SAME patch of room: the bench pivots at
//  (0, 1.25, −0.85) and the magnet region centres on (0, 1.35, −0.70).
//  Co-presenting them is therefore a layout problem before it is
//  anything else — two apparatus that each believe they own the space
//  in front of the user.
//
//  This is the arc that separates them. Each station keeps its own
//  interior coordinates untouched (every position, clamp, and seed in
//  those two modules stays exactly as written) and the world moves the
//  station's display root by a constant offset. A constant translation
//  is safe here for the same reason lab placement is: every grab in
//  this app moves a body by hand DISPLACEMENT, which a fixed
//  translation leaves untouched.
//
//  The third slot is REAL but unbuilt. The two-lab plan ends with
//  Electric Fields in this world too, so its seat is reserved and
//  bounded here rather than discovered later — `isBuilt` is what keeps
//  it off the arc until its station exists.
//

import simd

/// One apparatus in the E&M world.
enum EMStation: String, CaseIterable, Identifiable {
    /// The Circuit Workshop bench — left of the user.
    case bench
    /// The magnetic field volume — right of the user.
    case field
    /// Electric Fields. Reserved, not yet built (see `isBuilt`).
    case charges

    var id: String { rawValue }

    /// Whether this station actually renders today. The reserved seat
    /// is laid out and bounds-checked but never installed.
    var isBuilt: Bool { self != .charges }
}

enum EMStationLayout {
    /// Where each module ALREADY thinks its apparatus lives — the
    /// anchors baked into the modules themselves. Kept in sync with
    /// the real constants by `EMStationLayoutTests`, which reads
    /// `CircuitsRenderer.benchPivot`, `MagnetismModel.regionCenter`,
    /// and `FieldModel.regionCenter` and fails if any drifts from here.
    static func nativeAnchor(_ station: EMStation) -> SIMD3<Double> {
        switch station {
        case .bench:   SIMD3(0, 1.25, -0.85)
        case .field:   SIMD3(0, 1.35, -0.70)
        case .charges: SIMD3(0, 1.35, -0.90)
        }
    }

    /// Where the station stands in the merged world. The two built
    /// stations sit symmetrically about the user's centre line at a
    /// comfortable turn of the head; the reserved seat is centre-rear,
    /// far enough back that its volume clears both.
    static func center(_ station: EMStation) -> SIMD3<Double> {
        switch station {
        case .bench:   SIMD3(-0.72, 1.25, -0.90)
        case .field:   SIMD3(0.72, 1.35, -0.90)
        case .charges: SIMD3(0, 1.35, -2.25)
        }
    }

    /// The volume the station may draw and wander inside, as a half-size
    /// about `center`. These are the numbers the disjointness test
    /// enforces: no station's box may touch another's, because that is
    /// exactly how a magnet ends up floating inside the circuit bench.
    ///
    /// The field box is wider than its magnet clamp (0.62) because the
    /// compass grid is drawn from `MagnetismModel.regionHalfExtent`
    /// rather than the clamp, and reaches slightly further.
    static func halfExtents(_ station: EMStation) -> SIMD3<Double> {
        switch station {
        case .bench:   SIMD3(0.72, 0.50, 0.38)
        case .field:   SIMD3(0.65, 0.85, 0.66)
        case .charges: SIMD3(0.62, 0.65, 0.60)
        }
    }

    /// The display translation that carries a station's root from where
    /// its module authored it to where the world wants it.
    static func offset(_ station: EMStation) -> SIMD3<Float> {
        SIMD3<Float>(center(station) - nativeAnchor(station))
    }

    /// Which way is AWAY from the middle of the world, along x.
    ///
    /// Both modules park their side furniture — Circuits' layer bank,
    /// Magnetism's spawn well — on a hard-coded side that was fine when
    /// each owned the room alone. On the arc, the sides that used to be
    /// free now face each other across the middle, so a bank and a well
    /// would end up in the same half-metre. Furniture reads this and
    /// hangs on the station's outer flank instead.
    static func outboard(_ station: EMStation) -> Double {
        switch station {
        case .bench:   -1
        case .field:    1
        // Centre-rear has no outer flank; its furniture stays put.
        case .charges:  1
        }
    }

    /// The min/max corners of a station's volume, in world coordinates.
    static func bounds(_ station: EMStation)
    -> (min: SIMD3<Double>, max: SIMD3<Double>) {
        let c = center(station), h = halfExtents(station)
        return (c - h, c + h)
    }

    /// Whether two stations' volumes keep at least `margin` between
    /// them on some axis. Separation on ONE axis is enough — these are
    /// axis-aligned boxes, so a single clear axis means no overlap.
    static func areSeparated(
        _ a: EMStation, _ b: EMStation, margin: Double = 0
    ) -> Bool {
        let (aMin, aMax) = bounds(a)
        let (bMin, bMax) = bounds(b)
        for axis in 0..<3 where aMin[axis] - bMax[axis] >= margin
            || bMin[axis] - aMax[axis] >= margin {
            return true
        }
        return false
    }
}

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
//  ── Why the stations are a step away rather than at arm's length ──
//
//  Three apparatus want about four metres of width and a room does not
//  have four metres of arm's reach. The boxes are axis-aligned, so
//  clearance on ONE axis is enough, and x is the only axis available:
//  y would put a station on the floor or the ceiling, and separating in
//  z pushes a bench two and a quarter metres out — which is where the
//  charges seat was reserved, and it is out of reach for an apparatus
//  whose whole grammar is drag-a-charge.
//
//  So the three sit side by side in x with the charges in the middle,
//  and each station's CENTRE lands about 1.5 m away — near face about
//  1.1 m. You turn and take a step to work at one. That is a real cost,
//  chosen over the alternative of halving the electrostatics volume
//  (which would have capped capacitor plate separation at 0.4 m against
//  a range that goes to 1.0), and it is the cost the focus mechanic
//  makes legible: the bench you are standing at is lit and the others
//  stand back, so "which one am I working on" is answered by the room.
//
//  The middle seat needs NO offset at all — Electric Fields already
//  believes it is centred on the world's centre line, so its station is
//  the one apparatus in this app that stands exactly where its module
//  put it.
//

import PhysicsCore
import simd

/// One apparatus in the E&M world.
enum EMStation: String, CaseIterable, Identifiable {
    /// The Circuit Workshop bench — left of the user.
    case bench
    /// The magnetic field volume — right of the user.
    case field
    /// Electric Fields — the centre seat, straight ahead.
    case charges

    var id: String { rawValue }

    /// What the panel and the legend call this bench.
    var title: String {
        switch self {
        case .bench:   "Circuit bench"
        case .field:   "Magnetic field"
        case .charges: "Electric charges"
        }
    }
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

    /// Where the station stands in the merged world: charges straight
    /// ahead, the circuit bench to the left, the magnetic field to the
    /// right, all at the same depth. The x values are not chosen for
    /// looks — they are the nearest seats that clear the neighbouring
    /// box by the 6 cm margin `EMStationLayoutTests` enforces, so
    /// pulling either flank inward is a test failure, not a taste
    /// argument.
    static func center(_ station: EMStation) -> SIMD3<Double> {
        switch station {
        case .bench:   SIMD3(-1.40, 1.25, -0.90)
        case .charges: SIMD3(0, 1.35, -0.90)
        case .field:   SIMD3(1.33, 1.35, -0.90)
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
    ///
    /// Every one of these is now BACKED by a clamp in the model that
    /// owns it — `CircuitsModel.buildHalfExtents`,
    /// `FieldModel.regionHalfExtents`, `MagnetismModel.regionHalfExtents`
    /// — rather than being a footprint the apparatus was trusted to
    /// respect. Before co-presence that trust cost nothing; with three
    /// benches in one room an unclamped drag ends inside a neighbour.
    static func halfExtents(_ station: EMStation) -> SIMD3<Double> {
        switch station {
        case .bench:   SIMD3(0.72, 0.50, 0.38)
        // Tall on purpose: x is the axis that keeps the stations apart,
        // so y buys no separation and a short box would only take
        // working volume away. 1.20 puts the floor of the box exactly
        // at `FieldModel.floorClearance`, the height charges were
        // already stopped at — so clamping to the station costs this
        // bench nothing vertically.
        case .charges: SIMD3(0.62, 1.20, 0.62)
        case .field:   SIMD3(0.65, 0.85, 0.66)
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
        // The middle seat has no outer flank — both its sides face a
        // neighbour. It has no side furniture either (its only control
        // is the per-charge ring, which rides the charge), so nothing
        // reads this; it answers +1 rather than trapping, because a
        // layout question should not be able to crash a render.
        case .charges:  1
        }
    }

    /// A station's volume, as the box every invariant is asserted
    /// against. The box math itself lives in PhysicsCore so the layout
    /// tests run in `swift test` rather than booting a simulator, and so
    /// the Mechanics world asserts against exactly the same functions.
    static func box(_ station: EMStation) -> StationBox {
        StationBox(center: center(station), halfExtents: halfExtents(station))
    }

    /// The min/max corners of a station's volume, in world coordinates.
    static func bounds(_ station: EMStation)
    -> (min: SIMD3<Double>, max: SIMD3<Double>) {
        let b = box(station)
        return (b.minimum, b.maximum)
    }

    /// Whether two stations' volumes keep at least `margin` between
    /// them on some axis. Separation on ONE axis is enough — these are
    /// axis-aligned boxes, so a single clear axis means no overlap.
    static func areSeparated(
        _ a: EMStation, _ b: EMStation, margin: Double = 0
    ) -> Bool {
        box(a).isSeparated(from: box(b), margin: margin)
    }
}

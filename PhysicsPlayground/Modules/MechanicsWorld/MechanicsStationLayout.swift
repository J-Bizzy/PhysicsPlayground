//
//  MechanicsStationLayout.swift
//  Physics Playground — Mechanics & Energy
//
//  Where each apparatus stands in the merged Mechanics world.
//
//  ── One station may not move at all ──
//
//  The E&M world could seat all three of its benches wherever it liked,
//  because none of them knows the room exists. Projectiles does. It
//  feeds `appModel.room.collisionWalls` and `room.bounds` straight into
//  the solver and catches balls at `room.fingertips`: its physics space
//  IS the user's real scanned room, one to one. A display offset there
//  would leave every ball bouncing off a wall that is not where the
//  bounce is drawn — and it would do it silently, forever.
//
//  So `offset(.projectile)` is `.zero` by construction and by test. The
//  pendulum rig, which knows nothing about walls, moves to make room.
//
//  ── Seat and volume are separate here ──
//
//  `EMStationLayout` derives a station's box from its seat, because its
//  three benches happen to be centred on the anchors they were authored
//  around. A pendulum is not: it hangs from a pivot at head height and
//  its bob swings down past your knees, so the point it is PLACED by
//  and the volume it OCCUPIES are a metre apart vertically. Forcing one
//  to be the centre of the other would either move the rig down 0.8 m
//  or declare a box reaching through the ceiling. They are two facts,
//  so they are two functions.
//

import PhysicsCore
import simd

/// One apparatus in the Mechanics world.
enum MechanicsStation: String, CaseIterable, Identifiable {
    /// The launcher, its hoops, and the balls — dead centre, and the
    /// one apparatus in the app that may never be translated.
    case projectile
    /// The pendulum rig, to the left.
    case pendulum
    /// Orbital mechanics. Reserved, not yet built — it is not a seat on
    /// this arc at all but the volume the arc stands inside, which is
    /// why it has a `kind` rather than a place in the line.
    case orbital

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projectile: "Projectile bench"
        case .pendulum:   "Pendulum rig"
        case .orbital:    "Orbital mechanics"
        }
    }

    /// Whether this station stands beside the others, or around them.
    enum Kind {
        /// A bench on the arc. Must be disjoint from every other arc
        /// station.
        case arc
        /// An apparatus LARGER than the room, which the arc stations
        /// stand inside. Cannot be disjoint from anything, so it is
        /// held to a containment invariant instead.
        case ambient
    }

    var kind: Kind { self == .orbital ? .ambient : .arc }

    /// Whether this station renders today.
    var isBuilt: Bool { self != .orbital }
}

enum MechanicsStationLayout {
    /// Where each module already believes its apparatus is placed —
    /// checked against the modules' own constants by
    /// `MechanicsStationLayoutTests`.
    static func nativeAnchor(_ station: MechanicsStation) -> SIMD3<Double> {
        switch station {
        case .projectile: KinematicsModel.launcherHome
        case .pendulum:   PendulumsModel.defaultPivot
        case .orbital:    SIMD3(0, 1.25, -1.2)
        }
    }

    /// Where the station's display root is placed.
    ///
    /// The projectile bench's seat IS its native anchor, which is what
    /// makes its offset zero. The pendulum rig moves left to clear it.
    static func seat(_ station: MechanicsStation) -> SIMD3<Double> {
        switch station {
        case .projectile: nativeAnchor(.projectile)
        case .pendulum:   SIMD3(-1.75, 2.0, -1.1)
        case .orbital:    nativeAnchor(.orbital)
        }
    }

    /// The volume the station occupies, as a centre — NOT the same as
    /// its seat; see the header.
    static func center(_ station: MechanicsStation) -> SIMD3<Double> {
        switch station {
        // Centred on the apparatus, not on the launcher: the hoops
        // spawn 1.3 m to the launcher's right.
        case .projectile: SIMD3(0, 1.35, -1.2)
        // Centred between the pivot (y = 2.0) and the lowest a bob can
        // hang (2.0 − lengthRange.upperBound = 0.4).
        case .pendulum:   SIMD3(-1.75, 1.20, -1.1)
        case .orbital:    SIMD3(0, 1.25, -1.2)
        }
    }

    static func halfExtents(_ station: MechanicsStation) -> SIMD3<Double> {
        switch station {
        case .projectile: SIMD3(0.85, 0.50, 0.50)
        // Tall enough to hold the pivot at 2.0 and a bob hanging at
        // full cable plus its own radius (2.0 − 1.6 − 0.07 = 0.33).
        //
        // This is the rig's RESTING volume. A bob thrown hard sideways
        // swings out past it — a 1.6 m cable at 90° reaches further
        // than any box that would still leave the launcher room — and
        // that is fine: apparatus volumes must stay apart, trajectories
        // may cross freely. A swinging bob crossing the projectile
        // bench is the same event as a thrown ball crossing an orbit.
        case .pendulum:   SIMD3(0.80, 0.90, 0.55)
        // The orrery is fifteen metres across at metersPerAU = 0.5.
        // This is not a footprint anything is kept out of — it is the
        // volume the arc stations stand INSIDE, and its invariant is
        // the empty annulus between Mars' orbit and Jupiter's.
        case .orbital:    SIMD3(repeating: 9.0)
        }
    }

    /// The display translation carrying a station's root from where its
    /// module authored it to its seat.
    ///
    /// `.projectile` returns exactly zero, and
    /// `testTheProjectileStationIsNeverOffset` will fail loudly if that
    /// ever stops being true.
    static func offset(_ station: MechanicsStation) -> SIMD3<Float> {
        SIMD3<Float>(seat(station) - nativeAnchor(station))
    }

    /// Which way is AWAY from the middle of the world, along x — where
    /// side furniture (the pendulum's spawn well) hangs.
    static func outboard(_ station: MechanicsStation) -> Double {
        center(station).x <= 0 ? -1 : 1
    }

    static func box(_ station: MechanicsStation) -> StationBox {
        StationBox(center: center(station), halfExtents: halfExtents(station))
    }

    static func bounds(_ station: MechanicsStation)
    -> (min: SIMD3<Double>, max: SIMD3<Double>) {
        let b = box(station)
        return (b.minimum, b.maximum)
    }

    static func areSeparated(
        _ a: MechanicsStation, _ b: MechanicsStation, margin: Double = 0
    ) -> Bool {
        box(a).isSeparated(from: box(b), margin: margin)
    }
}

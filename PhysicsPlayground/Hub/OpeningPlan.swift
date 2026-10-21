//
//  OpeningPlan.swift
//  Physics Playground — Hub
//
//  "Birth of a System" (2026-10-20, the owner's choice), as one plan solved
//  once and read as pure functions of the clock — no RealityKit, so it is
//  tested on numbers. About six seconds:
//
//    0.0  The room dims under a night of real stars.
//    0.8  A protostar ignites ahead of the wearer.
//    1.1  Its dust disk fades up and turns — each ring at its own
//         Kepler rate Ω = √(GM/r³), so spokes that are straight at 1.5 s
//         wind into the r^−3/2 spirals of a sheared disk.
//    ~2–4 Seven worlds condense in gaps in the disk, each on its own
//         circular orbit, each opening a gap as it grows.
//    2.4–4.1 One by one they leave on transfer ellipses: the one orbit with
//         the star at its focus whose far end is exactly over a plinth,
//         passing through the world's place on its ring.
//    5.4  The clock — which ran up to 6.5 times faster while they flew
//         — falls to rest exactly as every world reaches its far end, so
//         each eases onto its plinth with no easing of its own. The bell.
//    5.4+ The worlds open into the labs, the star fades, the night lifts.
//
//  Everything is an exact two-body solution in simulated time, watched
//  through `TimeLapse`, except one stated event per world: no single disk
//  plane holds seven plinths that ring the wearer, so each world takes one
//  impulse at departure — from its circular speed onto its transfer —
//  chosen as the smallest the geometry allows. Worlds are test particles:
//  they feel the star, not one another.
//

import Foundation
import PhysicsCore
import simd

nonisolated struct OpeningPlan: Sendable {

    // MARK: The physics' one constant

    /// GM of the protostar, m³ per simulated second²: the disk's outer
    /// edge, 0.92 m out, turns 60° in the 1.5 s the disk takes to arrive
    /// at rate 1. A 1 M☉ star with one metre standing for ten AU.
    static let gm = 0.3795

    /// Kepler's angular speed at radius `r`, rad per simulated second.
    static func angularSpeed(atRadius r: Double) -> Double {
        (gm / (r * r * r)).squareRoot()
    }

    // MARK: The clock

    /// Simulated time against wall time: real speed while the disk forms,
    /// up to 6.5 times while the worlds fly, and to rest at the landing.
    /// Swept on 2026-10-20 between how fast a world crosses the room (no
    /// more than 6 cm a frame at 90 Hz) and how early the first, longest
    /// flight must leave (after the disk is up).
    static let clock = TimeLapse(knots: [
        .init(time: 0, rate: 1),
        .init(time: 2.6, rate: 1),
        .init(time: 4.4, rate: 6.5),
        .init(time: landingTime, rate: 0),
    ])
    /// When every world reaches its plinth, and the bell strikes.
    static let landingTime = 5.4
    static let landingSimTime = clock.simTime(at: landingTime)

    // MARK: The timeline, wall seconds

    /// The night (and, in the room, the sky over it) comes up from 0.
    static let nightRise = 0.8
    static let ignition = 0.8
    static let ignitionRise = 0.35
    static let diskStart = 1.1
    static let diskRise = 0.4
    /// When the disk's spokes are straight: its rings' angles are zero.
    static let spokesStraight = 1.5
    /// The disk clears from the inside out, as real disks do — the
    /// innermost ring from 3.0 s, the outermost from 4.2 s, each over
    /// half a second — which also keeps its fast inner rings from being
    /// seen spinning once the clock speeds up.
    static let diskFadeStart = 3.0
    static let diskFadeSpread = 1.2
    static let diskFade = 0.5
    /// A world condenses over the 0.5 s ending 0.1 s before it leaves.
    static let condenseLead = 0.6
    static let condenseTail = 0.1
    /// The labs fade up on their plinths, growing into place.
    static let labsStart = landingTime - 0.2
    static let labsRise = 0.5
    /// How much smaller a lab is when it begins to fade up.
    static let labGrowth: Float = 0.3
    /// The worlds shrink away into the labs after the landing.
    static let worldOpen = 0.35
    static let starFadeStart = landingTime
    static let starFade = 0.6
    /// The room's own dimming takes over from the night here.
    static let handOver = landingTime + 0.3
    static let nightFadeStart = landingTime + 0.2
    static let nightFade = 0.7
    /// The labels and the More come last.
    static let labelStart = landingTime
    static let labelRise = 0.4
    /// How far below its place the wordmark starts, metres.
    static let titleRise: Float = 0.035
    static let duration = nightFadeStart + nightFade

    // MARK: Where

    /// Eye height, for what the wearer sees and must never be struck by.
    static let eye = SIMD3<Double>(0, 1.6, 0)
    /// The star: a little right of straight ahead, above the plinths, off
    /// every plinth's line of sight.
    static let starAzimuth = 7 * Double.pi / 180
    static let starDistance = 2.80
    static let starHeight = 1.85
    /// The disk is seen this far from edge-on: an ellipse, not a line.
    static let viewFromEdge = 24 * Double.pi / 180
    static let diskInner = 0.28
    static let diskOuter = 0.92
    /// Rings of dust, each turning rigidly: enough that the arms they wind
    /// into read as curves, not stairs (33 showed steps).
    static let annulusCount = 64
    /// The worlds' rings: 0.45 m and each 11.6 % further out.
    static let ringBase = 0.45
    static let ringRatio = 1.116
    /// Innermost first; textured as Orbital Mechanics draws them.
    static let worldNames = ["Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Neptune"]
    static let worldRadii: [Double] = [0.022, 0.029, 0.031, 0.025, 0.053, 0.045, 0.036]
    /// Half the width of the gap a world clears in the disk, metres.
    static let gapWidth = 0.028
    /// How far above its plinth's deck a world comes to rest.
    static let landingLift = 0.006

    // MARK: Solved once

    struct World: Sendable {
        let name: String
        /// Drawn radius, metres.
        let radius: Double
        let ringRadius: Double
        /// Which portal, in arc order, it lands on.
        let portal: Int
        /// Where it comes to rest, in the room.
        let landing: SIMD3<Double>
        /// Its circular orbit until it leaves, and its transfer after;
        /// both about the star.
        let ring: KeplerOrbit
        let transfer: KeplerOrbit
        let departureSim: Double
        let departureWall: Double
        /// The one impulse: transfer velocity less ring velocity at the
        /// departure, simulated m/s.
        let deltaV: SIMD3<Double>

        var condenseStart: Double { departureWall - OpeningPlan.condenseLead }
        var condenseEnd: Double { departureWall - OpeningPlan.condenseTail }
    }

    let star: SIMD3<Double>
    /// The disk's normal; it turns anticlockwise about it, seen from the
    /// wearer.
    let diskNormal: SIMD3<Double>
    /// Two axes in the disk's plane, the disk's own 0° and 90°.
    let diskAxisU: SIMD3<Double>
    let diskAxisV: SIMD3<Double>
    /// In ring order, innermost first.
    let worlds: [World]

    /// The home's seven plinths.
    static let shared = OpeningPlan(portals: PortalLayout.portals(count: 7))

    init(portals: [PortalLayout.Portal]) {
        let star = SIMD3(Self.starDistance * sin(Self.starAzimuth), Self.starHeight,
                         -Self.starDistance * cos(Self.starAzimuth))
        self.star = star
        let count = min(portals.count, Self.worldNames.count)
        let targets = portals.prefix(count).map { PortalLayout.plinthCentre(of: $0) - star }

        // The plane nearest every plinth's direction, then tipped to be seen
        // `viewFromEdge` from edge-on, its normal toward the wearer.
        var normal = Self.leastSquaresNormal(of: targets.map(simd_normalize))
        let towardEye = simd_normalize(Self.eye - star)
        if simd_dot(normal, towardEye) < 0 { normal = -normal }
        let across = normal - simd_dot(normal, towardEye) * towardEye
        let sideways = simd_length(across) > 1e-9
            ? simd_normalize(across) : simd_normalize(simd_cross(towardEye, SIMD3(0, 1, 0)))
        let tilt = Double.pi / 2 - Self.viewFromEdge
        normal = simd_normalize(cos(tilt) * towardEye + sin(tilt) * sideways)
        diskNormal = normal
        let reference = abs(normal.y) < 0.9 ? SIMD3<Double>(0, 1, 0) : SIMD3<Double>(1, 0, 0)
        let u = simd_normalize(reference - simd_dot(reference, normal) * normal)
        diskAxisU = u
        diskAxisV = simd_cross(normal, u)

        // Innermost ring to the farthest plinth: the longest flight leaves
        // first, from where the disk turns fastest.
        let farthestFirst = (0..<count).sorted { simd_length(targets[$0]) > simd_length(targets[$1]) }
        var worlds: [World] = []
        for ring in 0..<count {
            let portal = farthestFirst[ring]
            let radius = Self.worldRadii[ring]
            let ringRadius = Self.ringBase * pow(Self.ringRatio, Double(ring))
            let landing = PortalLayout.plinthCentre(of: portals[portal])
                + SIMD3(0, radius + Self.landingLift, 0)
            guard let departure = Self.bestDeparture(ringRadius: ringRadius,
                                                     apoapsis: landing - star,
                                                     normal: normal, u: u, v: diskAxisV)
            else { continue }
            let flight = departure.transfer.timeOfFlight(
                from: departure.transfer.frame.trueAnomaly, to: .pi)
            let leaves = Self.landingSimTime - flight
            let transfer = KeplerOrbit(frame: departure.transfer.frame, epoch: leaves)
            let circle = KeplerOrbit.circular(radius: ringRadius, normal: normal,
                                              through: departure.point, mu: Self.gm, epoch: leaves)
            worlds.append(World(
                name: Self.worldNames[ring], radius: radius, ringRadius: ringRadius,
                portal: portal, landing: landing, ring: circle, transfer: transfer,
                departureSim: leaves,
                departureWall: Self.clock.wallTime(reaching: leaves) ?? 0,
                deltaV: departure.deltaV))
        }
        self.worlds = worlds
    }

    /// The unit normal minimising Σ(n·uᵢ)²: the plane the directions lie
    /// nearest. A search over the hemisphere, refined three times — solved
    /// once, so exhaustive is cheaper than clever.
    static func leastSquaresNormal(of directions: [SIMD3<Double>]) -> SIMD3<Double> {
        func cost(_ n: SIMD3<Double>) -> Double {
            directions.reduce(0) { $0 + simd_dot(n, $1) * simd_dot(n, $1) }
        }
        func normal(_ polar: Double, _ azimuth: Double) -> SIMD3<Double> {
            SIMD3(sin(polar) * cos(azimuth), cos(polar), sin(polar) * sin(azimuth))
        }
        var best = (polar: 0.0, azimuth: 0.0)
        var bestCost = Double.infinity
        var step = Double.pi / 90
        var polarRange = 0.0...(Double.pi / 2)
        var azimuthRange = 0.0...(2 * Double.pi)
        for _ in 0..<4 {
            var polar = polarRange.lowerBound
            while polar <= polarRange.upperBound {
                var azimuth = azimuthRange.lowerBound
                while azimuth <= azimuthRange.upperBound {
                    let c = cost(normal(polar, azimuth))
                    if c < bestCost { bestCost = c; best = (polar, azimuth) }
                    azimuth += step
                }
                polar += step
            }
            polarRange = (best.polar - 2 * step)...(best.polar + 2 * step)
            azimuthRange = (best.azimuth - 2 * step)...(best.azimuth + 2 * step)
            step /= 10
        }
        return simd_normalize(normal(best.polar, best.azimuth))
    }

    /// Where on its ring a world leaves for the transfer to `apoapsis`.
    /// Round any ring the impulse needed has two near-equal minima, either
    /// side of the place where the transfer's plane flips; picking the
    /// lower one alone flipped between them on a millimetre's change. So:
    /// every local minimum within 5 % of the least, refined, and of those
    /// the longest flight — the one that sweeps furthest round the star,
    /// which is also the one most worth watching.
    static func bestDeparture(ringRadius r: Double, apoapsis: SIMD3<Double>,
                              normal n: SIMD3<Double>, u: SIMD3<Double>, v: SIMD3<Double>)
    -> (point: SIMD3<Double>, transfer: KeplerOrbit, deltaV: SIMD3<Double>)? {
        typealias Candidate = (cost: Double, point: SIMD3<Double>, transfer: KeplerOrbit,
                               deltaV: SIMD3<Double>, phase: Double)
        func evaluate(_ phase: Double) -> Candidate? {
            let point = r * (cos(phase) * u + sin(phase) * v)
            guard let transfer = KeplerOrbit.reaching(apoapsis: apoapsis, through: point,
                                                      sense: n, mu: gm, at: 0) else { return nil }
            let circular = angularSpeed(atRadius: r) * r * simd_normalize(simd_cross(n, point))
            let jump = transfer.frame.state().velocity - circular
            return (simd_length(jump), point, transfer, jump, phase)
        }
        func refine(around phase: Double, step: Double) -> Candidate? {
            var best = evaluate(phase)
            var centre = phase, span = step
            for _ in 0..<3 {
                var probe = centre - 2 * span
                while probe <= centre + 2 * span {
                    if let found = evaluate(probe), found.cost < (best?.cost ?? .infinity) {
                        best = found
                        centre = probe
                    }
                    probe += span / 10
                }
                span /= 10
            }
            return best
        }
        let count = 720
        let step = 2 * Double.pi / Double(count)
        let costs = (0..<count).map { evaluate(Double($0) * step)?.cost ?? .infinity }
        var minima: [Candidate] = []
        for i in 0..<count where costs[i].isFinite
            && costs[i] <= costs[(i + count - 1) % count] && costs[i] <= costs[(i + 1) % count] {
            if let found = refine(around: Double(i) * step, step: step) { minima.append(found) }
        }
        guard let least = minima.map(\.cost).min() else { return nil }
        func flight(_ candidate: Candidate) -> Double {
            candidate.transfer.timeOfFlight(from: candidate.transfer.frame.trueAnomaly, to: .pi)
        }
        guard let chosen = minima.filter({ $0.cost <= least * 1.05 }).max(by: { flight($0) < flight($1) })
        else { return nil }
        return (chosen.point, chosen.transfer, chosen.deltaV)
    }

    // MARK: The worlds

    /// Simulated time at wall time `t`, held at the landing once there.
    static func simTime(at t: Double) -> Double {
        clock.simTime(at: min(max(t, 0), landingTime))
    }

    /// Where world `index` is, in the room, at wall time `t`.
    func position(ofWorld index: Int, at t: Double) -> SIMD3<Double> {
        star + relativeState(ofWorld: index, atSim: Self.simTime(at: t)).position
    }

    /// Its velocity in simulated time — the physics' own.
    func simVelocity(ofWorld index: Int, at t: Double) -> SIMD3<Double> {
        relativeState(ofWorld: index, atSim: Self.simTime(at: t)).velocity
    }

    /// The velocity the wearer sees: the physics' times the clock's rate.
    func shownVelocity(ofWorld index: Int, at t: Double) -> SIMD3<Double> {
        guard t < Self.landingTime else { return .zero }
        return simVelocity(ofWorld: index, at: t) * Self.clock.rate(at: t)
    }

    func relativeState(ofWorld index: Int, atSim tau: Double)
    -> (position: SIMD3<Double>, velocity: SIMD3<Double>) {
        let world = worlds[index]
        return tau < world.departureSim ? world.ring.state(at: tau) : world.transfer.state(at: tau)
    }

    /// How much of world `index` there is, 0…1: it condenses before it
    /// leaves and opens away into its lab after the landing.
    func growth(ofWorld index: Int, at t: Double) -> Double {
        let world = worlds[index]
        let formed = Self.smoothstep((t - world.condenseStart) / (world.condenseEnd - world.condenseStart))
        let opened = Self.smoothstep((t - Self.landingTime) / Self.worldOpen)
        return formed * (1 - opened)
    }

    /// The path world `index` has flown since it left, oldest first, and
    /// each point's age as a share of the whole (1 at the world): closed
    /// form, so a pinned clock draws the same trail as a running one.
    func trail(ofWorld index: Int, at t: Double, samples: Int = 40)
    -> (points: [SIMD3<Double>], ages: [Double]) {
        let world = worlds[index]
        let now = Self.simTime(at: t)
        guard now > world.departureSim, samples > 1 else { return ([], []) }
        var points: [SIMD3<Double>] = []
        var ages: [Double] = []
        for step in 0..<samples {
            let share = Double(step) / Double(samples - 1)
            let tau = world.departureSim + (now - world.departureSim) * share
            points.append(star + world.transfer.state(at: tau).position)
            ages.append(share)
        }
        return (points, ages)
    }

    // MARK: The disk

    static let annulusRatio = pow(diskOuter / diskInner, 1 / Double(annulusCount))

    /// Annulus `k`'s inner and outer radii, metres.
    static func annulus(_ k: Int) -> (inner: Double, outer: Double) {
        (diskInner * pow(annulusRatio, Double(k)), diskInner * pow(annulusRatio, Double(k + 1)))
    }

    /// How far annulus `k` has turned at wall time `t`: rigidly, at the
    /// Kepler rate of its middle radius, from straight at `spokesStraight`.
    func annulusAngle(_ k: Int, at t: Double) -> Double {
        let bounds = Self.annulus(k)
        let middle = (bounds.inner * bounds.outer).squareRoot()
        return Self.angularSpeed(atRadius: middle)
            * (Self.simTime(at: t) - Self.simTime(at: Self.spokesStraight))
    }

    /// Annulus `k`'s opacity at `t`: a disk brighter inward and soft at its
    /// edges, up and away on the timeline, and dimmed where a world is
    /// gathering its ring's dust into itself.
    func annulusOpacity(_ k: Int, at t: Double) -> Double {
        let bounds = Self.annulus(k)
        let middle = (bounds.inner + bounds.outer) / 2
        let x = Double(k) / Double(Self.annulusCount - 1)
        let edges = Self.smoothstep(x / 0.12) * Self.smoothstep((1 - x) / 0.2)
        let profile = pow(Self.diskInner / middle, 0.6) * edges
        let clears = Self.diskFadeStart + Self.diskFadeSpread * x
        let envelope = Self.ramp(t, from: Self.diskStart, over: Self.diskRise)
            * (1 - Self.ramp(t, from: clears, over: Self.diskFade))
        var gap = 1.0
        for world in worlds {
            let distance = abs(middle - world.ringRadius)
            let width = max((bounds.outer - bounds.inner) * 1.5, Self.gapWidth)
            guard distance < width else { continue }
            let formed = Self.smoothstep((t - world.condenseStart) / (world.condenseEnd - world.condenseStart))
            gap = min(gap, 1 - 0.85 * formed * (1 - distance / width))
        }
        return profile * envelope * gap
    }

    // MARK: Light

    func starBrightness(at t: Double) -> Double {
        Self.ramp(t, from: Self.ignition, over: Self.ignitionRise)
            * (1 - Self.ramp(t, from: Self.starFadeStart, over: Self.starFade))
    }

    /// The night over the room, 0…1 of its full opacity.
    func nightOpacity(at t: Double) -> Double {
        Self.ramp(t, from: 0, over: Self.nightRise)
            * (1 - Self.ramp(t, from: Self.nightFadeStart, over: Self.nightFade))
    }

    static func labOpacity(at t: Double) -> Float {
        Float(ramp(t, from: labsStart, over: labsRise))
    }

    /// A lab's scale as it arrives: it grows out of its world into place,
    /// and is exactly 1 once arrived.
    static func labScale(at t: Double) -> Float {
        1 - labGrowth * (1 - Float(easeOut(t, from: labsStart, over: labsRise)))
    }

    static func labelOpacity(at t: Double) -> Float {
        Float(ramp(t, from: labelStart, over: labelRise))
    }

    static func titleOffset(at t: Double) -> Float {
        -titleRise * (1 - Float(easeOut(t, from: labelStart, over: labelRise)))
    }

    static func isFinished(at t: Double) -> Bool { t >= duration }

    // MARK: Curves

    static func smoothstep(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    static func ramp(_ t: Double, from start: Double, over span: Double) -> Double {
        smoothstep((t - start) / max(span, 1e-6))
    }

    /// Fast away, soft into place.
    static func easeOut(_ t: Double, from start: Double, over span: Double) -> Double {
        let x = min(max((t - start) / max(span, 1e-6), 0), 1)
        return 1 - pow(1 - x, 3)
    }
}

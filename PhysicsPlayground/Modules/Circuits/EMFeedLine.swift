//
//  EMFeedLine.swift
//  Physics Playground — Electricity & Magnetism
//
//  The two conductors that run from the bench's inductor, across the
//  middle of the room, to the electromagnet standing in the magnetic
//  field.
//
//  This is the whole reason the two benches were merged. The link
//  itself is not new — the magnet bench has been reading the circuit
//  bench's inductor current for a long time — but it used to be a
//  sentence in a control panel, asserted across a module boundary the
//  user had to exit the room to cross. Here it is a pair of wires you
//  can see, with electrons on them, going somewhere.
//
//  So the failure modes are the point, not an edge case: no inductor
//  on the bench means no feed line at all, and an open switch means
//  beads that stop dead while the coil's field collapses. Both read
//  instantly, because the cable is right there.
//
//  Per-frame cost is transforms only. The segment chain and the beads
//  are built once at their full count and re-aimed each frame — the
//  architecture rule is that mesh regeneration goes through
//  GeometryPipeline's worker, never inline in the render tick, and a
//  cable that re-tubed itself every frame as the coil is carried
//  around would be exactly the thing that rule forbids.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

@MainActor
final class EMFeedLine {
    /// Sits at the scene root, NOT under either station: it is the one
    /// thing in the world that belongs to both, and it spans the gap
    /// their display offsets put between them.
    let root = Entity()

    /// Segments per conductor. Enough that the sag reads as a curve
    /// rather than a dogleg, few enough to stay cheap.
    private static let segments = 18
    /// Beads riding each conductor.
    private static let beadsPerConductor = 7
    private static let conductorRadius: Float = 0.0045
    private static let beadRadius: Float = 0.0075
    /// How far apart the outbound and return conductors run.
    private static let pairSpacing: Float = 0.016

    private var conductors: [[ModelEntity]] = []
    private var beads: [[ModelEntity]] = []
    private var phase = 0.0

    init() {
        // The bench's own copper, so the cable reads as more of the
        // same wire rather than a new kind of object.
        let copper = Materials.energized(
            DesignTokens.Palette.copperUI,
            roughness: 0.35, metallic: 1, glow: 0.05)
        let segmentMesh = MeshResource.generateCylinder(height: 1, radius: 1)
        let beadMesh = MeshResource.generateSphere(radius: Self.beadRadius)
        let beadMaterial = UnlitMaterial(color: DesignTokens.Palette.electronUI)

        for _ in 0..<2 {
            var chain: [ModelEntity] = []
            for _ in 0..<Self.segments {
                let segment = ModelEntity(mesh: segmentMesh, materials: [copper])
                root.addChild(segment)
                chain.append(segment)
            }
            conductors.append(chain)

            var riders: [ModelEntity] = []
            for _ in 0..<Self.beadsPerConductor {
                let bead = ModelEntity(mesh: beadMesh, materials: [beadMaterial])
                root.addChild(bead)
                riders.append(bead)
            }
            beads.append(riders)
        }
        root.isEnabled = false
    }

    /// Re-aims the cable and slides its electrons.
    ///
    /// `benchLeads` and `coilLeads` are in SCENE space — each station
    /// converts out of its own zoomed, offset frame before handing them
    /// over, because the cable is the one object that cannot live in
    /// either frame.
    func update(
        benchLeads: (SIMD3<Float>, SIMD3<Float>)?,
        coilLeads: (SIMD3<Float>, SIMD3<Float>)?,
        current: Double,
        speed: Double,
        isPaused: Bool,
        dt: Double
    ) {
        guard let benchLeads, let coilLeads else {
            // No inductor on the bench, or the coil is switched off:
            // there is nothing to carry, so there is no cable. The
            // absence is honest — wire an inductor in and it appears.
            root.isEnabled = false
            return
        }
        root.isEnabled = true

        // Outbound on one conductor, return on the other — a real
        // two-wire feed, so the electrons visibly go and come back
        // rather than vanishing into the coil.
        let routes = [
            (from: benchLeads.0, to: coilLeads.0, reversed: false),
            (from: coilLeads.1, to: benchLeads.1, reversed: true),
        ]

        let span = simd_distance(benchLeads.0, coilLeads.0)
        if !isPaused {
            phase = (phase + speed / Double(max(span, 0.05)) * dt)
                .truncatingRemainder(dividingBy: 1)
        }

        // Beads only where there is current to carry. The cable itself
        // stays visible: an unpowered feed is still a feed.
        let flowing = abs(current) > 5e-4

        for (index, route) in routes.enumerated() {
            let control = Self.sagControl(from: route.from, to: route.to)
            layOut(conductors[index], from: route.from,
                   control: control, to: route.to)

            for (rider, bead) in beads[index].enumerated() {
                guard flowing else { bead.isEnabled = false; continue }
                bead.isEnabled = true
                var t = phase + Double(rider) / Double(Self.beadsPerConductor)
                // The return conductor runs the other way, so its
                // electrons must travel the other way along it too.
                if route.reversed { t = -t }
                t = t.truncatingRemainder(dividingBy: 1)
                if t < 0 { t += 1 }
                bead.position = Self.point(
                    from: route.from, control: control, to: route.to,
                    t: Float(t))
            }
        }
    }

    // MARK: Geometry

    /// The control point that gives the cable its slack. A run this
    /// long dead straight reads as a laser, not a wire; the droop is
    /// what makes it a physical object crossing a room.
    private static func sagControl(
        from a: SIMD3<Float>, to b: SIMD3<Float>
    ) -> SIMD3<Float> {
        let mid = (a + b) / 2
        let sag = min(simd_distance(a, b) * 0.22, 0.30)
        // Quadratic Bezier sits halfway to its control point, so the
        // control drops twice the sag the curve should show.
        return mid - SIMD3<Float>(0, sag * 2, 0)
    }

    private static func point(
        from a: SIMD3<Float>, control c: SIMD3<Float>, to b: SIMD3<Float>,
        t: Float
    ) -> SIMD3<Float> {
        let u = 1 - t
        return u * u * a + 2 * u * t * c + t * t * b
    }

    /// Aims a chain of unit cylinders along the curve. Transforms only.
    private func layOut(
        _ chain: [ModelEntity], from a: SIMD3<Float>,
        control: SIMD3<Float>, to b: SIMD3<Float>
    ) {
        // The two conductors of a pair run side by side, offset
        // perpendicular to the span and to gravity.
        let along = b - a
        let sideways = simd_length(simd_cross(along, SIMD3<Float>(0, 1, 0))) > 1e-4
            ? simd_normalize(simd_cross(along, SIMD3<Float>(0, 1, 0)))
            : SIMD3<Float>(1, 0, 0)
        let shift = sideways * (Self.pairSpacing / 2)

        for (index, segment) in chain.enumerated() {
            let t0 = Float(index) / Float(Self.segments)
            let t1 = Float(index + 1) / Float(Self.segments)
            let p0 = Self.point(from: a, control: control, to: b, t: t0) + shift
            let p1 = Self.point(from: a, control: control, to: b, t: t1) + shift
            let delta = p1 - p0
            let length = simd_length(delta)
            guard length > 1e-6 else { segment.isEnabled = false; continue }
            segment.isEnabled = true
            segment.position = (p0 + p1) / 2
            // generateCylinder runs along +Y; aim it down the segment.
            segment.orientation = simd_quatf(
                from: SIMD3<Float>(0, 1, 0), to: delta / length)
            segment.scale = SIMD3(Self.conductorRadius, length, Self.conductorRadius)
        }
    }
}

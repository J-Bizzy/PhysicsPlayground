//
//  EquipotentialSurface.swift
//  PhysicsCore — Electromagnetism
//
//  Equipotential shells are isosurfaces of V(r), so this wrapper owns only
//  the electrostatics specifics — the regularized potential sampler, the
//  E-field-based outward orientation, and the default level set — and
//  delegates the marching-tetrahedra extraction to Math's Isosurface.
//
//  Because E = −∇V, the surface normal is always parallel to the field —
//  which is exactly the physics the visualization demonstrates: field lines
//  cross equipotential shells at right angles.
//

import Foundation
import simd

public enum EquipotentialSurface {
    /// Flat triangle list (every 3 consecutive points form one triangle) for
    /// the isosurface V = `level` inside the box.
    public static func triangles(
        level: Double,
        charges: [PointCharge],
        center: SIMD3<Double>,
        extents: SIMD3<Double>,
        resolution: Int = 24
    ) -> [SIMD3<Double>] {
        guard !charges.isEmpty, level != 0 else { return [] }

        // The sampled potential is *regularized*: distances are clamped to
        // half a cell. The raw kq/r diverges at a charge (and the display
        // guard returns 0 exactly there), so a lattice point landing on a
        // charge would fake a sign flip and extrude a tiny spurious shell
        // around it. Clamping keeps near-charge samples large, finite, and
        // on the correct side of every real level.
        let clampDistance = simd_reduce_min(extents / Double(resolution)) / 2

        return Isosurface.triangles(
            level: level,
            scalar: { point in
                charges.reduce(0) { total, charge in
                    total + ElectricField.k * charge.charge
                        / max(simd_distance(point, charge.position), clampDistance)
                }
            },
            outwardDirection: { outwardNormal(at: $0, level: level, charges: charges) },
            center: center,
            extents: extents,
            resolution: resolution
        )
    }

    /// Outward direction of the shell at `point`: along E for positive
    /// levels (V decreases outward from positive charges), against E for
    /// negative levels. Falls back to +Y at exact field zeros.
    public static func outwardNormal(at point: SIMD3<Double>, level: Double, charges: [PointCharge]) -> SIMD3<Double> {
        let field = ElectricField.vector(at: point, dueTo: charges)
        let magnitude = simd_length(field)
        guard magnitude > 1e-12 else { return SIMD3(0, 1, 0) }
        return (level >= 0 ? 1 : -1) / magnitude * field
    }

    /// A pleasant default set of levels for a scene: shells at three
    /// reference radii from the strongest charge, positive and/or negative
    /// depending on which polarities are present.
    public static func defaultLevels(for charges: [PointCharge]) -> [Double] {
        guard let maxQ = charges.map({ abs($0.charge) }).max(), maxQ > 0 else { return [] }
        let radii = [0.13, 0.21, 0.33]
        var levels: [Double] = []
        if charges.contains(where: { $0.isPositive }) {
            levels += radii.map { ElectricField.k * maxQ / $0 }
        }
        if charges.contains(where: { !$0.isPositive }) {
            levels += radii.map { -ElectricField.k * maxQ / $0 }
        }
        return levels
    }
}

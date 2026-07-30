//
//  GalleryLayout.swift
//  Physics Playground — Hub
//
//  The Gallery's geometry, as pure math: four domain terraces — floating
//  slabs arcing around the user in a crescent — each carrying its
//  domain's modules on pedestal pucks. Domains stop being a colour
//  legend and become physical structure: where a lab sits tells you
//  what kind of physics it is, and one sweep of the head reads the
//  whole room.
//
//  Everything here is a value computation with no RealityKit in it, so
//  the layout — widths from module counts, no terrace collisions across
//  the whole settings range, a ninth module extending its domain's slab
//  rather than wrapping onto someone else's spot — is unit-testable on
//  its own.
//
//  Scaling: the distance setting scales the crescent's plan (radials,
//  slab widths, puck pitch) uniformly, so the layout's proportions are
//  scale-invariant in XZ and a clearance proven at the default holds at
//  every slider position. The height setting scales terrace heights
//  only. Exhibits themselves keep a constant world size — distance
//  stays something you read, not something you are told.
//

import simd

enum GalleryLayout {
    struct Terrace {
        let domain: HubDomain
        let moduleIDs: [String]
        /// Slab centre, world space.
        let center: SIMD3<Float>
        /// Rotation about Y that turns the slab's front toward the user.
        let yaw: Float
        /// Slab length along the crescent, metres.
        let width: Float
        /// World y of the slab's top face.
        let slabTop: Float
        /// Centre of each puck's TOP face, world space, one per module,
        /// left to right as the user sees them.
        let puckTops: [SIMD3<Float>]
        /// Where each module's miniature centres, world space.
        let exhibitPositions: [SIMD3<Float>]
    }

    // Authored per domain: azimuth (degrees, 0 = dead ahead, + right),
    // radial distance at the 2.0 m default, slab-top height at the
    // 1.4 m default. Slight height and radius variation keeps the
    // pair reading as architecture rather than a poster with a curve
    // in it.
    //
    // Two doors now, so two slots, each carrying three experiences —
    // wide enough (~1.16 m of slab) that ±28° is as close together as
    // the collision tests allow across the whole settings range.
    private static let slots: [HubDomain: (azimuth: Float, radial: Float, top: Float)] = [
        .electricity: (azimuth: -28, radial: 1.95, top: 1.00),
        .mechanics:   (azimuth:  28, radial: 2.05, top: 0.92),
    ]

    static let slabDepth: Float = 0.42
    static let slabThickness: Float = 0.055
    static let puckRadius: Float = 0.085
    static let puckHeight: Float = 0.028
    /// Distance between neighbouring pucks at the default distance.
    static let basePuckPitch: Float = 0.36
    /// Puck top face → miniature centre.
    static let exhibitLift: Float = 0.14
    /// Slab width = pitch · modules + this margin (at default distance).
    static let baseWidthMargin: Float = 0.08

    /// The crescent for these modules at the given settings. Domains
    /// with no benched module get no terrace; a module outside every
    /// domain's list extends its fallback domain's slab.
    static func terraces(moduleIDs: [String],
                         distance: Float = 2.0,
                         height: Float = 1.4) -> [Terrace] {
        let radialScale = distance / 2.0
        let heightScale = height / 1.4
        let pitch = basePuckPitch * radialScale

        return HubDomain.allCases.compactMap { domain -> Terrace? in
            var ids = domain.moduleIDs.filter { moduleIDs.contains($0) }
            ids += moduleIDs.filter {
                !HubDomain.arcOrder.contains($0) && HubDomain.domain(for: $0) == domain
            }
            guard !ids.isEmpty, let slot = slots[domain] else { return nil }

            let azimuth = slot.azimuth * .pi / 180
            let radial = slot.radial * radialScale
            let top = slot.top * heightScale
            let width = pitch * Float(ids.count) + baseWidthMargin * radialScale
            let center = SIMD3(radial * sin(azimuth),
                               top - slabThickness / 2,
                               -radial * cos(azimuth))
            // Along the crescent, toward increasing azimuth — the
            // user's left-to-right.
            let tangent = SIMD3<Float>(cos(azimuth), 0, sin(azimuth))
            let puckTops = ids.indices.map { index -> SIMD3<Float> in
                let offset = (Float(index) - Float(ids.count - 1) / 2) * pitch
                return SIMD3(center.x, top + puckHeight, center.z) + tangent * offset
            }

            return Terrace(
                domain: domain,
                moduleIDs: ids,
                center: center,
                yaw: -azimuth,
                width: width,
                slabTop: top,
                puckTops: puckTops,
                exhibitPositions: puckTops.map { $0 + SIMD3(0, exhibitLift, 0) })
        }
    }
}

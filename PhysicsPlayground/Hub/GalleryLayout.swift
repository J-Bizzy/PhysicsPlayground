//  GalleryLayout.swift — Gallery terrace geometry as pure math, no RealityKit.
//  Distance setting scales the XZ plan uniformly (clearances proven at default hold at
//  every slider position); height scales terrace heights only; exhibits keep constant world size.

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
        /// Centre of each puck's top face, world space, one per module,
        /// left to right as the user sees them.
        let puckTops: [SIMD3<Float>]
        /// Where each module's miniature centres, world space.
        let exhibitPositions: [SIMD3<Float>]
    }

    // Per domain: azimuth (degrees, 0 = dead ahead, + right), radial at the 2.0 m default,
    // slab-top at the 1.4 m default. Slabs share one height; ±28° is the collision-test minimum.
    private static let slots: [HubDomain: (azimuth: Float, radial: Float, top: Float)] = [
        .electricity: (azimuth: -28, radial: 1.95, top: 0.96),
        .mechanics:   (azimuth:  28, radial: 2.05, top: 0.96),
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
            // Along the crescent toward increasing azimuth — the user's left-to-right.
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

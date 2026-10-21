//
//  PortalLayout.swift
//  Physics Playground — Hub
//
//  Where the labs stand in the home: seven on one arc around the wearer,
//  each on its plinth. Pure geometry, shared by the home, its opening
//  (`OpeningPlan` lands a world on every plinth) and their tests.
//

import Foundation
import simd

/// Where the labs stand: one arc at eye level around the wearer, each lab
/// in miniature on its own plinth, facing them. Pure geometry, so it is
/// tested on numbers.
nonisolated enum PortalLayout {
    struct Portal: Equatable {
        /// The portal's centre, in the space's coordinates.
        let position: SIMD3<Double>
        /// Rotation about +y that turns the portal's face to the wearer.
        let yaw: Double
        /// The portal's own right, horizontal.
        let right: SIMD3<Double>
        /// Horizontal, from the portal toward the wearer: its front.
        let toward: SIMD3<Double>
    }

    /// Far enough that seven fit the field of view with a turn of the head,
    /// near enough to read a lab 30 cm across.
    static let radius = 1.75
    /// Eye height for a standing wearer, a little low for a seated one.
    static let height = 1.35
    /// Between neighbouring portals, degrees.
    static let step = 20.0

    /// The plinth every lab stands on — a miniature of Circuit Workshop's
    /// turntable, the same size and height in every portal, so seven
    /// differently shaped labs read as one row of exhibits. Metres, to the
    /// knurled rim.
    static let plinthRadius = 0.16
    /// How far the plinth's top centre stands below the portal's centre:
    /// every lab rises from the same height.
    static let plinthDrop = 0.10
    /// How far every plinth is turned toward the wearer: enough that its
    /// top reads as a surface from a standing eye, little enough that a
    /// cable still hangs plumb to it. `HubVignettes.stageTilt` is this.
    static let plinthTilt = 10 * Double.pi / 180

    static func portals(count: Int) -> [Portal] {
        (0..<count).map { index in
            let degrees = (Double(index) - Double(count - 1) / 2) * step
            let azimuth = degrees * .pi / 180
            let position = SIMD3(radius * sin(azimuth), height, -radius * cos(azimuth))
            return Portal(position: position,
                          yaw: -azimuth,
                          right: SIMD3(cos(azimuth), 0, sin(azimuth)),
                          toward: SIMD3(-sin(azimuth), 0, cos(azimuth)))
        }
    }

    /// The plinth's top centre, in the space's coordinates.
    static func plinthCentre(of portal: Portal) -> SIMD3<Double> {
        portal.position + SIMD3(0, -plinthDrop, 0)
    }
}

//
//  PortalLayout.swift
//  Physics Playground — Hub
//
//  Where the labs stand in the home: seven on one arc around the wearer,
//  each floating at one size and height. Pure geometry, shared by the home
//  and its tests.
//

import Foundation
import simd

/// Where the labs stand: one arc at eye level around the wearer, each lab
/// in miniature floating in its place, facing them. Pure geometry, so it
/// is tested on numbers.
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

    /// The footprint every lab is scaled to: the same size and height in
    /// every portal, so seven differently shaped labs read as one row of
    /// exhibits. Metres. Each stood on a plinth this size, a miniature of
    /// Circuit Workshop's turntable, until 2026-10-21 (owner's call: the
    /// labs float).
    static let footprintRadius = 0.16
    /// How far a lab's footprint stands below the portal's centre: every
    /// lab rises from the same height.
    static let footprintDrop = 0.10
    /// How far every footprint is turned toward the wearer: enough that a
    /// lab's floor reads from a standing eye, little enough that a cable
    /// still hangs near plumb. `HubVignettes.stageTilt` is this.
    static let footprintTilt = 10 * Double.pi / 180

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

    /// The footprint's centre, where a lab's floor is, in the space's
    /// coordinates.
    static func footprintCentre(of portal: Portal) -> SIMD3<Double> {
        portal.position + SIMD3(0, -footprintDrop, 0)
    }
}

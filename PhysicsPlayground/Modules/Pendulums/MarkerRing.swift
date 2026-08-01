//
//  MarkerRing.swift
//  Physics Playground — Pendulums module
//
//  The Panthéon ring: the precession as a RECORD rather than a motion.
//
//  Foucault's 1851 demonstration did not ask anyone to watch. It left
//  evidence — the swing knocked over markers set around the floor, one
//  after another, so what you saw when you arrived was how far the plane
//  had come while you were elsewhere. That is the whole rhetorical trick
//  of the experiment, and it is the reason this is the module's
//  screenshotable moment: a still frame of a rotating plane shows
//  nothing, and a still frame of eleven fallen markers shows everything.
//
//  A marker is felled by the MODEL (`PendulumsModel.advanceFloorMarkers`),
//  which knows the swing plane; this file only draws standing and fallen.
//

import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class MarkerRing {
    let root = Entity()

    private var markers: [ModelEntity] = []
    private var wasStanding: [Bool] = []
    private let standingMaterial: PhysicallyBasedMaterial
    private let fallenMaterial: PhysicallyBasedMaterial

    private static let height: Float = 0.055
    private static let radius: Float = 0.007

    init(accent: UIColor, count: Int) {
        // Standing markers are lit; a fallen one is dark and lying down.
        // Two banked materials rather than one built per marker per
        // frame — the same allocation lesson the voltage skyline and the
        // induction filament both had to learn.
        standingMaterial = Materials.energized(accent, glow: 0.35)
        fallenMaterial = Materials.machined(UIColor(white: 0.34, alpha: 1))

        for index in 0..<count {
            let marker = ModelEntity(
                mesh: .generateBox(size: [Self.radius * 2, Self.height,
                                          Self.radius * 2],
                                   cornerRadius: Self.radius),
                materials: [standingMaterial])
            marker.name = "marker-\(index)"
            root.addChild(marker)
            markers.append(marker)
            wasStanding.append(true)
        }
    }

    /// Per frame: place the ring under the pivot and show which markers
    /// are still up.
    ///
    /// - Parameter originAngle: the plane the ring was laid out against,
    ///   so marker 0 is where the swing STARTED and the count of fallen
    ///   ones is a measure of how far it has come.
    func update(center: SIMD3<Float>, ringRadius: Float,
                standing: Set<Int>, originAngle: Double) {
        root.position = center
        for (index, marker) in markers.enumerated() {
            // Markers cover a HALF turn: a plane is the same plane
            // whichever way the bob travels along it, so a full circle of
            // them would be two identical halves and the count would read
            // double.
            let theta = originAngle
                + Double(index) * .pi / Double(markers.count)
            let x = ringRadius * Float(cos(theta))
            let z = ringRadius * Float(-sin(theta))
            let isStanding = standing.contains(index)

            if isStanding {
                marker.position = [x, Self.height / 2, z]
                marker.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            } else {
                // Lying down, pointing outward — knocked over by
                // something that came past from the inside.
                marker.position = [x, Self.radius, z]
                marker.orientation = simd_quatf(
                    angle: .pi / 2,
                    axis: simd_normalize(SIMD3(Float(-sin(theta)), 0,
                                               Float(-cos(theta)))))
            }
            if wasStanding[index] != isStanding {
                wasStanding[index] = isStanding
                marker.model?.materials =
                    [isStanding ? standingMaterial : fallenMaterial]
            }
        }
    }
}

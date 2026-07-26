//
//  PodPlacement.swift
//  Physics Playground — Design System
//
//  Where a control pod is allowed to open.
//
//  Pods were placed by hand, module by module, and in most modules at
//  least one of them opened outside the user's comfortable field of
//  view — clipped by the frame edge, hidden behind the user, or buried
//  in the furniture. "Keep pods within about ±1.15 m and z ≤ −0.85"
//  was written down as a lesson and then quietly violated again.
//
//  So it stops being a lesson and becomes an invariant: every default
//  pod position goes through `clamped`, which projects it into a
//  comfort shell — an arc in front of the user, at a readable distance,
//  between hip and brow height — and the test asserts that every
//  module's actual defaults already satisfy it.
//

import Foundation
import simd

enum PodPlacement {
    /// The user's head, standing at the origin of immersive space.
    static let eye = SIMD3<Float>(0, 1.5, 0)

    /// Comfort shell, measured from the eye.
    static let minimumDistance: Float = 0.55
    static let maximumDistance: Float = 1.65
    /// Half-angle of the frontal arc a pod may open in, radians.
    /// 75° each side keeps a pod in peripheral vision at worst — never
    /// behind the shoulder, where three modules used to put one.
    static let maximumAzimuth: Float = 75 * .pi / 180
    /// Vertical band: no pod below hip height or above the brow.
    static let minimumHeight: Float = 0.85
    static let maximumHeight: Float = 1.85

    /// True when a pod opening here would be comfortably visible.
    static func isComfortable(_ position: SIMD3<Float>) -> Bool {
        position == clamped(position)
    }

    /// Projects a requested position into the comfort shell, preserving
    /// the intent (which side, roughly how far) rather than snapping to
    /// a grid — a pod that wants to live beside the fan still does.
    static func clamped(_ position: SIMD3<Float>) -> SIMD3<Float> {
        var height = min(max(position.y, minimumHeight), maximumHeight)

        // Work in the horizontal plane relative to the eye. Forward is −z.
        var offset = SIMD2<Float>(position.x - eye.x, position.z - eye.z)
        var planarDistance = simd_length(offset)
        if planarDistance < 1e-4 {
            offset = SIMD2(0, -1)
            planarDistance = 1
        }

        // Azimuth measured from straight ahead (−z), signed by x.
        let forward = SIMD2<Float>(0, -1)
        let cosine = min(max(simd_dot(offset / planarDistance, forward), -1), 1)
        var azimuth = acos(cosine)
        let sign: Float = offset.x < 0 ? -1 : 1
        azimuth = min(azimuth, maximumAzimuth)

        let distance = min(max(planarDistance, minimumDistance), maximumDistance)
        let direction = SIMD2<Float>(sin(azimuth) * sign, -cos(azimuth))
        let planar = direction * distance

        // Far pods sit a little lower so they don't ride up over content.
        if distance > 1.3 { height = min(height, maximumHeight - 0.1) }

        return SIMD3(eye.x + planar.x, height, eye.z + planar.y)
    }
}

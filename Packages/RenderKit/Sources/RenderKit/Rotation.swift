//
//  Rotation.swift
//  RenderKit
//
//  `simd_quatf(from:to:)` is undefined at both ends of its own domain:
//  the two vectors exactly parallel (no rotation is determined, but the
//  half-way construction divides by a zero-length bisector) and exactly
//  antiparallel (every axis perpendicular to the pair is an equally
//  valid π, so the library picks none). Both ends are REACHED by this
//  app, not theoretically:
//
//  · every Bloom grip hangs its leader straight down, so `Callout`
//    aimed a cylinder from [0,1,0] to exactly [0,-1,0];
//  · a frozen gravity arrow points exactly [0,-1,0];
//  · a hand compass under a magnet's south pole reads a field that does
//    too;
//  · a circuit part dragged end-for-end has axis exactly [-1,0,0]
//    against a rest axis of [1,0,0];
//  · the placement cross-hair and the motor's blades each build one bar
//    from a vector to ITSELF.
//
//  The guard existed — `VectorFieldArrows.rotationFromYAxis(to:)` has
//  carried it since the arrows shipped — and was never shared, so
//  thirteen other sites re-made the same mistake. This file is that
//  guard, promoted, and `rotationFromYAxis` now delegates to it.
//
//  The antiparallel axis is CHOSEN rather than arbitrary. Any axis
//  perpendicular to the pair maps `a` to `b`; they differ in what they
//  do to everything else. Taking the component of world up that is
//  perpendicular to `a` keeps a flipped object's up pointing up — a
//  resistor turned end-for-end stays the right way up instead of
//  rolling onto its back — and degenerates, for a vertical `a`, to the
//  [1,0,0] flip `rotationFromYAxis` already used.
//
//  `yaw(facing:from:)` is the other half. Seven instruments — both
//  banks, the picker, Bloom, the palette bead, the time rail and the
//  multimeter — turned to face a viewer with `from: [0,0,1]` and a
//  y-flattened target. That is a one-degree-of-freedom problem solved
//  with a three-degree-of-freedom tool: `atan2` is exact everywhere,
//  states the intent, and cannot degenerate behind the instrument.
//

import simd

/// Rotation taking `a` to `b`, defined everywhere.
///
/// Returns identity when either vector is degenerate or the two already
/// agree, and an explicit π about a chosen perpendicular when they
/// oppose. Both inputs are normalised here; callers need not.
public func rotation(from a: SIMD3<Float>, to b: SIMD3<Float>) -> simd_quatf {
    let la = simd_length(a), lb = simd_length(b)
    guard la > 1e-6, lb > 1e-6 else { return simd_quatf(angle: 0, axis: [0, 1, 0]) }
    let u = a / la, v = b / lb
    let d = simd_dot(u, v)
    if d > 0.9999 { return simd_quatf(angle: 0, axis: [0, 1, 0]) }
    if d < -0.9999 {
        // Every axis perpendicular to `u` is a valid π. Prefer the one
        // that leaves world up alone, so a flipped object does not roll.
        let up = SIMD3<Float>(0, 1, 0)
        let perp = up - simd_dot(u, up) * u
        let axis = simd_length(perp) > 1e-3
            ? simd_normalize(perp)
            : SIMD3<Float>(1, 0, 0)          // `u` is vertical; roll about X
        return simd_quatf(angle: .pi, axis: axis)
    }
    return simd_quatf(from: u, to: v)
}

/// The yaw that turns an instrument's +Z face toward `target`, level.
///
/// Returns `nil` when the viewer is directly above or below the
/// instrument, which carries no yaw — the caller should keep the
/// orientation it has rather than snap to an arbitrary one.
public func yaw(facing target: SIMD3<Float>, from origin: SIMD3<Float>) -> simd_quatf? {
    let flat = SIMD3<Float>(target.x - origin.x, 0, target.z - origin.z)
    guard simd_length(flat) > 1e-4 else { return nil }
    // Rotating +Z by θ about +Y gives (sin θ, 0, cos θ).
    return simd_quatf(angle: atan2(flat.x, flat.z), axis: [0, 1, 0])
}

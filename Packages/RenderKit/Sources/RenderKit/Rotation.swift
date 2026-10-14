//
//  Rotation.swift
//  RenderKit
//
//  `simd_quatf(from:to:)` is undefined for exactly parallel and exactly
//  antiparallel vectors, and this app reaches both (a leader aimed
//  straight down, a gravity arrow, a part dragged end-for-end, a bar
//  built from a vector to itself). `rotation(from:to:)` is the shared
//  guard; the antiparallel axis keeps world up pointing up, so a flipped
//  object does not roll. `yaw(facing:from:)` is the level-facing case
//  every instrument needs, solved with `atan2` rather than a
//  three-degree-of-freedom tool.
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

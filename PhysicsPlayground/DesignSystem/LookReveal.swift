//
//  LookReveal.swift
//  Physics Playground — Design System
//
//  Look at a thing and it tells you about itself; look away and it
//  falls quiet. The last pillar of the interaction grammar: the head
//  ray the hub uses to focus exhibits, generalised so any module can
//  aim it at its own bodies.
//
//  Same honest signal as everywhere else in the app — visionOS never
//  exposes eye gaze, so this is head direction. Same hysteresis trick
//  as the hub: the focused thing keeps focus unless something else is
//  clearly closer to where you look, so a wandering glance doesn't
//  strobe the labels.
//
//  The reveal value eases, and the module applies it as opacity: a
//  label that MATERIALISES as you turn to its object reads as the
//  object answering you; a label that pops reads as UI.
//

import Foundation
import simd

@MainActor
final class LookReveal {
    private let cone: Float
    private let stickiness: Float

    private(set) var focusedID: String?
    private var reveals: [String: Float] = [:]

    init(coneDegrees: Float = 13, stickiness: Float = 0.75) {
        cone = coneDegrees * .pi / 180
        self.stickiness = stickiness
    }

    /// Feed the ray (already converted into the same space as the
    /// candidate positions) and every lookable thing, once per frame.
    func update(dt: Double,
                ray: (origin: SIMD3<Float>, direction: SIMD3<Float>)?,
                candidates: [(id: String, position: SIMD3<Float>)]) {
        var winner: String?

        #if DEBUG
        // `-lookReveal Earth` (or `first`) pins the winner so the
        // reveal can be screenshot-verified from a CLI that has no head
        // to turn. Mirrors the hub's `-hubFocus`.
        if let pinned = UserDefaults.standard.string(forKey: "lookReveal") {
            if pinned == "first" {
                winner = candidates.first?.id
            } else if candidates.contains(where: { $0.id == pinned }) {
                winner = pinned
            }
        }
        #endif

        if winner == nil, let ray {
            let forward = simd_normalize(ray.direction)
            var best = cone
            for candidate in candidates {
                let offset = candidate.position - ray.origin
                let distance = simd_length(offset)
                guard distance > 1e-4 else { continue }
                let cosine = simd_dot(offset / distance, forward)
                let angle = acos(min(max(cosine, -1), 1))
                let bias: Float = candidate.id == focusedID ? stickiness : 1
                if angle * bias < best {
                    best = angle * bias
                    winner = candidate.id
                }
            }
        }
        focusedID = winner

        let rate = Float(min(dt * 7, 1))
        for candidate in candidates {
            let target: Float = candidate.id == winner ? 1 : 0
            let current = reveals[candidate.id] ?? 0
            let next = current + (target - current) * rate
            reveals[candidate.id] = next < 0.005 && target == 0 ? nil : next
        }
        // Bodies that vanished (merged, deleted) take their fade along.
        let live = Set(candidates.map(\.id))
        reveals = reveals.filter { live.contains($0.key) }
    }

    /// 0 = unlooked-at, 1 = fully revealed. Apply as label opacity.
    func reveal(_ id: String) -> Float { reveals[id] ?? 0 }
}

//
//  PropCache.swift
//  Physics Playground — Design System
//
//  One prototype cache for every bundled .usdz, warmed through the async
//  loader (enumerated from the bundle, never a hand-kept list) before the
//  immersive space opens; the synchronous load survives as the cold fallback.
//

import Foundation
import RealityKit

@MainActor
enum PropCache {

    /// Loaded prototypes by asset name. `nil` records a FAILED load:
    /// a missing asset costs one attempt, not one per caller.
    private static var prototypes: [String: Entity?] = [:]

    /// The one warm-up, latched so every caller awaits the same pass.
    private static var warmTask: Task<Void, Never>?

    /// The shared prototype — callers must clone before parenting.
    /// Cache-first; falls back to the old blocking load when cold.
    static func prototype(named name: String) -> Entity? {
        if prototypes[name] == nil {
            prototypes[name] = try? Entity.load(named: name)
        }
        return prototypes[name] ?? nil
    }

    /// A fresh clone, for callers that parent the result directly —
    /// handing out the prototype would let a caller steal it from the cache.
    static func instance(named name: String) -> Entity? {
        prototype(named: name)?.clone(recursive: true)
    }

    /// Loads every bundled .usdz through the async loader. Idempotent;
    /// concurrent callers await the same pass. Sequential ON PURPOSE —
    /// one asset at a time keeps peak memory and launch I/O calm.
    static func warmUp() async {
        if warmTask == nil {
            warmTask = Task {
                let names = (Bundle.main.urls(forResourcesWithExtension: "usdz",
                                              subdirectory: nil) ?? [])
                    .map { $0.deletingPathExtension().lastPathComponent }
                    .sorted()
                for name in names where prototypes[name] == nil {
                    prototypes[name] = try? await Entity(named: name)
                }
            }
        }
        await warmTask?.value
    }
}

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

    /// Loaded prototypes by asset name. `nil` records a failed load:
    /// a missing asset costs one attempt, not one per caller.
    private static var prototypes: [String: Entity?] = [:]

    /// The one warm-up, latched so every caller awaits the same pass.
    private static var warmTask: Task<Void, Never>?

    /// Names still to load in the current pass; each worker takes the next.
    private static var pendingWarm: ArraySlice<String> = []

    /// How many assets load at once. The parse is CPU-bound and the loader
    /// runs it off the main thread, so a few in flight cut the cold launch
    /// to a fraction of the sequential time without a memory spike.
    static let warmWidth = 6

    /// The shared prototype — callers must clone before parenting.
    /// Cache-first; falls back to the old blocking load when cold.
    static func prototype(named name: String) -> Entity? {
        if prototypes[name] == nil {
            #if DEBUG
            LaunchTrace.mark("synchronous prop load on the main thread: \(name)")
            #endif
            prototypes[name] = try? Entity.load(named: name)
        }
        return prototypes[name] ?? nil
    }

    /// A fresh clone, for callers that parent the result directly —
    /// handing out the prototype would let a caller steal it from the cache.
    static func instance(named name: String) -> Entity? {
        prototype(named: name)?.clone(recursive: true)
    }

    /// Loads every bundled .usdz through the async loader, `warmWidth` at a
    /// time. Idempotent; concurrent callers await the same pass.
    static func warmUp() async {
        if warmTask == nil {
            warmTask = Task { await warmAll() }
        }
        await warmTask?.value
    }

    private static func warmAll() async {
        let names = (Bundle.main.urls(forResourcesWithExtension: "usdz",
                                      subdirectory: nil) ?? [])
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
            .filter { prototypes[$0] == nil }
        #if DEBUG
        let started = ContinuousClock.now
        #endif
        pendingWarm = names[...]
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<min(warmWidth, names.count) {
                group.addTask { @MainActor in await warmWorker() }
            }
        }
        #if DEBUG
        let seconds = (ContinuousClock.now - started) / .seconds(1)
        LaunchTrace.mark("props warm: \(names.count) assets in "
                         + String(format: "%.2f", seconds) + " s")
        #endif
    }

    /// Takes names off the shared queue until it is empty. Every worker runs
    /// on the main actor, so the queue and the cache need no lock; the
    /// concurrency is in the loader, where the await suspends.
    private static func warmWorker() async {
        while let name = pendingWarm.popFirst() {
            prototypes[name] = try? await Entity(named: name)
        }
    }
}

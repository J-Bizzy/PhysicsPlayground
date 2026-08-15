//
//  PropCache.swift
//  Physics Playground — Design System
//
//  One prototype cache for every modelled asset in the bundle, and the
//  warm-up that fills it off the main thread.
//
//  WHY THIS EXISTS. `Entity.load(named:)` is synchronous, and by
//  2026-08-15 ten call sites used it — the gallery's props and
//  platforms, the milled titles, the circuit bodies, the meter, the
//  reel, the capacitor furniture. Each kept its own little cache, which
//  solved the SECOND load of every asset and did nothing about the
//  first: building the hub parsed twenty-odd USDZ files on the main
//  thread in one pass. That was measured at ~2.4 s of swallowed frames
//  on a warm simulator launch, and under the debugger it is the
//  "Thread 1" hang Xcode keeps flagging — the app looks stuck booting
//  because its first real frame is queued behind a mountain of
//  synchronous parsing.
//
//  The warm-up loads every bundled .usdz through the ASYNC loader
//  before the immersive space opens: the window appears instantly, the
//  parsing happens while nothing is waiting on it, and by the time the
//  gallery builds, every fetch below is a dictionary hit. Enumerated
//  from the bundle rather than from a hand-kept list, for the same
//  reason CLAUDE.md greps for launch arguments instead of counting
//  them: a list somebody maintains drifts by exactly the assets
//  somebody added without updating it.
//
//  The synchronous path SURVIVES as the fallback. A caller that runs
//  before the warm-up finishes (a `-openModule` debug launch, a race
//  nobody predicted) gets exactly the old behaviour — one blocking
//  load — instead of a missing prop.
//

import Foundation
import RealityKit

@MainActor
enum PropCache {

    /// Loaded prototypes by asset name. `nil` records a FAILED load:
    /// a missing asset should cost one attempt, not one per caller —
    /// the same bargain every local cache this replaces had struck.
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

    /// A fresh clone, for callers that parent the result directly.
    /// Handing out the prototype itself would let the first caller
    /// re-parent it and steal it from the cache — a rebuilt Time Rail
    /// would silently strip the reel off the previous one.
    static func instance(named name: String) -> Entity? {
        prototype(named: name)?.clone(recursive: true)
    }

    /// Loads every bundled .usdz through the async loader. Idempotent;
    /// concurrent callers await the same underlying pass. Sequential on
    /// purpose: each `await` parses off the main actor while this loop
    /// merely suspends, and one asset at a time keeps peak memory and
    /// simulator I/O calm during launch.
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

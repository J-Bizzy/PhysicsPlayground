//
//  PropCacheTests.swift
//  PhysicsPlaygroundTests
//
//  The prop warm-up is what stands between launch and the first thing on
//  screen: it must load every bundled asset, once, however many callers
//  ask at the same time.
//

import XCTest
import RealityKit
@testable import PhysicsPlayground

@MainActor
final class PropCacheTests: XCTestCase {

    private var bundledNames: [String] {
        (Bundle.main.urls(forResourcesWithExtension: "usdz", subdirectory: nil) ?? [])
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    /// Every .usdz in the bundle comes out of the warm-up loaded, so no
    /// caller after it ever falls back to the synchronous load.
    func testWarmUpLoadsEveryBundledProp() async {
        let names = bundledNames
        XCTAssertGreaterThan(names.count, 20, "the bundle carries the props")
        await PropCache.warmUp()
        for name in names {
            XCTAssertNotNil(PropCache.prototype(named: name), "\(name) did not warm")
        }
    }

    /// One pass, shared: concurrent callers await the same task, and a
    /// second warm-up hands back the same prototypes rather than reloading.
    func testConcurrentCallersShareOnePass() async {
        async let first: Void = PropCache.warmUp()
        async let second: Void = PropCache.warmUp()
        _ = await (first, second)
        let before = PropCache.prototype(named: "HubStage")
        await PropCache.warmUp()
        XCTAssertNotNil(before)
        XCTAssertTrue(before === PropCache.prototype(named: "HubStage"),
                      "a second warm-up reloaded a prototype it already had")
    }

    /// An instance is a clone, never the prototype: parenting the shared
    /// entity would steal it from the cache.
    func testInstanceIsACloneOfThePrototype() async {
        await PropCache.warmUp()
        let prototype = PropCache.prototype(named: "HubStage")
        let instance = PropCache.instance(named: "HubStage")
        XCTAssertNotNil(instance)
        XCTAssertFalse(prototype === instance)
        XCTAssertNil(instance?.parent)
    }
}

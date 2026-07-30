//
//  GalleryLayoutTests.swift
//  PhysicsPlaygroundTests
//
//  The Gallery's geometry, proven as math: slab widths follow module
//  counts, pucks sit on their slabs at even pitch, exhibits never
//  collide across the whole settings range (the plan scales uniformly,
//  so clearances proven at the default hold everywhere), and a module
//  outside every domain extends its fallback slab instead of wrapping
//  onto someone else's spot — the bug the old constellation shipped.
//

import XCTest
import simd
@testable import PhysicsPlayground

@MainActor
final class GalleryLayoutTests: XCTestCase {

    private let allModules = HubDomain.arcOrder   // the live ids, in arc order

    /// Three terraces now, not four: Waves was archived on 2026-07-29 when
    /// the app narrowed to two labs, so its domain is benched and builds
    /// nothing.
    /// Derived from `HubDomain`, not written out — the catalog is being
    /// folded down to two flagship worlds, and a test that hard-codes
    /// today's counts fails on every phase of that for no reason. What
    /// is actually worth asserting is the RELATIONSHIP: one terrace per
    /// domain that has modules, carrying exactly that domain's modules,
    /// and none for a domain that has been benched.
    func testTerracesFollowTheLiveDomains() {
        let terraces = GalleryLayout.terraces(moduleIDs: allModules)
        let live = HubDomain.allCases.filter { !$0.moduleIDs.isEmpty }
        XCTAssertEqual(terraces.count, live.count)

        let counts = Dictionary(uniqueKeysWithValues:
            terraces.map { ($0.domain, $0.moduleIDs.count) })
        for domain in HubDomain.allCases {
            if domain.moduleIDs.isEmpty {
                XCTAssertNil(counts[domain],
                             "\(domain) is benched and must build no terrace")
            } else {
                XCTAssertEqual(counts[domain], domain.moduleIDs.count,
                               "\(domain)'s terrace lost or gained a module")
            }
        }
    }

    func testWidthsFollowModuleCounts() {
        for terrace in GalleryLayout.terraces(moduleIDs: allModules) {
            let expected = GalleryLayout.basePuckPitch * Float(terrace.moduleIDs.count)
                + GalleryLayout.baseWidthMargin
            XCTAssertEqual(terrace.width, expected, accuracy: 1e-5,
                           "\(terrace.domain) slab width")
        }
    }

    func testPucksSitOnTheirSlabAtEvenPitch() {
        for terrace in GalleryLayout.terraces(moduleIDs: allModules) {
            XCTAssertEqual(terrace.puckTops.count, terrace.moduleIDs.count)
            for top in terrace.puckTops {
                XCTAssertEqual(top.y, terrace.slabTop + GalleryLayout.puckHeight,
                               accuracy: 1e-5)
            }
            for pair in zip(terrace.puckTops, terrace.puckTops.dropFirst()) {
                XCTAssertEqual(simd_distance(pair.0, pair.1),
                               GalleryLayout.basePuckPitch, accuracy: 1e-4,
                               "\(terrace.domain) puck pitch")
            }
        }
    }

    func testExhibitsFloatAboveTheirPucks() {
        for terrace in GalleryLayout.terraces(moduleIDs: allModules) {
            for (top, exhibit) in zip(terrace.puckTops, terrace.exhibitPositions) {
                XCTAssertEqual(exhibit.x, top.x, accuracy: 1e-6)
                XCTAssertEqual(exhibit.y, top.y + GalleryLayout.exhibitLift,
                               accuracy: 1e-6)
                XCTAssertEqual(exhibit.z, top.z, accuracy: 1e-6)
            }
        }
    }

    func testDistanceScalesThePlanAndHeightScalesTheTops() {
        let reference = GalleryLayout.terraces(moduleIDs: allModules)
        let scaled = GalleryLayout.terraces(moduleIDs: allModules,
                                            distance: 3.0, height: 1.8)
        for (a, b) in zip(reference, scaled) {
            // Plan (XZ) scales by 3.0/2.0.
            XCTAssertEqual(b.center.x, a.center.x * 1.5, accuracy: 1e-4)
            XCTAssertEqual(b.center.z, a.center.z * 1.5, accuracy: 1e-4)
            XCTAssertEqual(b.width, a.width * 1.5, accuracy: 1e-4)
            // Heights scale by 1.8/1.4.
            XCTAssertEqual(b.slabTop, a.slabTop * (1.8 / 1.4), accuracy: 1e-4)
        }
    }

    func testExhibitsNeverCollideAcrossTheSettingsRange() {
        // 0.24 m exhibits need 0.26 m of air. Uniform plan scaling makes
        // the default the worst case relatively, but check the slider
        // extremes anyway — this is the constraint the layout exists to
        // keep.
        for distance in [Float(1.5), 2.0, 3.0] {
            let terraces = GalleryLayout.terraces(moduleIDs: allModules,
                                                  distance: distance)
            let exhibits = terraces.flatMap(\.exhibitPositions)
            for i in exhibits.indices {
                for j in exhibits.indices where j > i {
                    XCTAssertGreaterThan(
                        simd_distance(exhibits[i], exhibits[j]), 0.26,
                        "exhibits \(i) and \(j) collide at distance \(distance)")
                }
            }
        }
    }

    func testSlabsNeverOverlapAcrossTheSettingsRange() {
        // Adjacent slab ends, compared along the crescent: the gap
        // between one slab's right end and the next one's left end must
        // stay positive at every slider position.
        for distance in [Float(1.5), 2.0, 3.0] {
            let terraces = GalleryLayout.terraces(moduleIDs: allModules,
                                                  distance: distance)
            for (a, b) in zip(terraces, terraces.dropFirst()) {
                func end(_ t: GalleryLayout.Terrace, _ side: Float) -> SIMD3<Float> {
                    let tangent = SIMD3<Float>(cos(-t.yaw), 0, sin(-t.yaw))
                    return t.center + tangent * (side * t.width / 2)
                }
                let gap = simd_distance(end(a, 1), end(b, -1))
                XCTAssertGreaterThan(gap, 0.05,
                                     "\(a.domain)–\(b.domain) slabs touch at distance \(distance)")
            }
        }
    }

    func testNinthModuleExtendsItsFallbackSlabInsteadOfWrapping() {
        // "optics" is in no domain's list; domain(for:) falls back to
        // mechanics — its slab grows a third puck, nothing overlaps
        // anything, and no other terrace moves.
        let with = GalleryLayout.terraces(moduleIDs: allModules + ["optics"])
        let without = GalleryLayout.terraces(moduleIDs: allModules)

        let mechanics = with.first { $0.domain == .mechanics }!
        XCTAssertEqual(mechanics.moduleIDs.count, 3)
        XCTAssertTrue(mechanics.moduleIDs.contains("optics"))
        XCTAssertEqual(mechanics.width,
                       GalleryLayout.basePuckPitch * 3 + GalleryLayout.baseWidthMargin,
                       accuracy: 1e-5)

        for domain in [HubDomain.electricity, .fluidsGravity] {
            let a = with.first { $0.domain == domain }!
            let b = without.first { $0.domain == domain }!
            XCTAssertEqual(a.center, b.center)
            XCTAssertEqual(a.width, b.width)
        }

        // Every exhibit position is unique — the wrap bug stays dead.
        let exhibits = with.flatMap(\.exhibitPositions)
        for i in exhibits.indices {
            for j in exhibits.indices where j > i {
                XCTAssertGreaterThan(simd_distance(exhibits[i], exhibits[j]), 0.2)
            }
        }
    }

    /// The crescent closes up around an archived domain rather than showing
    /// an empty shelf — which is what makes benching a domain a one-line
    /// change to its module list.
    func testBenchedDomainGetsNoTerrace() {
        XCTAssertTrue(HubDomain.waves.moduleIDs.isEmpty, "waves is benched")
        let terraces = GalleryLayout.terraces(moduleIDs: allModules)
        XCTAssertFalse(terraces.contains { $0.domain == .waves })

        // And an id belonging to no live domain still lands somewhere
        // rather than vanishing: it extends its fallback slab.
        let orphan = GalleryLayout.terraces(moduleIDs: ["waves"])
        XCTAssertEqual(orphan.count, 1)
        XCTAssertEqual(orphan[0].moduleIDs, ["waves"])
    }
}

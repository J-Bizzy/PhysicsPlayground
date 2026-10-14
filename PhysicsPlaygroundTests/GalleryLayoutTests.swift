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
import RealityKit
@testable import PhysicsPlayground

@MainActor
final class GalleryLayoutTests: XCTestCase {

    private let allModules = HubDomain.arcOrder   // the live ids, in arc order

    /// Derived from `HubDomain`, not written out: one terrace per domain
    /// that has modules, carrying exactly that domain's modules, and none
    /// for a benched domain.
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

        // Derived, not written out: the property is that the orphan
        // lands on its fallback domain and widens that slab by exactly
        // one puck — true whatever the catalog currently holds.
        let expected = HubDomain.mechanics.moduleIDs.count + 1
        let mechanics = with.first { $0.domain == .mechanics }!
        XCTAssertEqual(mechanics.moduleIDs.count, expected)
        XCTAssertTrue(mechanics.moduleIDs.contains("optics"))
        XCTAssertEqual(mechanics.width,
                       GalleryLayout.basePuckPitch * Float(expected)
                           + GalleryLayout.baseWidthMargin,
                       accuracy: 1e-5)

        // …and no other terrace moves or resizes to accommodate it.
        for domain in HubDomain.allCases where domain != .mechanics {
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

    /// A door with none of its experiences benched builds no terrace; the
    /// fixture benches one by omission.
    func testBenchedDomainGetsNoTerrace() {
        let mechanicsOnly = HubDomain.mechanics.moduleIDs
        let terraces = GalleryLayout.terraces(moduleIDs: mechanicsOnly)
        XCTAssertEqual(terraces.count, 1)
        XCTAssertFalse(terraces.contains { $0.domain == .electricity },
                       "no benched experience, no terrace")

        // And an id belonging to no live domain still lands somewhere
        // rather than vanishing: it extends its fallback slab.
        let orphan = GalleryLayout.terraces(moduleIDs: ["waves"])
        XCTAssertEqual(orphan.count, 1)
        XCTAssertEqual(orphan[0].moduleIDs, ["waves"])
    }

    /// Every lab's name is an inlay on the bench's front edge, under its
    /// mount, at `HubScene.benchLabelSize` — the one surface a longer module
    /// title could run into. Measured, so "Orbital Mechanics" (joint-longest
    /// with "Projectile Motion") is a number rather than a screenshot: a
    /// label stays inside its own pitch cell, two neighbours keep 3 cm of
    /// bare graphite between them (nothing backs the type, so the gap is
    /// all that says where one name ends), and every label fits the face
    /// it is inlaid in with the chamfers clear.
    func testEveryExhibitTitleFitsItsPitch() {
        let pitch = GalleryLayout.basePuckPitch
        let modules = ModuleCatalog.all(appModel: AppModel())
        let width = Dictionary(uniqueKeysWithValues: modules.map {
            ($0.id, HubScene.benchLabelWidth($0.title))
        })
        for module in modules {
            XCTAssertLessThan(width[module.id] ?? .infinity, pitch - 0.03, """
                \(module.title)'s bench label is \(width[module.id] ?? 0) m wide, \
                past its own \(pitch) m pitch less a 3 cm gap.
                """)
            let height = HubScene.benchLabel(module.title, accent: .white)
                .visualBounds(relativeTo: nil).extents.y
            XCTAssertLessThan(height, GalleryLayout.slabThickness - 0.016, """
                \(module.title)'s bench label is \(height) m tall on a \
                \(GalleryLayout.slabThickness) m face; it would run into the \
                chamfers or past the edge.
                """)
        }
        let order = HubDomain.arcOrder
        for (left, right) in zip(order, order.dropFirst()) {
            let reach = ((width[left] ?? 0) + (width[right] ?? 0)) / 2
            XCTAssertLessThan(reach, pitch - 0.03, """
                the bench labels of \(left) and \(right) reach \(reach) m toward \
                each other across a \(pitch) m pitch.
                """)
        }
    }

    /// The names are on the bench, so nothing lifted or docked can carry one
    /// into a door sign: each label stands on its terrace's front face,
    /// directly under its own exhibit, and nowhere near the sign above.
    func testEveryLabelStandsUnderItsExhibitOnTheBenchFace() throws {
        let modules = ModuleCatalog.all(appModel: AppModel())
        let scene = HubScene()
        scene.build(modules: modules)

        var labels: [Entity] = []
        func walk(_ entity: Entity) {
            if entity.name == "bench-label" { labels.append(entity) }
            entity.children.forEach(walk)
        }
        walk(scene.root)
        XCTAssertEqual(labels.count, modules.count,
                       "one label per lab, on its bench")

        for module in modules {
            let exhibit = try XCTUnwrap(scene.root.children.first { $0.name == module.id })
            let at = exhibit.position(relativeTo: nil)
            let label = try XCTUnwrap(labels.min {
                simd_distance($0.position(relativeTo: nil), at)
                    < simd_distance($1.position(relativeTo: nil), at)
            })
            let labelAt = label.position(relativeTo: nil)
            let horizontal = simd_length(SIMD2(labelAt.x - at.x, labelAt.z - at.z))
            XCTAssertLessThan(horizontal, GalleryLayout.slabDepth / 2 + 0.02, """
                \(module.title)'s label is \(horizontal) m from under its exhibit.
                """)
            XCTAssertLessThan(labelAt.y, at.y - GalleryLayout.exhibitLift, """
                \(module.title)'s label stands above its mount; it belongs on \
                the bench's edge.
                """)
        }
    }
}

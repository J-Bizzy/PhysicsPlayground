//
//  GalleryCaptionTests.swift
//  PhysicsPlaygroundTests
//
//  A CAPTION BELONGS TO ONE EXHIBIT.
//
//  `HubDomain.promise` is the hand-written line saying what you actually
//  do in a lab, and waking it was a goal of this arc. It woke as a
//  single-line `namePlate` — the builder every other caller feeds a
//  lab's NAME — so a sentence became one long plate running straight
//  through the neighbouring exhibits' names and behind its own ENTER
//  plaque. The photograph (2026-08-08, `-hubFocus pendulums`) shows the
//  Pendulums promise crossing "Projectile Mo…" on one side and "Gravity
//  Lab" on the other.
//
//  Nothing was broken and nothing was untested. The caption simply
//  belonged to three exhibits at once.
//
//  The rule is arithmetic, so it is a test rather than an eye: pucks are
//  `GalleryLayout.basePuckPitch` apart, so a caption wider than that
//  overlaps its neighbour by construction. Asserted for EVERY module's
//  real promise string, at the real size, because the one that overflows
//  will be whichever one someone rewrites longest.
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class GalleryCaptionTests: XCTestCase {

    /// The size the gallery draws a promise at.
    private static let promiseSize: CGFloat = 0.016

    private func plateWidth(of entity: Entity) -> Float {
        var widest: Float = 0
        func walk(_ node: Entity) {
            if let model = node as? ModelEntity,
               let bounds = model.model?.mesh.bounds {
                widest = max(widest, bounds.extents.x)
            }
            node.children.forEach(walk)
        }
        walk(entity)
        return widest
    }

    func testNoPromiseCaptionIsWiderThanItsOwnExhibit() {
        let pitch = GalleryLayout.basePuckPitch
        for module in ModuleCatalog.all(appModel: AppModel()) {
            let promise = HubDomain.promise(for: module.id)
            guard !promise.isEmpty else { continue }
            let plate = HubScene.namePlate(
                promise,
                accent: .white,
                size: Self.promiseSize,
                wrapWidth: CGFloat(pitch * 0.84))
            let width = plateWidth(of: plate)
            XCTAssertLessThan(width, pitch, """
                \(module.id)'s promise makes a \(width) m caption against a \
                \(pitch) m puck pitch, so it runs through the exhibit next \
                to it: "\(promise)"
                """)
        }
    }

    /// EVERY LAB HAS ONE. Waking the promise means nothing if a module
    /// answers with an empty string and silently gets no caption.
    func testEveryLabPromisesSomething() {
        for module in ModuleCatalog.all(appModel: AppModel()) {
            let promise = HubDomain.promise(for: module.id)
            XCTAssertFalse(promise.isEmpty,
                           "\(module.id) has no promise line")
        }
    }

    /// The criterion can fail. Without this it is asserting that wrapping
    /// works against a builder that might be ignoring `wrapWidth`.
    func testAnUnwrappedSentenceWouldBeCaughtByThisRule() {
        let sentence = HubDomain.promise(for: "pendulums")
        let unwrapped = HubScene.namePlate(sentence, accent: .white,
                                           size: Self.promiseSize)
        XCTAssertGreaterThan(plateWidth(of: unwrapped),
                             GalleryLayout.basePuckPitch, """
            the same sentence drawn UNWRAPPED fits inside a puck pitch, so \
            the wrapped assertion above proves nothing — either the string \
            got much shorter or `namePlate` is wrapping regardless.
            """)
    }

    /// NO TEST HERE ASSERTS THE PLAQUE CLEARS THE CAPTION, and that is
    /// deliberate.
    ///
    /// One was written on 2026-08-09 and passed over a photograph with
    /// ENTER drawn through the sentence. The caption billboards from
    /// z 0.11 and the plaque from z 0.165, so their on-screen order is
    /// not their y order, and a test comparing y values is measuring
    /// something other than what it claims. Acting on it moved the
    /// plaque into the terrace slab and made every ENTER in the gallery
    /// disappear — green the whole way.
    ///
    /// A test that cannot see the thing it asserts is worse than no
    /// test, because it is also a claim that somebody checked. The
    /// overlap is real and open; see the grave in `HubScene`.
}

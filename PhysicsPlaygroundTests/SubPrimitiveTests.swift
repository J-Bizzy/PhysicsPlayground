//
//  SubPrimitiveTests.swift
//  PhysicsPlaygroundTests
//
//  The 2026-08-05 consolidation pass folded three hand-rolled copies of
//  the selection halo and three of the +/− sign glyph into shared
//  builders. These tests pin the two behaviours the fold could have
//  silently changed, in the house style: build the REAL entities and
//  read the scene graph, because the variable a builder was handed is
//  not what a wearer sees.
//
//  · The sign glyph now always builds BOTH strokes and disables the
//    vertical for a minus (so the probe's polarity can flip live
//    without rebuilding mid-pinch). A minus that still SHOWS two
//    strokes would be a physics label lying about a sign.
//  · A halo is decoration, never a target: hidden until selected, and
//    carrying no collider — the SpatialScaleHandle law. A halo with a
//    collider steals the pinch aimed at the thing it decorates.
//

import XCTest
import RealityKit
@testable import PhysicsPlayground

@MainActor
final class SubPrimitiveTests: XCTestCase {

    // MARK: Sign glyphs

    func testNegativeSignGlyphHidesItsVerticalStroke() {
        let (_, vertical) = FieldRenderer.signGlyphParts(radius: 0.03)
        XCTAssertTrue(vertical.isEnabled,
                      "the parts builder hands back a live vertical; the caller decides")

        let minus = FieldRenderer.signGlyph(isPositive: false, radius: 0.03)
        let strokes = minus.children.compactMap { $0 as? ModelEntity }
        XCTAssertEqual(strokes.count, 2,
                       "both strokes must exist so polarity can flip without a rebuild")
        XCTAssertEqual(strokes.filter(\.isEnabled).count, 1,
                       "a minus shows exactly one stroke")

        let plus = FieldRenderer.signGlyph(isPositive: true, radius: 0.03)
        XCTAssertEqual(plus.children.compactMap { $0 as? ModelEntity }
                           .filter(\.isEnabled).count, 2,
                       "a plus shows both strokes")
    }

    func testPlateGlyphTakesItsBarFromThePlateNotTheRadius() {
        // The capacitor plates pass radius 0 and a bar length of their
        // own scale; the glyph must still have visible extent.
        let plate = FieldRenderer.signGlyph(isPositive: true, radius: 0,
                                            barLength: 0.05)
        let horizontal = plate.children.compactMap { $0 as? ModelEntity }.first
        let width = horizontal?.model?.mesh.bounds.extents.x ?? 0
        XCTAssertEqual(width, 0.05, accuracy: 0.001,
                       "the plate's bar length is the plate's, not a sphere's")
    }

    // MARK: Selection halo

    func testSelectionHaloIsHiddenAndNeverATarget() {
        let halo = SelectionHalo.make(mesh: .generateSphere(radius: 0.1))
        XCTAssertFalse(halo.isEnabled, "a halo waits for selection")
        XCTAssertNil(halo.components[CollisionComponent.self],
                     "a halo with a collider steals the pinch aimed at its object")
        XCTAssertNil(halo.components[InputTargetComponent.self],
                     "a halo is decoration, not input")
    }
}

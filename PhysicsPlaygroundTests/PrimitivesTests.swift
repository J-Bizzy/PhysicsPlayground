//
//  PrimitivesTests.swift
//  PhysicsPlaygroundTests
//
//  The shared primitive cache: the same dimensions hand back the same
//  resource, different ones do not, and a copied material is a value —
//  the property that lets a cached material be handed out and recoloured.
//

import XCTest
import RealityKit
import RenderKit
import UIKit
@testable import PhysicsPlayground

@MainActor
final class PrimitivesTests: XCTestCase {

    func testTheSameDimensionsShareOneMesh() {
        XCTAssertTrue(Primitives.sphere(radius: 0.0123) === Primitives.sphere(radius: 0.0123))
        XCTAssertTrue(Primitives.box(size: [0.1, 0.02, 0.01], cornerRadius: 0.004)
                      === Primitives.box(width: 0.1, height: 0.02, depth: 0.01, cornerRadius: 0.004))
        XCTAssertTrue(Primitives.cylinder(height: 0.05, radius: 0.01)
                      === Primitives.cylinder(height: 0.05, radius: 0.01))
    }

    func testDifferentDimensionsDoNot() {
        XCTAssertFalse(Primitives.sphere(radius: 0.0123) === Primitives.sphere(radius: 0.0124))
        XCTAssertFalse(Primitives.plane(width: 0.1, height: 0.02) === Primitives.plane(width: 0.1, depth: 0.02))
        XCTAssertFalse(Primitives.box(size: [0.1, 0.02, 0.01]) === Primitives.box(size: [0.1, 0.02, 0.01], cornerRadius: 0.002))
    }

    func testCollidersShareTooAndKeepTheirOffset() {
        XCTAssertTrue(Primitives.collisionSphere(radius: 0.03) === Primitives.collisionSphere(radius: 0.03))
        let offset = Primitives.collisionBox(size: [0.1, 0.02, 0.02], offset: [0, 0.05, 0])
        XCTAssertTrue(offset === Primitives.collisionBox(size: [0.1, 0.02, 0.02], offset: [0, 0.05, 0]))
        XCTAssertFalse(offset === Primitives.collisionBox(size: [0.1, 0.02, 0.02]))
        XCTAssertEqual(offset.bounds.center.y, 0.05, accuracy: 1e-4)
        XCTAssertEqual(Primitives.collisionBox(size: [0.1, 0.02, 0.02]).bounds.center.y, 0, accuracy: 1e-4)
    }

    /// A copied material must not share state with its source, or a cache
    /// handing out one material would let one caller recolour every other.
    func testACopiedMaterialIsAValue() {
        let source = Materials.machined(.white)
        var copy = source
        copy.baseColor = .init(tint: .red)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        source.baseColor.tint.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(g, 1, accuracy: 0.01, "recolouring a copy recoloured the cached original")
        var unlit = Materials.unlit(.white, opacity: 0.5)
        let unlitCopy = unlit
        unlit.color = .init(tint: .red)
        unlitCopy.color.tint.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(g, 1, accuracy: 0.01)
    }

    /// The recipes memoise: the same arguments come back as one resource.
    func testMaterialRecipesAreMemoised() {
        XCTAssertEqual(Materials.machined(UIColor(white: 0.5, alpha: 1)).baseColor.tint,
                       Materials.machined(UIColor(white: 0.5, alpha: 1)).baseColor.tint)
        let before = Materials.cachedCount
        _ = Materials.unlit(UIColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1), opacity: 0.4)
        _ = Materials.unlit(UIColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1), opacity: 0.4)
        XCTAssertEqual(Materials.cachedCount, before + 1, "the second identical recipe built a second material")
        _ = Materials.unlit(UIColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1), opacity: 0.5)
        XCTAssertEqual(Materials.cachedCount, before + 2)
    }
}

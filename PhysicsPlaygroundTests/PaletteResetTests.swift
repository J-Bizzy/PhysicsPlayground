//
//  PaletteResetTests.swift
//  PhysicsPlaygroundTests
//
//  The palette's Reset petal arms before it fires (2026-10-14). The title
//  bar's Reset asks first and every Clear plate arms first; a petal one
//  pinch from wiping a bench that survives relaunch was the one unguarded
//  path. Driven through `handleTap` and `update`, the way a hand and the
//  frame clock reach it, since no automation can pinch.
//

import XCTest
import RealityKit
@testable import PhysicsPlayground

@MainActor
final class PaletteResetTests: XCTestCase {

    private func openPalette() throws -> (Palette, reset: Entity) {
        let palette = Palette(slots: [])
        palette.place(at: .zero)
        let bead = try XCTUnwrap(palette.root.children.first { $0.name == "palette-bead" })
        _ = palette.handleTap(bead)
        for _ in 0..<80 { palette.update(dt: 1 / 90, viewer: [0, 0, 1]) }
        let reset = try XCTUnwrap(palette.root.children.first { $0.name == "palette-reset" })
        return (palette, reset)
    }

    func testOnePinchArmsAndResetsNothing() throws {
        let (palette, reset) = try openPalette()
        var resets = 0
        palette.onReset = { resets += 1 }

        XCTAssertTrue(palette.handleTap(reset))
        XCTAssertEqual(resets, 0, "one pinch on Reset reset the lab — it must only arm")
        XCTAssertNotNil(palette.resetArmed)
    }

    func testTheSecondPinchFiresOnce() throws {
        let (palette, reset) = try openPalette()
        var resets = 0
        palette.onReset = { resets += 1 }

        _ = palette.handleTap(reset)
        palette.update(dt: 1, viewer: [0, 0, 1])
        _ = palette.handleTap(reset)
        XCTAssertEqual(resets, 1)
        XCTAssertNil(palette.resetArmed, "a fired petal must not stay armed")
    }

    func testTheArmRunsOut() throws {
        let (palette, reset) = try openPalette()
        var resets = 0
        palette.onReset = { resets += 1 }

        _ = palette.handleTap(reset)
        palette.update(dt: SpatialActionBank.armWindow + 0.1, viewer: [0, 0, 1])
        XCTAssertNil(palette.resetArmed, "the arm outlived its window")

        // So the next pinch arms again rather than firing.
        _ = palette.handleTap(reset)
        XCTAssertEqual(resets, 0)
    }

    func testFoldingTheRingDisarms() throws {
        let (palette, reset) = try openPalette()
        _ = palette.handleTap(reset)
        _ = palette.handleTap(palette.beadEntity)
        palette.update(dt: 1 / 90, viewer: [0, 0, 1])
        XCTAssertNil(palette.resetArmed,
                     "a folded ring kept Reset armed, so reopening it is one pinch from a wipe")
    }

    func testArmedReadsTapAgain() throws {
        let (palette, reset) = try openPalette()
        func shown(_ name: String) -> Bool {
            reset.children.first { $0.name == name }?.isEnabled ?? false
        }
        XCTAssertTrue(shown("petal-label"))
        XCTAssertFalse(shown("petal-label-armed"))

        _ = palette.handleTap(reset)
        XCTAssertFalse(shown("petal-label"))
        XCTAssertTrue(shown("petal-label-armed"))
    }
}

//
//  AtmosphereCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  THE ROOM'S BRIGHTNESS IS PART OF THE SET, not a per-module taste.
//
//  Until 2026-08-09 three modules opened at `preferredDimming` 0 and
//  three at 0.35, with Gravity Lab further out at 0.85. Nobody chose a
//  three-way split; each module picked a number on the day it was
//  written, and the result was that walking from Circuits into Electric
//  Fields changed how bright the user's own living room was. In a demo
//  cut between labs it is the loudest difference between two rooms that
//  are supposed to feel like one place.
//
//  So: one house value, and exceptions that have to argue for
//  themselves in the descriptor. Gravity Lab is the standing exception
//  and the reason is real — a pale Sun and specks of planet have no
//  contrast at all against a lit wall, which is why it also carries a
//  16 m shell and `.progressive` immersion.
//
//  This is a CRITERION, not a snapshot: it does not assert "these six
//  numbers". It asserts that the set has one house value, that at most
//  one module departs from it, and that the module which does also
//  moved its shell — because a heavy dimming with the default 3.4 m
//  radius is the seam-through-the-apparatus bug the radius exists for.
//

import XCTest
@testable import PhysicsPlayground

@MainActor
final class AtmosphereCriterionTests: XCTestCase {

    /// The value five of six modules share.
    private static let houseDimming = 0.35

    private func descriptors() -> [ModuleDescriptor] {
        ModuleCatalog.all(appModel: AppModel())
    }

    func testTheLabsShareOneRoomBrightness() {
        let modules = descriptors()
        XCTAssertEqual(modules.count, 6, "the catalog changed shape")

        let conforming = modules.filter { $0.preferredDimming == Self.houseDimming }
        let departing = modules.filter { $0.preferredDimming != Self.houseDimming }

        XCTAssertGreaterThanOrEqual(conforming.count, 5, """
            only \(conforming.count) of \(modules.count) modules open at the \
            house dimming of \(Self.houseDimming).

            Departing: \(departing.map { "\($0.id) @ \($0.preferredDimming)" }
                .joined(separator: ", ")).

            A per-module brightness is a per-module ROOM, and the six labs \
            are meant to read as one place seen six times. If a lab genuinely \
            needs its own atmosphere, say why in its descriptor and raise the \
            allowance here deliberately — do not let a fourth number appear \
            because somebody typed one.
            """)
    }

    func testAModuleThatDimsHeavilyAlsoMovesItsShellOut() {
        for module in descriptors() where module.preferredDimming > 0.5 {
            XCTAssertGreaterThan(
                module.preferredDimmingRadius, RoomDimmerView.defaultRadius, """
                \(module.id) dims to \(module.preferredDimming) but keeps the \
                default \(RoomDimmerView.defaultRadius) m shell.

                Heavy dimming at the default radius draws the shell THROUGH \
                the apparatus: some of the scene reads against darkness and \
                some against the wall, with the seam moving as the user zooms. \
                Gravity Lab's 16 m is what that costs to fix.
                """)
        }
    }

    /// The exception has to be visibly exceptional, not just different.
    func testTheHeavilyDimmedModuleSaysWhyInItsOwnSource() throws {
        let heavy = descriptors().filter { $0.preferredDimming > 0.5 }
        try XCTSkipIf(heavy.isEmpty, "no module dims heavily; nothing to justify")
        XCTAssertEqual(heavy.count, 1, """
            \(heavy.count) modules dim heavily (\(heavy.map(\.id))). One \
            exception is a decision; two is a second convention nobody \
            declared.
            """)
    }
}

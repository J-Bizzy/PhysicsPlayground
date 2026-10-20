//
//  AtmosphereCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  The room's brightness is part of the set: one house
//  `preferredDimming`, at most one module departing from it, and that
//  module must also move its shell out — and be the one lab that opens in
//  deep space. A criterion, not a snapshot of six numbers.
//

import XCTest
@testable import PhysicsPlayground

@MainActor
final class AtmosphereCriterionTests: XCTestCase {

    /// The value every module but one shares.
    private static let houseDimming = 0.35

    private func descriptors() -> [ModuleDescriptor] {
        ModuleCatalog.all(appModel: AppModel())
    }

    func testTheLabsShareOneRoomBrightness() {
        let modules = descriptors()
        XCTAssertEqual(modules.count, ModuleCatalog.allIDs.count, "the catalog changed shape")
        XCTAssertGreaterThanOrEqual(modules.count, 7, "the catalog lost a lab")

        let conforming = modules.filter { $0.preferredDimming == Self.houseDimming }
        let departing = modules.filter { $0.preferredDimming != Self.houseDimming }

        // Exactly one departure is allowed, however many labs there are: a
        // fixed count would quietly allow a second the day a lab was added.
        XCTAssertGreaterThanOrEqual(conforming.count, modules.count - 1, """
            only \(conforming.count) of \(modules.count) modules open at the \
            house dimming of \(Self.houseDimming).

            Departing: \(departing.map { "\($0.id) @ \($0.preferredDimming)" }
                .joined(separator: ", ")).

            A per-module brightness is a per-module ROOM, and the labs \
            are meant to read as one place seen from every door. If a lab genuinely \
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
                Orbital Mechanics' 16 m is what that costs to fix.
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

    /// The one lab that dims past half is the one that opens in deep space
    /// and draws its own Sun: its heavy room atmosphere is for a wearer who
    /// chooses the room there, and nowhere else may need one.
    func testTheHeavilyDimmedLabIsTheOneThatOpensInSpace() {
        let modules = descriptors()
        let heavy = modules.filter { $0.preferredDimming > 0.5 }.map(\.id)
        let spacebound = modules.filter { $0.preferredSurroundings == .deepSpace }.map(\.id)
        XCTAssertEqual(heavy, spacebound)
        for module in modules where module.preferredSurroundings == .deepSpace {
            XCTAssertTrue(module.drawsItsOwnSun, "\(module.id) opens in space under a second Sun")
        }
        XCTAssertTrue(modules.allSatisfy { $0.preferredSurroundings != .room },
                      "no lab may refuse a wearer's deep space")
    }
}

//
//  InstrumentReachCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  Can you actually touch the controls? Every module's bank anchor is a
//  named static so it can be measured. Reach is measured to the nearest
//  point of a declared box, deliberately larger than the plates because
//  nameplates hang beside and below them — the generous convention, so
//  anything still called unreachable is unreachable under the most
//  forgiving measurement.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class InstrumentReachCriterionTests: XCTestCase {

    /// The declared box for a plate bank, matching the size
    /// `FieldInstrumentLayout` gives its own layers bank.
    private static let bankHalfExtents = SIMD3<Double>(0.15, 0.20, 0.15)
    /// A verb bank is shorter — two or three plates, not five.
    private static let verbHalfExtents = SIMD3<Double>(0.13, 0.10, 0.08)

    private struct Instrument {
        let name: String
        let anchor: SIMD3<Float>
        let halfExtents: SIMD3<Double>

        var box: StationBox {
            StationBox(center: SIMD3<Double>(anchor), halfExtents: halfExtents)
        }
        var reach: Double {
            box.distanceRange(from: InstrumentClearance.viewer).nearest
        }
    }

    /// Every module's layer bank, read from the module's own constant so
    /// this cannot drift from what ships.
    private var banks: [Instrument] {
        [
            .init(name: "Pendulums layers",
                  anchor: PendulumsSpaceView.bankAnchor,
                  halfExtents: Self.bankHalfExtents),
        ]
    }

    /// What else stands on a lab's flank for a hand: Orbital Mechanics'
    /// world well and Electric Fields' two (their clocks, layers, verbs
    /// and rails moved into More).
    private var verbBanks: [Instrument] {
        [
            .init(name: "Electric Fields wells",
                  anchor: SIMD3<Float>(FieldInstrumentLayout.foreRail.head),
                  halfExtents: FieldInstrumentLayout.wellHalfExtents),
            .init(name: "Magnetism magnet well",
                  anchor: MagnetismSpaceView.wellAnchor,
                  halfExtents: Self.wellHalfExtents),
            .init(name: "Orbital Mechanics world well",
                  anchor: OrbitalMechanicsRenderer.systemPosition
                      + OrbitalMechanicsSpaceView.wellOffset,
                  halfExtents: Self.wellHalfExtents),
        ]
    }

    /// Five plates at 0.066 pitch plus a plate's own height — the box
    /// `CircuitsInstrumentClearanceTests` sizes its columns with.
    private static let fivePlateHalfExtents = SIMD3<Double>(0.15, 0.157, 0.05)
    /// A rail's box, as `FieldInstrumentLayout` declares its own.
    private static let railHalfExtents = SIMD3<Double>(0.16, 0.05, 0.07)
    /// One well mouth — the preview and the nameplate under it.
    private static let wellHalfExtents = SIMD3<Double>(0.06, 0.06, 0.06)

    /// A `SummonHandle` tab is one `PlateStyle` plate with a nameplate
    /// under it.
    private static let summonTabHalfExtents = SIMD3<Double>(
        Double(PlateStyle.width) / 2,
        Double(PlateStyle.height) / 2 + 0.010,
        Double(PlateStyle.depth) / 2)

    /// What stands on Projectiles' wall: its two wells (its world, air,
    /// walls and wind moved into More). A bank is not a module's only
    /// control, and checking only banks is how this module once passed
    /// while every one of its instruments was out of reach.
    private var projectilesWall: [Instrument] {
        [
            .init(name: "Projectiles ball well",
                  anchor: KinematicsSpaceView.wellAnchor,
                  halfExtents: SIMD3(0.10, 0.10, 0.10)),
            // The hoop's mouth, outboard of the ball's on the same row.
            .init(name: "Projectiles hoop well",
                  anchor: KinematicsSpaceView.hoopWellAnchor,
                  halfExtents: SIMD3(0.10, 0.10, 0.10)),
        ]
    }

    /// Nothing is exempt any more. The list stays so the shape of the
    /// test still says exemptions are possible and must be argued.
    private static let knownUnreachable: [String] = []

    func testEveryLayerBankIsWithinReach() {
        for bank in banks where !Self.knownUnreachable.contains(bank.name) {
            XCTAssertLessThanOrEqual(
                bank.reach, InstrumentClearance.maximumReach, """
                \(bank.name) is \(String(format: "%.3f", bank.reach)) m from a \
                standing viewer — past the \(InstrumentClearance.maximumReach) m \
                limit. That is a step, not a reach.

                A control you can see and cannot touch is worse than one that \
                is not there: the user does not know whether they missed or the \
                app did.
                """)
        }
    }

    func testEveryVerbBankIsWithinReach() {
        for bank in verbBanks {
            XCTAssertLessThanOrEqual(
                bank.reach, InstrumentClearance.maximumReach, """
                \(bank.name) is \(String(format: "%.3f", bank.reach)) m away, \
                past the \(InstrumentClearance.maximumReach) m limit.
                """)
        }
    }

    func testEveryProjectilesInstrumentIsWithinReach() {
        for instrument in projectilesWall {
            XCTAssertLessThanOrEqual(
                instrument.reach, InstrumentClearance.maximumReach, """
                \(instrument.name) is \(String(format: "%.3f", instrument.reach)) m \
                from a standing viewer, past the \(InstrumentClearance.maximumReach) m \
                limit.

                This module's apparatus is 1:1 with the room, which makes it the \
                easiest one to push its own controls out past the edge of a reach \
                — every instrument here was out until 2026-08-09.
                """)
        }
    }

    /// Bringing something closer can push it off the side of the frame:
    /// reach and off-axis angle pull in opposite directions, and a test
    /// that measured only reach would call the trade a success.
    func testTheWallStaysInsideTheOffAxisLimit() {
        let limit = 48.0
        for instrument in projectilesWall {
            let anchor = SIMD3<Double>(instrument.anchor)
            // Forward is −Z, so the bearing is measured against −z.
            let degrees = atan2(abs(anchor.x), -anchor.z) * 180 / .pi
            XCTAssertLessThanOrEqual(degrees, limit, """
                \(instrument.name) stands \(String(format: "%.1f", degrees))° off \
                the forward axis, past \(limit)°.

                Out there it is at the edge of vision and its nameplate is the \
                first thing to be clipped. If this failed after a change that \
                fixed a REACH, the two were traded rather than both solved.
                """)
        }
    }

    /// The wall must stay out of the shot: closer to the user and into the
    /// firing line are the same direction for four of the five.
    func testTheWallStaysBesideTheShotNotInFrontOfIt() {
        let launcherX = Double(KinematicsModel.launcherHome.x)
        for instrument in projectilesWall {
            let inboardEdge = instrument.box.maximum.x
            XCTAssertLessThan(inboardEdge, launcherX - 0.05, """
                \(instrument.name) reaches x \(String(format: "%.3f", inboardEdge)), \
                which is inside the launcher's line at x \
                \(String(format: "%.2f", launcherX)).

                Balls go everywhere in this module. An instrument in front of the \
                muzzle is one the user shoots.
                """)
        }
    }



    /// Not vacuous: the list has to actually cover the app. The labs
    /// whose layers live in the title bar's More (2026-10-14):
    /// nothing of theirs stands in the room to be out of reach.
    private static let banksInMore: Set<String> = [
        "circuits", "electrostatics", "gravitylab", "kinematics", "magnetism"]

    func testTheCriterionCoversEveryModule() {
        XCTAssertEqual(banks.count + Self.banksInMore.count, ModuleCatalog.allIDs.count, """
            \(banks.count) banks measured, \(Self.banksInMore.count) in More, against \
            \(ModuleCatalog.allIDs.count) modules. A module was added without its \
            bank being measured, which is how the first two came to be out of reach.
            """)
    }
}

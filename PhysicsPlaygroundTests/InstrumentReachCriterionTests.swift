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
            .init(name: "Electric Fields layers",
                  anchor: SIMD3<Float>(FieldInstrumentLayout.leftRail.head),
                  halfExtents: Self.bankHalfExtents),
            .init(name: "Magnetism layers",
                  anchor: MagnetismSpaceView.bankAnchor,
                  halfExtents: Self.bankHalfExtents),
            // Circuits' and Orbital Mechanics' one standing layer instrument is a
            // `SummonHandle` tab, measured on the tab's own tight box.
            .init(name: "Circuits views tab",
                  anchor: CircuitsSpaceView.bankAnchor,
                  halfExtents: Self.summonTabHalfExtents),
            .init(name: "Orbital Mechanics show tab",
                  anchor: OrbitalMechanicsSpaceView.bankAnchor,
                  halfExtents: Self.summonTabHalfExtents),
            .init(name: "Pendulums layers",
                  anchor: PendulumsSpaceView.bankAnchor,
                  halfExtents: Self.bankHalfExtents),
            .init(name: "Projectiles layers",
                  anchor: KinematicsSpaceView.bankAnchor,
                  halfExtents: Self.bankHalfExtents),
        ]
    }

    /// Orbital Mechanics' fore column, measured as a flank for the reason
    /// Projectiles is measured as a wall.
    private var verbBanks: [Instrument] {
        [
            .init(name: "Orbital Mechanics verbs",
                  anchor: OrbitalMechanicsSpaceView.verbAnchor,
                  halfExtents: Self.verbHalfExtents),
            .init(name: "Orbital Mechanics clock tab",
                  anchor: OrbitalMechanicsSpaceView.clockAnchor,
                  halfExtents: Self.summonTabHalfExtents),
            // The fan the tab unfolds: a folded instrument that would be
            // unreachable when opened is still unreachable.
            .init(name: "Orbital Mechanics clock fan",
                  anchor: OrbitalMechanicsSpaceView.clockAnchor + SIMD3(0, 0.13, 0),
                  halfExtents: SIMD3(0.15, 0.10, 0.15)),
            // The deep flank's other objects: the Show column (only while open),
            // the world well under the tab, and the G rail at the fore column's foot.
            .init(name: "Orbital Mechanics show column",
                  anchor: OrbitalMechanicsSpaceView.showColumnAnchor,
                  halfExtents: Self.fivePlateHalfExtents),
            .init(name: "Orbital Mechanics world well",
                  anchor: OrbitalMechanicsRenderer.systemPosition
                      + OrbitalMechanicsSpaceView.wellOffset,
                  halfExtents: Self.wellHalfExtents),
            .init(name: "Orbital Mechanics G rail",
                  anchor: OrbitalMechanicsSpaceView.gravityRailAnchor,
                  halfExtents: Self.railHalfExtents),
            // And Circuits' column, for the same reason.
            .init(name: "Circuits views column",
                  anchor: CircuitsSpaceView.viewsColumnAnchor,
                  halfExtents: Self.fivePlateHalfExtents),
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

    /// Projectiles' whole instrument wall: a bank is not a module's only
    /// control, and checking only banks is how this module passed while
    /// every one of its five instruments was out of reach.
    private var projectilesWall: [Instrument] {
        [
            .init(name: "Projectiles layers",
                  anchor: KinematicsSpaceView.bankAnchor,
                  halfExtents: Self.bankHalfExtents),
            .init(name: "Projectiles ball well",
                  anchor: KinematicsSpaceView.wellAnchor,
                  halfExtents: SIMD3(0.10, 0.10, 0.10)),
            // The hoop's mouth, outboard of the ball's on the same row.
            .init(name: "Projectiles hoop well",
                  anchor: KinematicsSpaceView.hoopWellAnchor,
                  halfExtents: SIMD3(0.10, 0.10, 0.10)),
            .init(name: "Projectiles worlds picker",
                  anchor: KinematicsSpaceView.worldsAnchor,
                  halfExtents: SIMD3(0.15, 0.10, 0.15)),
            .init(name: "Projectiles g rail",
                  anchor: KinematicsSpaceView.gravityCenter,
                  halfExtents: SIMD3(0.16, 0.05, 0.07)),
            .init(name: "Projectiles wind rail",
                  anchor: KinematicsSpaceView.windCenter,
                  halfExtents: SIMD3(0.16, 0.05, 0.07)),
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

    /// Moving something into reach can move it into something else: the
    /// verb bank's flank is shared with the clock's tab.
    func testOrbitalMechanicsForeColumnInstrumentsDoNotCrowd() {
        let verbs = Instrument(name: "Orbital Mechanics verbs",
                               anchor: OrbitalMechanicsSpaceView.verbAnchor,
                               halfExtents: Self.verbHalfExtents)
        let clock = Instrument(name: "Orbital Mechanics clock tab",
                               anchor: OrbitalMechanicsSpaceView.clockAnchor,
                               halfExtents: Self.summonTabHalfExtents)

        // Only the gap between them: asserting neither stands inside the
        // orrery needs a declared station box, and Orbital Mechanics' extent is
        // whatever preset is loaded.
        let gap = verbs.box.separation(from: clock.box)
        XCTAssertGreaterThan(gap, InstrumentClearance.separation, """
            the verb bank clears the clock tab by \(String(format: "%.3f", gap)) m, \
            which is not MORE than the \(InstrumentClearance.separation) m minimum.

            Exactly at the limit is not clearance, it is a coincidence — the \
            first draft of this move landed on 0.030 and read as fine.
            """)
        // And the G rail at the column's foot clears the
        // verbs above it — their labels, not just their plates.
        let rail = Instrument(name: "Orbital Mechanics G rail",
                              anchor: OrbitalMechanicsSpaceView.gravityRailAnchor,
                              halfExtents: Self.railHalfExtents)
        XCTAssertGreaterThan(rail.box.separation(from: verbs.box),
                             InstrumentClearance.separation,
                             "the G rail stands on the verb plates' labels")
    }

    /// The deep flank must not stand on itself: the tab, its column and
    /// the well that hangs under the tab.
    func testOrbitalMechanicsDeepFlankDoesNotStackOnItself() {
        let tab = Instrument(name: "Orbital Mechanics show tab",
                             anchor: OrbitalMechanicsSpaceView.bankAnchor,
                             halfExtents: Self.summonTabHalfExtents)
        let column = Instrument(name: "Orbital Mechanics show column",
                                anchor: OrbitalMechanicsSpaceView.showColumnAnchor,
                                halfExtents: Self.fivePlateHalfExtents)
        let well = Instrument(name: "Orbital Mechanics world well",
                              anchor: OrbitalMechanicsRenderer.systemPosition
                                  + OrbitalMechanicsSpaceView.wellOffset,
                              halfExtents: Self.wellHalfExtents)
        for (a, b) in [(tab, column), (tab, well), (column, well)] {
            let gap = a.box.separation(from: b.box)
            XCTAssertGreaterThan(gap, InstrumentClearance.separation, """
                \(a.name) and \(b.name) are \(String(format: "%.3f", gap)) m \
                apart, not MORE than the \(InstrumentClearance.separation) m \
                minimum — one stands on the other.
                """)
        }
        // And the column, which opens upward, stays under a raised arm.
        XCTAssertLessThan(column.box.maximum.y,
                          InstrumentClearance.workingHeight.upperBound,
                          "the unfolded Show column climbs out of the working band")
    }

    /// Not vacuous: the list has to actually cover the app.
    func testTheCriterionCoversEveryModule() {
        XCTAssertEqual(banks.count, ModuleCatalog.allIDs.count, """
            \(banks.count) banks measured against \(ModuleCatalog.allIDs.count) \
            modules. A module was added without its bank being measured, which \
            is how the first two came to be out of reach.
            """)
    }
}

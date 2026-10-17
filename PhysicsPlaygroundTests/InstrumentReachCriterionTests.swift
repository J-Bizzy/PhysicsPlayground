//
//  InstrumentReachCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  Can you actually touch what stands in the room? Since 2026-10-14 every
//  lab's layers, rails and verbs are in More, and what stands on a lab's
//  flank is its wells — each anchor a named static so it can be measured.
//  Reach is measured to the nearest point of a declared box, deliberately
//  larger than the mouth because a nameplate hangs under it — the generous
//  convention, so anything still called unreachable is unreachable under
//  the most forgiving measurement.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class InstrumentReachCriterionTests: XCTestCase {

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

    /// One well mouth — the preview and the nameplate under it.
    private static let wellHalfExtents = SIMD3<Double>(0.06, 0.06, 0.06)

    /// What stands in each lab for a hand, by module id, read from the
    /// module's own constants so this cannot drift from what ships.
    /// Circuit Workshop's shelf is measured by
    /// `CircuitsInstrumentClearanceTests`, which knows its scroll window.
    private var standing: [(module: String, instrument: Instrument)] {
        [
            ("electrostatics",
             .init(name: "Electric Fields wells",
                   anchor: SIMD3<Float>(FieldInstrumentLayout.foreRail.head),
                   halfExtents: FieldInstrumentLayout.wellHalfExtents)),
            ("magnetism",
             .init(name: "Magnetism magnet well",
                   anchor: MagnetismSpaceView.wellAnchor,
                   halfExtents: Self.wellHalfExtents)),
            ("magnetism",
             .init(name: "Magnetism coil well",
                   anchor: MagnetismSpaceView.coilWellAnchor,
                   halfExtents: Self.wellHalfExtents)),
            ("pendulums",
             .init(name: "Pendulums pendulum well",
                   anchor: PendulumsSpaceView.wellAnchor,
                   halfExtents: Self.wellHalfExtents)),
            ("pendulums",
             .init(name: "Pendulums double well",
                   anchor: PendulumsSpaceView.doubleWellAnchor,
                   halfExtents: Self.wellHalfExtents)),
            ("gravitylab",
             .init(name: "Orbital Mechanics world well",
                   anchor: OrbitalMechanicsRenderer.systemPosition
                       + OrbitalMechanicsSpaceView.wellOffset,
                   halfExtents: Self.wellHalfExtents)),
        ] + projectilesWall.map { ("kinematics", $0) }
            + OpticsSpaceView.wellAnchors.enumerated().map { index, anchor in
                ("optics", Instrument(name: "Light & Optics well \(index + 1)",
                                      anchor: anchor, halfExtents: Self.wellHalfExtents))
            }
    }

    /// Nothing is exempt. The list stays so the shape of the test still
    /// says exemptions are possible and must be argued.
    private static let knownUnreachable: [String] = []

    func testEverythingStandingInTheRoomIsWithinReach() {
        for (_, instrument) in standing
        where !Self.knownUnreachable.contains(instrument.name) {
            XCTAssertLessThanOrEqual(
                instrument.reach, InstrumentClearance.maximumReach, """
                \(instrument.name) is \(String(format: "%.3f", instrument.reach)) m \
                from a standing viewer — past the \(InstrumentClearance.maximumReach) m \
                limit. That is a step, not a reach.

                A control you can see and cannot touch is worse than one that \
                is not there: the user does not know whether they missed or the \
                app did.
                """)
        }
    }

    /// What stands on Projectiles' wall: its two wells (its world, air,
    /// walls and wind moved into More). A bank is not a module's only
    /// control, and checking only banks is how this module once passed
    /// while every one of its instruments was out of reach.
    private var projectilesWall: [Instrument] {
        [
            .init(name: "Projectiles ball well",
                  anchor: KinematicsSpaceView.wellAnchor,
                  halfExtents: SIMD3(0.10, 0.10, 0.10)),
            // The hoop's mouth, up on the row above the ball's.
            .init(name: "Projectiles hoop well",
                  anchor: KinematicsSpaceView.hoopWellAnchor,
                  halfExtents: SIMD3(0.10, 0.10, 0.10)),
        ]
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

    /// The ball you throw waits where a hand picks up a ball to throw it:
    /// below the shoulder and nearer than the hoop's row, not up at head
    /// height where you reach for a part (2026-10-17).
    func testTheBallWaitsAtChestHeight() {
        let ball = KinematicsSpaceView.wellAnchor
        XCTAssertGreaterThan(ball.y, 0.95)
        XCTAssertLessThan(ball.y, 1.35, "the ball waits above the shoulder")
        let viewer = SIMD3<Float>(InstrumentClearance.viewer)
        XCTAssertLessThan(simd_distance(ball, viewer),
                          simd_distance(KinematicsSpaceView.hoopWellAnchor, viewer))
    }

    /// Not vacuous: the list has to actually cover the app. Every lab
    /// but Circuit Workshop, whose shelf has its own test, has something
    /// measured here.
    func testTheCriterionCoversEveryModule() {
        let measured = Set(standing.map(\.module)).union(["circuits"])
        XCTAssertEqual(measured, Set(ModuleCatalog.allIDs), """
            A module stands something in the room that nothing measures, \
            which is how the first two came to be out of reach.
            """)
    }
}

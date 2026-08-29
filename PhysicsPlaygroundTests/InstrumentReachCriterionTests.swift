//
//  InstrumentReachCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  CAN YOU ACTUALLY TOUCH THE CONTROLS?
//
//  `InstrumentClearance` has said since 2026-08-08 that furniture past
//  `maximumReach` is "a step, not a reach", and until 2026-08-09 it was
//  pointed at exactly one module. Electric Fields had a layout file, a
//  declared station and tests; the other five put their bank anchor in a
//  `SIMD3` literal inside a render closure, where nothing could measure
//  it. Two of them were out of reach and had been for as long as they
//  had existed.
//
//  ── WHY THE BOX MATTERS MORE THAN THE ANCHOR ──
//
//  Reach is measured to the NEAREST point of an instrument's box, so the
//  answer depends on how big you say the box is — and it is easy to
//  produce whichever answer you were hoping for. This file uses the
//  convention `FieldInstrumentLayout` already ships and states: a
//  DECLARED box, deliberately larger than the plates themselves, because
//  a bank is not just its plates — nameplates hang beside and below
//  them, and a confirming plate's label grows when it arms.
//
//  That convention is the GENEROUS one: a bigger box has a nearer near
//  face, so it makes reach easier to pass, not harder. Anything this
//  test still calls unreachable is unreachable under the most forgiving
//  measurement the project uses. (Measured with the tight plate
//  geometry instead, Pendulums also fails — at 1.39 m. It passes here at
//  1.21 m, and the honest thing is to say the answer depends on where
//  its nameplates actually end, which is a photograph's question.)
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
            .init(name: "Circuits layers",
                  anchor: CircuitsSpaceView.bankAnchor,
                  halfExtents: Self.bankHalfExtents),
            .init(name: "Gravity Lab layers",
                  anchor: GravityLabSpaceView.bankAnchor,
                  halfExtents: Self.bankHalfExtents),
            .init(name: "Pendulums layers",
                  anchor: PendulumsSpaceView.bankAnchor,
                  halfExtents: Self.bankHalfExtents),
            .init(name: "Projectiles layers",
                  anchor: KinematicsSpaceView.bankAnchor,
                  halfExtents: Self.bankHalfExtents),
        ]
    }

    /// Gravity Lab's fore column (on the left since 2026-08-29; it was
    /// the right flank, which had TWO instruments out of reach) —
    /// measured as a flank for the reason Projectiles is measured as a
    /// wall.
    private var verbBanks: [Instrument] {
        [
            .init(name: "Gravity Lab verbs",
                  anchor: GravityLabSpaceView.verbAnchor,
                  halfExtents: Self.verbHalfExtents),
            .init(name: "Gravity Lab clock tab",
                  anchor: GravityLabSpaceView.clockAnchor,
                  halfExtents: Self.summonTabHalfExtents),
            // The fan the tab unfolds. A folded instrument that would be
            // unreachable when opened is still unreachable; it just
            // waits for a pinch — the same argument
            // `CircuitsInstrumentClearanceTests` makes for listing the
            // presets column that only exists while its tab is open.
            .init(name: "Gravity Lab clock fan",
                  anchor: GravityLabSpaceView.clockAnchor + SIMD3(0, 0.13, 0),
                  halfExtents: SIMD3(0.15, 0.10, 0.15)),
        ]
    }

    /// A `SummonHandle` tab is one `PlateStyle` plate with a nameplate
    /// under it.
    private static let summonTabHalfExtents = SIMD3<Double>(
        Double(PlateStyle.width) / 2,
        Double(PlateStyle.height) / 2 + 0.010,
        Double(PlateStyle.depth) / 2)

    /// Projectiles' whole instrument wall, measured as a wall.
    ///
    /// A BANK IS NOT A MODULE'S ONLY CONTROL, and checking only banks is
    /// how this module passed while every one of its five instruments
    /// was out of reach. The wall was rebuilt on 2026-08-09 — see
    /// `KinematicsSpaceView` — and these are here so that "the bank is
    /// reachable" can never again be mistaken for "the module is".
    private var projectilesWall: [Instrument] {
        [
            .init(name: "Projectiles layers",
                  anchor: KinematicsSpaceView.bankAnchor,
                  halfExtents: Self.bankHalfExtents),
            .init(name: "Projectiles ball well",
                  anchor: KinematicsSpaceView.wellAnchor,
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

    /// Bringing something closer can push it off the side of the frame.
    ///
    /// Reach and off-axis angle pull in opposite directions: at a fixed
    /// x, every metre of depth you give up to get inside arm's reach
    /// buys degrees of azimuth. The first version of the Projectiles fix
    /// pulled the wall to z = −0.78, fixed all five reaches, and moved
    /// it from 43.7° to 49.1° — past the 48° that
    /// `CircuitsPartsLayout` records as the point where nameplates
    /// start being clipped, and visible in a screenshot as the rails
    /// running off the left of the frame.
    ///
    /// A test that had only measured reach would have called that a
    /// success. This is the other half.
    func testTheWallStaysInsideTheOffAxisLimit() {
        let limit = 48.0
        for instrument in projectilesWall {
            let anchor = SIMD3<Double>(instrument.anchor)
            // FORWARD IS −Z, so the bearing is measured against −z and
            // not against z. Written the other way round first, which
            // reported every instrument at 136° — the third-quadrant
            // answer to a question nobody asked, and the same shape of
            // mistake `InstrumentClearance.violations` records making
            // with nearest-vs-farthest.
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

    /// The wall must stay out of the shot.
    ///
    /// The reach fix moved five instruments toward the user, and the
    /// launcher opens at x = −0.6 firing down −z. "Closer to the user"
    /// and "into the firing line" are the same direction for four of
    /// the five, so the constraint that shapes this module has to be
    /// asserted next to the one that just moved everything.
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

    /// Moving something into reach can move it into something else.
    ///
    /// Gravity Lab's verb bank came in from 1.36 m on 2026-08-09, and
    /// the only axis available to it was depth — its flank is shared
    /// with the clock's folding tab, and at the system's own depth the
    /// reach limit and the clock want the same air. So the fix is only
    /// a fix if the gap survives it, and "I checked the arithmetic" is
    /// how the 2 cm of slack in Electric Fields got spent twice.
    func testGravityLabsForeColumnInstrumentsDoNotCrowd() {
        let verbs = Instrument(name: "Gravity Lab verbs",
                               anchor: GravityLabSpaceView.verbAnchor,
                               halfExtents: Self.verbHalfExtents)
        let clock = Instrument(name: "Gravity Lab clock tab",
                               anchor: GravityLabSpaceView.clockAnchor,
                               halfExtents: Self.summonTabHalfExtents)

        // ONLY THE GAP BETWEEN THEM. The obvious thing to also assert
        // here — that neither stands inside the orrery — needs a
        // DECLARED station box, and Gravity Lab does not have one: the
        // module's extent is whatever preset is loaded, out to Neptune.
        // Inventing a half-metre box for the test produced a violation
        // against a number this file made up, which is a criterion
        // measuring its own guess. That box belongs in the module, as a
        // decision, not here.
        let gap = verbs.box.separation(from: clock.box)
        XCTAssertGreaterThan(gap, InstrumentClearance.separation, """
            the verb bank clears the clock tab by \(String(format: "%.3f", gap)) m, \
            which is not MORE than the \(InstrumentClearance.separation) m minimum.

            Exactly at the limit is not clearance, it is a coincidence — the \
            first draft of this move landed on 0.030 and read as fine.
            """)
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

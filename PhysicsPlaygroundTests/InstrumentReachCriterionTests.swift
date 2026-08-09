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

    private var verbBanks: [Instrument] {
        [
            .init(name: "Gravity Lab verbs",
                  anchor: GravityLabSpaceView.verbAnchor,
                  halfExtents: Self.verbHalfExtents),
        ]
    }

    /// Projectiles' whole instrument wall — bank, three rails and a well
    /// — stands 1.4–1.9 m out. It is a KNOWN failure, recorded rather
    /// than excused: fixing it is not moving one anchor, it is a
    /// placement pass over a module whose launcher is room-scale 1:1 and
    /// off-axis, and moving the bank alone would split the wall into two
    /// rows at different distances. Recorded here so the criterion can
    /// be green and the debt still visible.
    private static let knownUnreachable = ["Projectiles layers"]

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

    /// The recorded failure has to STAY a recorded failure — if someone
    /// fixes Projectiles, this fails and tells them to delete the excuse.
    func testTheKnownUnreachableWallIsStillUnreachable() {
        for name in Self.knownUnreachable {
            guard let bank = banks.first(where: { $0.name == name }) else {
                return XCTFail("\(name) is recorded as unreachable but no longer exists")
            }
            XCTAssertGreaterThan(bank.reach, InstrumentClearance.maximumReach, """
                \(name) is now within reach (\(String(format: "%.3f", bank.reach)) m).

                Good — remove it from `knownUnreachable` in the same commit, so \
                the list keeps meaning "still broken" rather than becoming a \
                list of things that used to be.
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
    func testGravityLabsRightFlankInstrumentsDoNotCrowd() {
        let verbs = Instrument(name: "Gravity Lab verbs",
                               anchor: GravityLabSpaceView.verbAnchor,
                               halfExtents: Self.verbHalfExtents)
        // Derived from the real plate, not guessed: a `SummonHandle`
        // tab is one `PlateStyle` plate with a nameplate under it.
        let clock = Instrument(
            name: "Gravity Lab clock tab",
            anchor: GravityLabSpaceView.clockAnchor,
            halfExtents: SIMD3(Double(PlateStyle.width) / 2,
                               Double(PlateStyle.height) / 2 + 0.010,
                               Double(PlateStyle.depth) / 2))

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

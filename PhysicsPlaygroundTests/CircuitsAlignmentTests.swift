//
//  CircuitsAlignmentTests.swift
//  PhysicsPlaygroundTests
//
//  Snap-align: a part released with a lead near another part's lead
//  moves AND turns so the two leads become one point. Parts chain nose
//  to tail, the way components clipped together do, and a bench built
//  by dropping things near each other reads as a circuit rather than a
//  pile.
//
//  The promise is geometric and exact, so the assertions are exact:
//  the landing lead ends up on its target to 1e-12, not "close". A
//  snap that leaves a visible gap is worse than no snap, because it
//  claims a connection the eye cannot confirm.
//
//  Two rules do most of the work and each has its own test:
//
//  THE RELEASED PART MOVES; THE TARGET NEVER DOES. That is also the
//  cascade guard — a part nobody touched is never displaced, so an
//  alignment cannot propagate past one hop.
//
//  THE CLAMP VETOES. If the bench wall would move the part after the
//  alignment placed it, there is no alignment: a clamped snap leaves
//  the leads visibly apart while claiming they met, and it does that
//  right where a beginner works.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsAlignmentTests: XCTestCase {

    private func lead(_ model: CircuitsModel, _ id: UUID, _ end: Int) -> SIMD3<Double> {
        model.components.first { $0.id == id }!.terminalPosition(end)
    }

    /// Drops `kind` so its `end` lead sits `gap` from `from`'s `end`,
    /// displaced by `offset` so the alignment has a rotation to do.
    private func drop(_ model: CircuitsModel, _ kind: CircuitsModel.ComponentKind,
                      near anchor: SIMD3<Double>, gap: Double,
                      offset: SIMD3<Double> = .zero) -> UUID {
        let centre = anchor + SIMD3(gap + CircuitsModel.terminalOffset, 0, 0) + offset
        return model.add(kind, at: centre)!
    }

    // MARK: The promise

    /// The landing lead ends up EXACTLY on its target.
    func testTheAligningLeadLandsExactlyOnItsTarget() {
        let model = CircuitsModel()
        model.clearBench()
        let battery = model.add(.battery, at: CircuitsModel.buildCenter)!
        let target = lead(model, battery, 1)
        let bulb = drop(model, .bulb, near: target, gap: 0.03, offset: SIMD3(0, 0.04, 0))

        model.release(id: bulb)
        XCTAssertEqual(simd_distance(lead(model, bulb, 0), target), 0, accuracy: 1e-12,
                       "The leads must be one point, not nearly one point.")
    }

    /// And it wires them while it is there.
    func testAligningAlsoWires() {
        let model = CircuitsModel()
        model.clearBench()
        let battery = model.add(.battery, at: CircuitsModel.buildCenter)!
        let bulb = drop(model, .bulb, near: lead(model, battery, 1), gap: 0.03)
        model.release(id: bulb)
        XCTAssertEqual(model.wires.count, 1)
        XCTAssertTrue(model.areConnected(.init(componentID: battery, end: 1),
                                         .init(componentID: bulb, end: 0)))
    }

    /// The thing in your hand is the thing that moved.
    func testTheReleasedPartMovesAndTheTargetDoesNot() {
        let model = CircuitsModel()
        model.clearBench()
        let battery = model.add(.battery, at: CircuitsModel.buildCenter)!
        let batteryBefore = model.components.first { $0.id == battery }!
        let bulb = drop(model, .bulb, near: lead(model, battery, 1), gap: 0.03,
                        offset: SIMD3(0, 0.04, 0))
        let bulbBefore = model.components.first { $0.id == bulb }!.position

        model.release(id: bulb)
        let batteryAfter = model.components.first { $0.id == battery }!
        XCTAssertEqual(simd_distance(batteryAfter.position, batteryBefore.position), 0,
                       accuracy: 1e-12, "The target part moved.")
        XCTAssertEqual(simd_distance(batteryAfter.axis, batteryBefore.axis), 0,
                       accuracy: 1e-12, "The target part turned.")
        XCTAssertGreaterThan(
            simd_distance(model.components.first { $0.id == bulb }!.position, bulbBefore),
            1e-6, "The released part did not move.")
    }

    /// It rotates about the JOINT, so the far end swings and the
    /// landing lead stays put. Rotating about the centre would swing
    /// the joint through the part it is joining.
    func testTheFarEndSwingsAndTheJointStaysPut() {
        let model = CircuitsModel()
        model.clearBench()
        let battery = model.add(.battery, at: CircuitsModel.buildCenter)!
        let target = lead(model, battery, 1)
        let bulb = drop(model, .bulb, near: target, gap: 0.03, offset: SIMD3(0, 0.05, 0))
        let farBefore = lead(model, bulb, 1)

        model.release(id: bulb)
        XCTAssertEqual(simd_distance(lead(model, bulb, 0), target), 0, accuracy: 1e-12)
        XCTAssertGreaterThan(simd_distance(lead(model, bulb, 1), farBefore), 1e-6,
                             "The free end should have swung.")
        // The part keeps its length: nothing stretches any more.
        XCTAssertEqual(simd_distance(lead(model, bulb, 0), lead(model, bulb, 1)),
                       2 * CircuitsModel.terminalOffset, accuracy: 1e-12)
    }

    /// The aimed part points AWAY from the joint — its far lead is
    /// further from the target than its near one, which is what makes
    /// a chain a chain rather than a part folded back on itself.
    func testTheAlignedPartPointsAwayFromTheJoint() {
        let model = CircuitsModel()
        model.clearBench()
        let battery = model.add(.battery, at: CircuitsModel.buildCenter)!
        let target = lead(model, battery, 1)
        let bulb = drop(model, .bulb, near: target, gap: 0.03, offset: SIMD3(0, 0.05, 0))
        model.release(id: bulb)
        XCTAssertGreaterThan(simd_distance(lead(model, bulb, 1), target),
                             simd_distance(lead(model, bulb, 0), target))
    }

    // MARK: The choices

    /// With a candidate on each end, the CLOSER one becomes the
    /// anchor. Satisfying both would need the targets exactly a part's
    /// length apart, and forcing it would stretch a part that no
    /// longer stretches.
    func testTheCloserOfTwoCandidatesWins() {
        let model = CircuitsModel()
        model.clearBench()
        let left = model.add(.battery, at: CircuitsModel.buildCenter)!
        let leftLead = lead(model, left, 1)
        // A middle part whose end 0 is 1 cm from left's end 1, and
        // whose end 1 is 5 cm from a right part's end 0.
        let middle = drop(model, .resistor, near: leftLead, gap: 0.01)
        let middleFar = lead(model, middle, 1)
        model.add(.bulb, at: middleFar + SIMD3(0.05 + CircuitsModel.terminalOffset, 0, 0))

        model.release(id: middle)
        XCTAssertEqual(simd_distance(lead(model, middle, 0), leftLead), 0, accuracy: 1e-12,
                       "The 1 cm candidate should have won the geometry.")
    }

    /// The end that did NOT win still gets its wire — the alignment
    /// picks one joint, the wiring takes every pair it can.
    func testBothEndsGetWiredButOnlyOneAligns() {
        let model = CircuitsModel()
        model.clearBench()
        let left = model.add(.battery, at: CircuitsModel.buildCenter)!
        let leftLead = lead(model, left, 1)
        let middle = drop(model, .resistor, near: leftLead, gap: 0.01)
        let right = model.add(.bulb, at: lead(model, middle, 1)
                                + SIMD3(0.03 + CircuitsModel.terminalOffset, 0, 0))!

        model.release(id: middle)
        XCTAssertEqual(model.wires.count, 2, "Both pairs should be wired.")
        XCTAssertTrue(model.areConnected(.init(componentID: middle, end: 0),
                                         .init(componentID: left, end: 1)))
        XCTAssertTrue(model.areConnected(.init(componentID: middle, end: 1),
                                         .init(componentID: right, end: 0)))
    }

    /// A part already on the target's net is not an alignment target:
    /// nothing would be gained and the wire would be refused anyway.
    func testASameNetCandidateIsNotAnAlignmentTarget() {
        let model = CircuitsModel()
        model.clearBench()
        let battery = model.add(.battery, at: CircuitsModel.buildCenter)!
        let bulb = drop(model, .bulb, near: lead(model, battery, 1), gap: 0.03)
        model.release(id: bulb)
        let settled = model.components.first { $0.id == bulb }!.position

        // Release again: they are one net now, so nothing should move.
        model.release(id: bulb)
        XCTAssertNil(model.alignment(for: bulb))
        XCTAssertEqual(simd_distance(model.components.first { $0.id == bulb }!.position,
                                     settled), 0, accuracy: 1e-12)
        XCTAssertEqual(model.wires.count, 1)
    }

    /// Nothing near, nothing happens — a release in open space leaves
    /// the part exactly where the hand left it.
    func testAReleaseWithNothingNearbyChangesNothing() {
        let model = CircuitsModel()
        model.clearBench()
        model.add(.battery, at: CircuitsModel.buildCenter)
        let far = model.add(.bulb, at: CircuitsModel.buildCenter + SIMD3(0.5, 0, 0))!
        let before = model.components.first { $0.id == far }!

        model.release(id: far)
        let after = model.components.first { $0.id == far }!
        XCTAssertEqual(simd_distance(after.position, before.position), 0, accuracy: 1e-12)
        XCTAssertEqual(simd_distance(after.axis, before.axis), 0, accuracy: 1e-12)
        XCTAssertTrue(model.wires.isEmpty)
    }

    /// Just outside `leadReach` is outside — the threshold is one
    /// number now, and this is it.
    func testTheReachIsTheOnlyThreshold() {
        let model = CircuitsModel()
        model.clearBench()
        let battery = model.add(.battery, at: CircuitsModel.buildCenter)!
        let inside = drop(model, .bulb, near: lead(model, battery, 1),
                          gap: CircuitsModel.leadReach * 0.9)
        model.release(id: inside)
        XCTAssertEqual(model.wires.count, 1, "Inside the reach must join.")

        model.clearBench()
        let battery2 = model.add(.battery, at: CircuitsModel.buildCenter)!
        let outside = drop(model, .bulb, near: lead(model, battery2, 1),
                           gap: CircuitsModel.leadReach * 1.1)
        model.release(id: outside)
        XCTAssertTrue(model.wires.isEmpty, "Outside the reach must not join.")
    }

    // MARK: The vetoes

    /// THE CLAMP VETO, swept.
    ///
    /// A snap the bench wall would then undo does not happen: a
    /// clamped alignment leaves the leads visibly apart while claiming
    /// they met, and it does that right where a beginner works, up
    /// against the edge of the volume.
    ///
    /// This is a deterministic sweep rather than one hand-built case,
    /// for a reason worth recording. The first version of this test
    /// was a hand-built battery against the +x wall, and it FAILED —
    /// not because the veto was broken but because `add` clamps, so
    /// the scenario it thought it was building could not exist. The
    /// algebra that followed "proved" the veto unreachable, and the
    /// proof was wrong too: it only held for parts aimed along the
    /// same line. Sweeping arbitrary aims reaches the veto in about a
    /// quarter of all wall-adjacent releases.
    ///
    /// So the test asserts BOTH halves: that the veto fires (it is not
    /// dead code) and that nothing it lets through lands outside (it
    /// is sufficient). Either one alone would have passed on a version
    /// of this code that was wrong.
    func testTheClampVetoFiresAndNothingEscapesTheBench() {
        var vetoes = 0, alignments = 0
        // A fixed seed: this is a sweep, not a random test. It runs
        // the same 4000 placements every time.
        var seed: UInt64 = 12345
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        func aim() -> SIMD3<Double> {
            SIMD3(random() * 2 - 1, random() * 2 - 1, random() * 2 - 1)
        }
        let model = CircuitsModel()
        let half = CircuitsModel.buildHalfExtents
        for _ in 0..<4000 {
            model.clearBench()
            // Deliberately biased OUTSIDE the volume, so `add`'s clamp
            // parks most of these hard against a wall — which is the
            // only place the veto can matter.
            let spot = CircuitsModel.buildCenter
                + SIMD3((random() * 2 - 1) * half.x * 1.4,
                        (random() * 2 - 1) * half.y * 1.4,
                        (random() * 2 - 1) * half.z * 1.4)
            guard let anchor = model.add(.battery, at: spot) else { continue }
            model.setAxis(id: anchor, axis: aim())
            let anchorLead = lead(model, anchor, Int(random() * 2) % 2)
            let jitter = simd_normalize(SIMD3(random() * 2 - 1,
                                              random() * 2 - 1,
                                              random() * 2 - 1))
            guard let part = model.add(
                .resistor, at: anchorLead + jitter * (random() * CircuitsModel.leadReach))
            else { continue }
            model.setAxis(id: part, axis: aim())
            guard !model.pendingJoins(for: part).isEmpty else { continue }

            if let alignment = model.alignment(for: part) {
                alignments += 1
                XCTAssertEqual(
                    simd_distance(CircuitsModel.clampToBench(alignment.position),
                                  alignment.position),
                    0, accuracy: 1e-9,
                    "An alignment escaped the bench at \(alignment.position).")
                // And it does what it claims: the lead lands on target.
                let target = model.components
                    .first { $0.id == alignment.target.componentID }!
                    .terminalPosition(alignment.target.end)
                let landed = alignment.position
                    + (alignment.end == 0 ? -1.0 : 1.0)
                    * CircuitsModel.terminalOffset * alignment.axis
                XCTAssertEqual(simd_distance(landed, target), 0, accuracy: 1e-9)
            } else {
                vetoes += 1
            }
        }
        XCTAssertGreaterThan(alignments, 100, "The sweep barely aligned anything.")
        XCTAssertGreaterThan(vetoes, 0,
                             "The clamp veto never fired in 4000 wall-adjacent releases — "
                             + "either the sweep stopped reaching the walls or the guard is dead.")
    }

    /// Every aligned part lands inside the bench. The veto is what
    /// guarantees this, and this is the assertion that would catch it
    /// being weakened to a clamp-after-the-fact.
    func testAnAlignedPartIsAlwaysInsideTheBench() {
        let model = CircuitsModel()
        model.clearBench()
        for offset in [SIMD3(0.6, 0.0, 0.0), SIMD3(-0.6, 0, 0),
                       SIMD3(0.0, 0.4, 0.0), SIMD3(0, 0, 0.3)] {
            model.clearBench()
            let anchor = model.add(.battery, at: CircuitsModel.buildCenter + offset)!
            let part = drop(model, .bulb, near: lead(model, anchor, 1), gap: 0.03)
            model.release(id: part)
            let landed = model.components.first { $0.id == part }!.position
            XCTAssertEqual(simd_distance(CircuitsModel.clampToBench(landed), landed), 0,
                           accuracy: 1e-9, "A part landed outside the bench at offset \(offset).")
        }
    }

    /// THE CASCADE GUARD. A part nobody touched is never displaced, so
    /// a snap cannot ripple down a chain.
    func testAlignmentNeverMovesAThirdPart() {
        let model = CircuitsModel()
        model.clearBench()
        let first = model.add(.battery, at: CircuitsModel.buildCenter)!
        let second = drop(model, .resistor, near: lead(model, first, 1), gap: 0.02)
        model.release(id: second)
        let positions = model.components.map { ($0.id, $0.position, $0.axis) }

        let third = drop(model, .bulb, near: lead(model, second, 1), gap: 0.02,
                         offset: SIMD3(0, 0.03, 0))
        model.release(id: third)

        for (id, position, axis) in positions {
            let now = model.components.first { $0.id == id }!
            XCTAssertEqual(simd_distance(now.position, position), 0, accuracy: 1e-12,
                           "Part \(id) moved without being touched.")
            XCTAssertEqual(simd_distance(now.axis, axis), 0, accuracy: 1e-12,
                           "Part \(id) turned without being touched.")
        }
    }

    // MARK: Chains

    /// Six parts dropped one after another form a chain whose every
    /// joint is exactly closed. This is the whole feature, end to end.
    func testSixPartsReleasedInSequenceFormAChain() {
        let model = CircuitsModel()
        model.clearBench()
        var chain = [model.add(.battery, at: CircuitsModel.buildCenter
                                - SIMD3(0.5, 0, 0))!]
        for _ in 0..<5 {
            let previous = chain.last!
            let next = drop(model, .resistor, near: lead(model, previous, 1), gap: 0.025,
                            offset: SIMD3(0, 0.02, 0))
            model.release(id: next)
            chain.append(next)
        }
        XCTAssertEqual(chain.count, 6)
        for index in 1..<chain.count {
            XCTAssertEqual(
                simd_distance(lead(model, chain[index - 1], 1), lead(model, chain[index], 0)),
                0, accuracy: 1e-12,
                "Joint \(index) is open.")
        }
        // And it is one electrical chain, not six loose parts.
        XCTAssertTrue(model.areConnected(.init(componentID: chain[0], end: 1),
                                         .init(componentID: chain[1], end: 0)))
    }

    // MARK: swing — where "aim the part" went

    /// A part hanging by ONE lead swings about that lead: the wired
    /// end stays pinned, the free end follows the hand.
    func testSwingPinsTheWiredEnd() {
        let model = CircuitsModel()
        model.clearBench()
        let battery = model.add(.battery, at: CircuitsModel.buildCenter)!
        let bulb = drop(model, .bulb, near: lead(model, battery, 1), gap: 0.02)
        model.release(id: bulb)
        let joint = lead(model, bulb, 0)

        model.swing(id: bulb, hand: joint + SIMD3(0.0, 0.3, 0.0))
        XCTAssertEqual(simd_distance(lead(model, bulb, 0), joint), 0, accuracy: 1e-12,
                       "The wired lead must stay where it is.")
        XCTAssertEqual(model.components.first { $0.id == bulb }!.axis.y, 1, accuracy: 1e-9,
                       "The part should point at the hand.")
    }

    /// A part wired at BOTH ends does not swing — the chain decides
    /// the aim. A part wired at neither has nothing to hang from.
    func testSwingIgnoresPartsWiredAtBothEndsOrNeither() {
        let model = CircuitsModel()
        model.clearBench()
        let loose = model.add(.resistor, at: CircuitsModel.buildCenter)!
        let before = model.components.first { $0.id == loose }!.axis
        model.swing(id: loose, hand: CircuitsModel.buildCenter + SIMD3(0, 0.3, 0))
        XCTAssertEqual(simd_distance(model.components.first { $0.id == loose }!.axis, before),
                       0, accuracy: 1e-12, "An unwired part must not swing.")

        // Now wire both ends and try again.
        let a = model.add(.battery, at: CircuitsModel.buildCenter - SIMD3(0.3, 0, 0))!
        let b = model.add(.bulb, at: CircuitsModel.buildCenter + SIMD3(0.3, 0, 0))!
        model.connectTerminals(.init(componentID: loose, end: 0), .init(componentID: a, end: 1))
        model.connectTerminals(.init(componentID: loose, end: 1), .init(componentID: b, end: 0))
        let both = model.components.first { $0.id == loose }!.axis
        model.swing(id: loose, hand: CircuitsModel.buildCenter + SIMD3(0, 0.3, 0))
        XCTAssertEqual(simd_distance(model.components.first { $0.id == loose }!.axis, both),
                       0, accuracy: 1e-12, "A part wired at both ends must not swing.")
    }
}

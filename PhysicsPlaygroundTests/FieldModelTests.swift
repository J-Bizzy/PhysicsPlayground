//
//  FieldModelTests.swift
//  PhysicsPlaygroundTests
//
//  Tests for the multi-charge app state: add/remove/select behavior and the
//  selected-charge bindings the control panels use. Superposition math itself
//  is covered in PhysicsCore's ElectricFieldTests.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class FieldModelTests: XCTestCase {

    /// The module opens on a dipole: the positive charge is selected,
    /// so the sliders act on the one wearing the white halo.
    func testStartsWithASelectedDipole() {
        let model = FieldModel()
        XCTAssertEqual(model.charges.count, 2)
        XCTAssertEqual(model.selectedChargeID, model.charges[0].id)
        XCTAssertTrue(model.charges[0].isPositive)
        XCTAssertFalse(model.charges[1].isPositive)
    }

    func testAddChargeAppendsSelectsAndSetsPolarity() {
        let model = FieldModel()
        let before = model.charges.count
        model.addCharge(positive: false)
        XCTAssertEqual(model.charges.count, before + 1)
        XCTAssertEqual(model.selectedChargeID, model.charges.last?.id)
        XCTAssertFalse(model.charges.last!.isPositive)
        XCTAssertEqual(model.charges.last!.charge, -FieldModel.defaultMagnitude)
    }

    func testAddedChargesDoNotStack() {
        let model = FieldModel()
        model.addCharge(positive: true)
        model.addCharge(positive: true)
        let positions = model.charges.map(\.position)
        for i in positions.indices {
            for j in positions.indices where i < j {
                XCTAssertGreaterThan(simd_distance(positions[i], positions[j]), 0.05)
            }
        }
    }

    func testRemoveSelectedReselectsAnother() {
        let model = FieldModel()
        let before = model.charges.count
        model.addCharge(positive: false)
        let removedID = model.selectedChargeID
        model.removeSelectedCharge()
        XCTAssertEqual(model.charges.count, before)
        XCTAssertNotEqual(model.selectedChargeID, removedID)
        XCTAssertTrue(model.charges.contains { $0.id == model.selectedChargeID })
    }

    func testRemoveAllClearsSelection() {
        let model = FieldModel()
        model.addCharge(positive: true)
        model.removeAllCharges()
        XCTAssertTrue(model.charges.isEmpty)
        XCTAssertNil(model.selectedChargeID)
    }

    /// THE CLEAR PLATE'S ACTUAL PROMISE: an empty room. It fired
    /// `removeAllCharges` for months and the probe — placed content
    /// with its own lifecycle — survived every clear, orbiting nothing.
    /// The plate fires `clearEverything` now, and this holds it to the
    /// name on the plate.
    func testClearEverythingRemovesTheProbeToo() {
        let model = FieldModel()
        model.addCharge(positive: true)
        model.addCharge(positive: false)
        model.dropProbe()
        XCTAssertNotNil(model.probe, "no probe to clear — test is vacuous")

        model.clearEverything()
        XCTAssertTrue(model.charges.isEmpty)
        XCTAssertNil(model.selectedChargeID)
        XCTAssertNil(model.probe, "the placed test charge must clear with "
                     + "everything else")
        XCTAssertEqual(model.probeStatus, .none)
        XCTAssertTrue(model.probeTrail.isEmpty)
    }

    func testSelectedBindingsEditOnlyTheSelectedCharge() {
        let model = FieldModel()
        let firstID = model.charges[0].id
        model.addCharge(positive: false)  // a new charge, now selected
        let editedID = model.selectedChargeID

        model.selectedMagnitudeMicroCoulombs = 3.0

        let first = model.charges.first { $0.id == firstID }!
        XCTAssertEqual(first.charge, FieldModel.defaultMagnitude, "unselected charge must be untouched")
        let edited = model.charges.first { $0.id == editedID }!
        XCTAssertEqual(edited.charge, -3.0e-6, accuracy: 1e-12,
                       "magnitude set, sign kept from birth")
    }

    /// Dragged at the floor, a charge stops at the floor clearance —
    /// the one boundary a hand still meets after the station walls came
    /// off the drag paths (2026-08-03).
    func testMoveChargeClampsAboveFloor() {
        let model = FieldModel()
        let id = model.charges[0].id
        model.moveCharge(id: id, to: SIMD3(0.2, -0.5, -1.0))
        XCTAssertEqual(model.charges[0].position.y,
                       FieldModel.floorClearance, accuracy: 1e-9)
        // Laterally the hand is obeyed exactly.
        XCTAssertEqual(model.charges[0].position.x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(model.charges[0].position.z, -1.0, accuracy: 1e-9)
    }

    func testMoveChargeMovesOnlyTheTarget() {
        let model = FieldModel()
        model.addCharge(positive: false)
        let othersBefore = model.charges.dropFirst().map(\.position)
        model.moveCharge(id: model.charges[0].id, to: SIMD3(0.1, 1.0, -0.9))
        XCTAssertEqual(model.charges[0].position, SIMD3(0.1, 1.0, -0.9))
        XCTAssertEqual(Array(model.charges.dropFirst().map(\.position)), othersBefore)
    }

    func testSelectIgnoresUnknownID() {
        let model = FieldModel()
        let before = model.selectedChargeID
        model.select(id: UUID())
        XCTAssertEqual(model.selectedChargeID, before)
    }

    // MARK: Sampling region

    /// "Far away" now means the far corner of this bench's STATION, not
    /// the far corner of the room: since Electric Fields became the
    /// middle seat of the E&M world, a charge dragged at the wall stops
    /// at its own boundary rather than drifting into the circuit bench.
    /// The property under test is unchanged — the sampling region
    /// follows the charge wherever the charge is allowed to go.
    func testRegionFollowsChargeDraggedFarAway() {
        let model = FieldModel()
        let id = model.charges[0].id
        model.moveCharge(id: id, to: SIMD3(2.0, 1.2, -2.5))
        let farAway = model.charges[0].position
        XCTAssertGreaterThan(simd_distance(farAway, FieldModel.regionCenter), 0.5,
                             "the drag should still have gone somewhere")

        let region = model.samplingRegion
        let lower = region.center - region.extents / 2
        let upper = region.center + region.extents / 2
        XCTAssertTrue(simd_min(lower, farAway) == lower && simd_max(upper, farAway) == upper,
                      "region must contain the charge wherever it goes")
        // And the sample points went with it.
        XCTAssertTrue(model.samplePoints.contains { simd_distance($0, farAway) < 0.7 })
    }

    func testRegionContainsAllChargesWithMargin() {
        let model = FieldModel()
        model.addCharge(positive: false)
        model.moveCharge(id: model.charges[1].id, to: SIMD3(1.5, 0.8, -0.4))

        let region = model.samplingRegion
        let lower = region.center - region.extents / 2
        let upper = region.center + region.extents / 2
        for charge in model.charges {
            for axis in 0..<3 {
                XCTAssertLessThanOrEqual(lower[axis], charge.position[axis])
                XCTAssertGreaterThanOrEqual(upper[axis], charge.position[axis])
            }
        }
    }

    func testRegionNeverSmallerThanDefaultCube() {
        let model = FieldModel()  // single charge → minimal region
        let region = model.samplingRegion
        for axis in 0..<3 {
            XCTAssertGreaterThanOrEqual(region.extents[axis], FieldModel.regionExtent - 1e-9)
        }
    }

    func testRegionStaysOutOfTheFloor() {
        let model = FieldModel()
        model.moveCharge(id: model.charges[0].id, to: SIMD3(0, FieldModel.floorClearance, -1))
        let region = model.samplingRegion
        XCTAssertGreaterThanOrEqual(region.center.y - region.extents.y / 2, FieldModel.regionFloor - 1e-9)
        XCTAssertFalse(model.samplePoints.contains { $0.y < FieldModel.regionFloor - 1e-9 })
    }

    // MARK: Probe lifecycle

    func testDropProbeStartsAtRestAndRunning() {
        let model = FieldModel()
        model.dropProbe()
        XCTAssertNotNil(model.probe)
        XCTAssertEqual(model.probe?.velocity, .zero)
        XCTAssertEqual(model.probeStatus, .running)
        XCTAssertNotNil(model.probeReadout)
    }

    func testRemoveProbeClearsEverything() {
        let model = FieldModel()
        model.dropProbe()
        model.removeProbe()
        XCTAssertNil(model.probe)
        XCTAssertEqual(model.probeStatus, .none)
        XCTAssertNil(model.probeReadout)
    }

    func testStepProbeMovesItAlongTheField() {
        let model = FieldModel()   // one positive charge at region center
        model.dropProbe()
        let start = model.probe!.position
        let distanceBefore = simd_distance(start, model.charges[0].position)
        for _ in 0..<60 { model.stepProbe(dt: 1.0 / 90.0) }
        let distanceAfter = simd_distance(model.probe!.position, model.charges[0].position)
        XCTAssertGreaterThan(distanceAfter, distanceBefore,
                             "positive probe must be repelled by the positive charge")
    }

    func testHeldProbeDoesNotSimulate() {
        let model = FieldModel()
        model.dropProbe()
        model.holdProbe(at: SIMD3(0.2, 1.2, -1.0))
        let held = model.probe!.position
        model.stepProbe(dt: 1.0 / 90.0)
        XCTAssertEqual(model.probe!.position, held, "held probe must not move on its own")
        model.releaseProbe()
        XCTAssertEqual(model.probeStatus, .running)
    }

    func testNegativeProbeIsAttractedToPositiveCharge() {
        let model = FieldModel()   // one positive charge at region center
        model.probeIsPositive = false
        model.probe = TestChargeDynamics.ProbeState(
            position: FieldModel.regionCenter + SIMD3(0.15, 0, 0)
        )
        model.probeStatus = .running

        for _ in 0..<3000 where model.probeStatus == .running {
            model.stepProbe(dt: 1.0 / 90.0)
        }
        XCTAssertEqual(model.probeStatus, .captured,
                       "a negative probe must fall into the positive charge")
    }

    func testProbePolarityFlipsSignedCharge() {
        let model = FieldModel()
        XCTAssertEqual(model.probeCharge, model.probeChargeMagnitude)
        model.probeIsPositive = false
        XCTAssertEqual(model.probeCharge, -model.probeChargeMagnitude)
    }

    func testProbeIsCapturedByNegativeCharge() {
        let model = FieldModel()
        model.removeAllCharges()
        model.charges = [PointCharge(position: FieldModel.regionCenter, charge: -2e-6)]
        model.probe = TestChargeDynamics.ProbeState(
            position: FieldModel.regionCenter + SIMD3(0.15, 0, 0)
        )
        model.probeStatus = .running

        for _ in 0..<3000 where model.probeStatus == .running {
            model.stepProbe(dt: 1.0 / 90.0)
        }
        XCTAssertEqual(model.probeStatus, .captured,
                       "a positive probe falling into a negative charge must be captured")
    }

    /// The shared pause orb freezes the probe mid-flight.
    func testPauseFreezesProbe() {
        let model = FieldModel()
        model.dropProbe()
        model.isPaused = true
        let frozen = try! XCTUnwrap(model.probe)
        for _ in 0..<30 {
            model.stepProbe(dt: 1.0 / 90.0)
        }
        XCTAssertEqual(model.probe, frozen, "a paused probe must not move")
        XCTAssertEqual(model.probeStatus, .running, "pause is not capture — resuming continues the flight")

        model.isPaused = false
        model.stepProbe(dt: 1.0 / 90.0)
        XCTAssertNotEqual(model.probe, frozen, "resuming picks the flight back up")
    }

    // MARK: Reset (the shell's Reset button calls this via the descriptor)

    /// The module opens as a DIPOLE, not a monopole: a single charge's
    /// field is straight rays to infinity, which reads as a starburst
    /// rather than a field. The pair must be equal and opposite and
    /// straddle the region centre, so the picture is the textbook one.
    func testResetOpensOnADipole() {
        let model = FieldModel()
        model.addCharge(positive: false)
        model.addCharge(positive: true)
        model.dropProbe()
        model.showLines = false
        model.probeIsPositive = false

        model.reset()

        XCTAssertEqual(model.charges.count, 2)
        XCTAssertEqual(model.charges.filter(\.isPositive).count, 1)
        XCTAssertEqual(model.charges.filter { !$0.isPositive }.count, 1)
        XCTAssertEqual(model.charges[0].charge, -model.charges[1].charge, accuracy: 1e-18,
                       "equal and opposite — the net charge is zero")
        let midpoint = (model.charges[0].position + model.charges[1].position) / 2
        XCTAssertEqual(simd_distance(midpoint, FieldModel.regionCenter), 0, accuracy: 1e-12,
                       "the pair straddles the home centre")
        XCTAssertGreaterThan(
            simd_distance(model.charges[0].position, model.charges[1].position), 0.1,
            "far enough apart to read as two charges")
        XCTAssertEqual(model.selectedChargeID, model.charges[0].id)
        XCTAssertNil(model.probe)
        XCTAssertEqual(model.probeStatus, .none)
        XCTAssertTrue(model.probeIsPositive)
        XCTAssertTrue(model.showLines)
    }

    /// The ΔV rail writes through a 500 V snap (2026-08-06): the
    /// displayed "%.0f kV" can never disagree with the model by
    /// sub-display noise, and reaching past the range clamps first.
    func testPlateVoltageWritesSnapTo500VoltSteps() {
        let model = FieldModel()
        model.setPlateVoltage(17_263)
        XCTAssertEqual(model.plateVoltage, 17_500, accuracy: 1e-9)
        model.setPlateVoltage(17_249)
        XCTAssertEqual(model.plateVoltage, 17_000, accuracy: 1e-9)
        model.setPlateVoltage(999_999)
        XCTAssertEqual(model.plateVoltage, 40_000, accuracy: 1e-9,
                       "clamped to the range's top, which is itself on-grid")
        model.setPlateVoltage(-5)
        XCTAssertEqual(model.plateVoltage, 2_000, accuracy: 1e-9)
    }

    /// One arithmetic for the E line everywhere it is shown — and since
    /// the plates became real (2026-08-14), that number is the MEASURED
    /// centre field: honestly below the ideal V/d, because a finite
    /// capacitor leaks field out its sides, and more so as the gap
    /// opens relative to the plates.
    func testPlateFieldReadsTheMeasuredCentreField() {
        let model = FieldModel()
        model.capacitorOn = true
        for (volts, separation) in [(2_000.0, 0.15), (20_000.0, 0.44),
                                    (40_000.0, 1.0), (13_500.0, 0.62)] {
            model.plateVoltage = volts
            model.plateSeparation = separation
            let ideal = volts / separation / 1000
            XCTAssertLessThan(model.plateFieldkVPerM, ideal,
                              "finite plates cannot reach the ideal V/d")
            XCTAssertGreaterThan(model.plateFieldkVPerM, ideal * 0.35,
                                 "\(volts) V over \(separation) m")
            // And it is the same number the capacitor itself measures,
            // to the displayed tenth.
            let measured = model.capacitorField(at: model.capacitorCenter).x
            XCTAssertEqual(model.plateFieldkVPerM,
                           ((measured / 1000) * 10).rounded() / 10,
                           accuracy: 1e-9)
        }
    }

    /// The capacitor accelerates the probe at exactly a = qV/(d·m).
    func testCapacitorDrift() {
        // Capacitor: no point charges, plates on, probe at the center.
        let model = FieldModel()
        model.removeAllCharges()
        XCTAssertTrue(model.charges.isEmpty)
        model.capacitorOn = true
        model.plateVoltage = 20_000
        model.dropProbe()
        model.holdProbe(at: model.samplingRegion.center)
        model.releaseProbe()

        // The MEASURED centre field, not V/d: the plates are real and
        // open, so the ideal formula overstates E. The probe stays on
        // the symmetry axis while it drifts, where the field varies
        // slowly — a 10% window covers the variation over 0.3 s.
        let expectedAcceleration = model.probeChargeMagnitude
            * model.capacitorField(at: model.capacitorCenter).x
            / FieldModel.probeMass
        for _ in 0..<27 {  // 0.3 s
            model.stepProbe(dt: 1.0 / 90.0)
        }
        let probe = try! XCTUnwrap(model.probe)
        XCTAssertEqual(probe.velocity.x, expectedAcceleration * 0.3,
                       accuracy: expectedAcceleration * 0.3 * 0.10,
                       "a + probe drifts toward the negative plate at qE/m")
        XCTAssertEqual(probe.velocity.y, 0, accuracy: 1e-9,
                       "on the symmetry axis the sideways field is zero")

        // Grab the negative plate and pull it outward: the gap grows,
        // the other plate stays put, and E = V/d falls.
        let fieldBefore = simd_length(model.capacitorField(at: model.capacitorCenter))
        let leftPlateX = model.plateX(0)
        model.movePlate(1, toWorld: model.capacitorCenter
                        + SIMD3(0.45, 0, 0))
        XCTAssertEqual(model.plateX(0), leftPlateX, accuracy: 1e-9,
                       "the un-grabbed plate stays put")
        XCTAssertGreaterThan(model.plateSeparation, 0.5)
        let fieldAfter = simd_length(model.capacitorField(at: model.capacitorCenter))
        XCTAssertLessThan(fieldAfter, fieldBefore, "wider gap, weaker field")

        // Double the probe's charge: the same field pushes twice as hard.
        let readoutBefore = try! XCTUnwrap(model.probeReadout)
        model.probeChargeMagnitude *= 2
        let readoutAfter = try! XCTUnwrap(model.probeReadout)
        XCTAssertEqual(readoutAfter.forceMagnitude,
                       2 * readoutBefore.forceMagnitude,
                       accuracy: readoutBefore.forceMagnitude * 1e-9,
                       "F = qE scales linearly with q")
    }

    /// With B on and nothing else, the probe launches sideways and
    /// curves at constant speed — v rotates into z while |v| holds.
    func testMagneticFieldCurvesTheProbe() {
        let model = FieldModel()
        model.removeAllCharges()
        model.magneticFieldOn = true
        model.magneticFieldTesla = 5e4
        model.dropProbe()
        let launch = FieldModel.magneticLaunchSpeed

        for _ in 0..<90 {
            model.stepProbe(dt: 1.0 / 90.0)
        }
        let probe = try! XCTUnwrap(model.probe)
        XCTAssertGreaterThan(abs(probe.velocity.z), launch * 0.2,
                             "the velocity has visibly rotated")
        XCTAssertEqual(simd_length(probe.velocity), launch,
                       accuracy: launch * 1e-9,
                       "a magnetic force never changes the speed")
        XCTAssertEqual(probe.velocity.y, 0, accuracy: 1e-12,
                       "B along y leaves vy alone")
    }

    // (Electron mode's realistic-field test left with the mode itself on
    // 2026-08-03 — the probe is always the charged ball now. Git history
    // holds the e/m coverage.)

    // MARK: What the card says about the probe

    /// THE CARD REPORTED THE ELECTRIC FORCE WHILE THE DEMO WAS MAGNETIC.
    ///
    /// `stepProbe` pushes the probe with the full Lorentz force
    /// q(E + v×B) — correctly — and `probeReadout` computed `|q||E|` and
    /// called it "Force". Switch Uniform B on with no charges in the
    /// room and the card read `Force 0.00 N` while the probe visibly
    /// circled in front of you. The one number that could have explained
    /// the orbit said nothing was happening.
    func testTheCardReportsTheMagneticForceOnACirclingProbe() throws {
        let model = FieldModel()
        model.removeAllCharges()
        model.magneticFieldOn = true
        model.magneticFieldTesla = 5e4
        model.dropProbe()
        for _ in 0..<10 { model.stepProbe(dt: 1.0 / 90.0) }

        let readout = try XCTUnwrap(model.probeReadout)

        // No charges and no plates, so there is genuinely no E.
        XCTAssertEqual(readout.electricForce, 0, accuracy: 1e-18,
                       "there is no electric field here")
        // …and the probe is nonetheless being pushed, hard enough to
        // bend it into a circle.
        XCTAssertGreaterThan(readout.magneticForce, 0,
                             "a moving charge in a magnetic field feels q v×B; "
                             + "reporting zero is why the orbit was unexplained")
        XCTAssertEqual(readout.forceMagnitude, readout.magneticForce,
                       accuracy: readout.magneticForce * 1e-9,
                       "with no E, the whole force is magnetic")

        // The acceleration the card quotes must be the one the probe is
        // actually undergoing: a = v²/r for circular motion.
        let speed = readout.speed
        let expected = speed * speed / model.cyclotronRadius
        XCTAssertEqual(readout.acceleration, expected, accuracy: expected * 0.05,
                       "the quoted acceleration is not the one bending the path")
    }

    /// A STATIONARY probe feels no magnetic force, which is the other
    /// half of the same lesson — and the reason the split is worth
    /// showing rather than folding into one number.
    func testAStationaryProbeFeelsNoMagneticForce() throws {
        let model = FieldModel()
        model.removeAllCharges()
        model.magneticFieldOn = true
        model.magneticFieldTesla = 5e4
        model.dropProbe()
        // `holdProbe` is the grab path: it parks the probe and zeroes
        // its velocity, which is exactly the state this is about.
        model.holdProbe(at: model.samplingRegion.center)

        let readout = try XCTUnwrap(model.probeReadout)
        XCTAssertEqual(readout.speed, 0, accuracy: 1e-12)
        XCTAssertEqual(readout.magneticForce, 0, accuracy: 1e-18,
                       "q v×B is zero when v is zero")
    }

    /// A LARGE FIELD BESIDE `0.00 V` IS THE ONE THING A POTENTIAL CANNOT
    /// BE. `fieldVector` includes the capacitor plates and the card's
    /// potential did not, so between the plates the card showed a strong
    /// E and no potential difference from anywhere to anywhere.
    func testThePotentialIncludesTheCapacitor() throws {
        let model = FieldModel()
        model.removeAllCharges()
        model.capacitorOn = true
        model.dropProbe()

        // Off-centre along the field axis, where a uniform field must
        // show a potential difference from the centre.
        let offset = SIMD3<Double>(model.plateSeparation / 4, 0, 0)
        model.holdProbe(at: model.capacitorCenter + offset)
        let readout = try XCTUnwrap(model.probeReadout)

        XCTAssertGreaterThan(readout.fieldMagnitude, 0,
                             "the plates should make a field here")
        XCTAssertEqual(
            readout.potential,
            model.capacitorPotential(at: model.capacitorCenter + offset),
            accuracy: 1e-9)
        XCTAssertLessThan(readout.potential, 0,
                          "downhill toward the negative plate — and not the "
                          + "0.00 V beside a strong E that started all this")
    }

    /// The slab's coverage is physics state (it rides the Time Capsule
    /// snapshot), and it is a Double — outside `ResetCoverageTests`'s
    /// Bool reflection — so its reset is held by hand, the same
    /// arrangement `CircuitsNetHighlightTests` uses for the net
    /// selection.
    func testResetParksTheDielectric() {
        let model = FieldModel()
        model.capacitorOn = true
        model.dielectricCoverage = 0.7
        model.reset()
        XCTAssertEqual(model.dielectricCoverage, 0,
                       "reset must pull the slab back out")
        XCTAssertFalse(model.capacitorOn)
    }

    /// Sliding the slab in raises the capacitance monotonically toward
    /// κ·C₀ — the classic partial-insertion demo, live on the bench.
    func testSlidingTheSlabRaisesCapacitance() throws {
        let model = FieldModel()
        model.capacitorOn = true
        let bare = try XCTUnwrap(model.capacitor).capacitance
        model.moveDielectric(toWorld: model.capacitorCenter
                             - SIMD3(0, 0, FieldModel.plateSize / 2))
        XCTAssertEqual(model.dielectricCoverage, 0.5, accuracy: 1e-9)
        let half = try XCTUnwrap(model.capacitor).capacitance
        model.moveDielectric(toWorld: model.capacitorCenter)
        XCTAssertEqual(model.dielectricCoverage, 1, accuracy: 1e-9)
        let full = try XCTUnwrap(model.capacitor).capacitance
        XCTAssertGreaterThan(half, bare)
        XCTAssertGreaterThan(full, half)
        XCTAssertEqual(full, bare * FieldModel.dielectricConstant,
                       accuracy: full * 1e-6)
    }

    /// The deflection launch: in through the +z fringe, a parabola
    /// between the plates, and the bend follows the probe's sign.
    func testTheDeflectionLaunchBendsWithTheProbeSign() throws {
        let model = FieldModel()
        model.removeAllCharges()
        model.capacitorOn = true

        model.launchProbeThroughGap()
        for _ in 0..<90 { model.stepProbe(dt: 1.0 / 90.0) }
        let positive = try XCTUnwrap(model.probe)
        XCTAssertLessThan(positive.position.z,
                          model.capacitorCenter.z + FieldModel.plateSize / 2,
                          "the probe should have entered the gap")
        XCTAssertGreaterThan(positive.velocity.x, 0.01,
                             "a + probe bends toward the − plate (+x)")

        model.probeIsPositive = false
        model.launchProbeThroughGap()
        for _ in 0..<90 { model.stepProbe(dt: 1.0 / 90.0) }
        let negative = try XCTUnwrap(model.probe)
        XCTAssertLessThan(negative.velocity.x, -0.01,
                          "a − probe bends the other way")
    }

    /// Re-firing is the point of the launch verb, and each shot is its
    /// own flight: the trail restarts at the muzzle instead of drawing
    /// a straight bridge back to wherever the last parabola ended.
    func testRefiringTheDeflectionShotStartsAFreshTrail() {
        let model = FieldModel()
        model.removeAllCharges()
        model.capacitorOn = true

        model.launchProbeThroughGap()
        for _ in 0..<60 { model.stepProbe(dt: 1.0 / 90.0) }
        XCTAssertFalse(model.probeTrail.isEmpty,
                       "the first flight should have left a trail")

        model.launchProbeThroughGap()
        XCTAssertTrue(model.probeTrail.isEmpty,
                      "the old flight must not leak into the new one")
    }
}

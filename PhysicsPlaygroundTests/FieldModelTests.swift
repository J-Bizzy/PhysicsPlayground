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

    func testMoveChargeClampsAboveFloor() {
        let model = FieldModel()
        let id = model.charges[0].id
        model.moveCharge(id: id, to: SIMD3(0.2, -0.5, -1.0))
        XCTAssertEqual(model.charges[0].position.y, FieldModel.floorClearance)
        XCTAssertEqual(model.charges[0].position.x, 0.2)
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

    func testRegionFollowsChargeDraggedFarAway() {
        let model = FieldModel()
        let id = model.charges[0].id
        let farAway = SIMD3<Double>(2.0, 1.2, -2.5)
        model.moveCharge(id: id, to: farAway)

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

        let expectedAcceleration = model.probeChargeMagnitude
            * model.plateVoltage / model.plateSeparation / FieldModel.probeMass
        for _ in 0..<27 {  // 0.3 s
            model.stepProbe(dt: 1.0 / 90.0)
        }
        let probe = try! XCTUnwrap(model.probe)
        XCTAssertEqual(probe.velocity.x, expectedAcceleration * 0.3,
                       accuracy: expectedAcceleration * 0.3 * 0.02,
                       "a + probe drifts toward the negative plate at qE/m")
        XCTAssertEqual(probe.velocity.y, 0, accuracy: 1e-9)

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

    /// Electron mode: a realistic 0.1 mT bends a real electron into an
    /// ~11 cm circle at constant speed, under display time compression.
    func testElectronModeCurvesAtRealisticField() {
        let model = FieldModel()
        model.removeAllCharges()
        model.magneticFieldOn = true
        model.electronMode = true
        model.electronFieldTesla = 1e-4
        model.dropProbe()

        // r = v/((q/m)B) ≈ 0.1137 m.
        let ratio = FieldModel.electronCharge / FieldModel.electronMass
        XCTAssertEqual(model.cyclotronRadius,
                       FieldModel.electronLaunchSpeed / (ratio * 1e-4),
                       accuracy: 1e-6)
        XCTAssertEqual(model.cyclotronRadius, 0.1137, accuracy: 0.001)

        for _ in 0..<90 {  // one wall-second ≈ 0.28 orbits
            model.stepProbe(dt: 1.0 / 90.0)
        }
        let probe = try! XCTUnwrap(model.probe)
        XCTAssertGreaterThan(abs(probe.velocity.z),
                             FieldModel.electronLaunchSpeed * 0.2,
                             "the electron's velocity has visibly rotated")
        XCTAssertEqual(simd_length(probe.velocity), FieldModel.electronLaunchSpeed,
                       accuracy: FieldModel.electronLaunchSpeed * 1e-9,
                       "B does no work on the electron either")
    }
}

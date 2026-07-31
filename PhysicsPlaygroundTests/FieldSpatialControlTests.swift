//
//  FieldSpatialControlTests.swift
//  PhysicsPlaygroundTests
//
//  Electric Fields' controls left the window panel on 2026-07-31. These
//  are the behaviours that moved with them — the ones a migration can
//  silently drop, because they were properties of the OLD control rather
//  than of the model underneath.
//
//  The probe's launch push is the type specimen: `dropProbe` shoved the
//  test charge sideways "so there's a velocity for B to bend", and that
//  one line is the entire reason the cyclotron demo works. Replace the
//  button with a well and the push disappears with it, and nothing fails —
//  the probe just sits there while the field does nothing to it. That is a
//  demonstration lost, not a control lost, and only a test notices.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class FieldSpatialControlTests: XCTestCase {

    // MARK: The throw that replaced the Drop button

    /// With B on, the probe must leave your hand MOVING, or F = qv×B is
    /// zero and the field has nothing to bend.
    func testReleasingTheProbeIntoAMagneticFieldLaunchesIt() {
        let model = FieldModel()
        model.magneticFieldOn = true
        model.holdProbe(at: FieldModel.regionCenter)

        model.releaseProbe(flick: SIMD3(0, 0, 0.8))

        let velocity = try? XCTUnwrap(model.probe?.velocity)
        XCTAssertEqual(simd_length(velocity ?? .zero), model.launchSpeed,
                       accuracy: model.launchSpeed * 1e-9,
                       "The probe must leave at the launch speed, not the hand's speed.")
        XCTAssertEqual(simd_normalize(velocity ?? SIMD3(1, 0, 0)).z, 1, accuracy: 1e-9,
                       "The throw must carry the aim.")
        XCTAssertEqual(model.probeStatus, .running)
    }

    /// Letting go gently is not a bug to be punished. Below the threshold
    /// it falls back to the sideways push `dropProbe` always used, so a
    /// careful release still produces a circle rather than a dead probe.
    func testAGentleReleaseStillGetsThePushItUsedTo() {
        let model = FieldModel()
        model.magneticFieldOn = true
        model.holdProbe(at: FieldModel.regionCenter)

        model.releaseProbe(flick: SIMD3(0.001, 0, 0))

        XCTAssertEqual(simd_length(model.probe?.velocity ?? .zero), model.launchSpeed,
                       accuracy: model.launchSpeed * 1e-9)
    }

    /// With NO magnetic field, the probe starts from rest — the pure
    /// F = qE demonstration, where a launch velocity would be a lie about
    /// what the electric field did.
    func testWithoutAMagneticFieldTheProbeStartsAtRest() {
        let model = FieldModel()
        model.magneticFieldOn = false
        model.electronMode = false
        model.holdProbe(at: FieldModel.regionCenter)

        model.releaseProbe(flick: SIMD3(0, 0, 2.0))

        XCTAssertEqual(simd_length(model.probe?.velocity ?? SIMD3(9, 9, 9)), 0,
                       accuracy: 1e-12,
                       "An electrostatic drop must start at rest, whatever the hand did.")
    }

    func testReleasingWithNoProbeDoesNothing() {
        let model = FieldModel()
        model.removeProbe()
        model.releaseProbe(flick: SIMD3(0, 0, 1))
        XCTAssertNil(model.probe)
        XCTAssertEqual(model.probeStatus, .none)
    }

    // MARK: What the wells make

    /// A charge pulled from a well is born AT THE HAND — not at the next
    /// slot on the golden-angle ring the old "Add +" button used. Creating
    /// and placing are one gesture, which is the whole reason a well beats
    /// a button.
    func testAChargeIsBornWhereTheHandIs() {
        let model = FieldModel()
        model.removeAllCharges()
        let hand = FieldModel.regionCenter + SIMD3(0.2, -0.1, 0.15)

        let id = model.addCharge(positive: true, at: hand)

        let charge = try? XCTUnwrap(model.charges.first(where: { $0.id == id }))
        XCTAssertEqual(charge?.position ?? .zero, hand,
                       "The charge did not arrive under the fingers that made it.")
        XCTAssertTrue(charge?.isPositive ?? false)
    }

    /// The probe's well has no UUID of its own to hand back, so the view
    /// uses a fixed sentinel and remaps it. It must never collide with a
    /// real charge — that would make a pulled probe move a charge instead.
    func testThePulledProbeIsHeldAtTheHand() {
        let model = FieldModel()
        let hand = FieldModel.regionCenter + SIMD3(0, 0.2, 0)

        model.holdProbe(at: hand)

        XCTAssertEqual(model.probeStatus, .held)
        XCTAssertEqual(model.probe?.position ?? .zero, hand)
        XCTAssertEqual(simd_length(model.probe?.velocity ?? SIMD3(1, 1, 1)), 0,
                       accuracy: 1e-12, "A held probe must not be moving.")
    }

    // MARK: The particle bank

    /// The four discs and the two model flags are the same fact, and the
    /// mapping must survive a round trip in both directions — otherwise a
    /// lit disc can disagree with the physics it claims to describe. The
    /// positron is the case that gets dropped: it exists only as
    /// `electronMode && probeIsPositive`, so a three-way picker deletes a
    /// particle without anyone noticing.
    func testEveryParticleRoundTrips() {
        let model = FieldModel()
        let cases: [(id: String, electron: Bool, positive: Bool)] = [
            ("plus", false, true),
            ("minus", false, false),
            ("electron", true, false),
            ("positron", true, true),
        ]
        for particle in cases {
            model.electronMode = particle.id == "electron" || particle.id == "positron"
            model.probeIsPositive = particle.id == "plus" || particle.id == "positron"

            XCTAssertEqual(model.electronMode, particle.electron, "\(particle.id)")
            XCTAssertEqual(model.probeIsPositive, particle.positive, "\(particle.id)")

            // And the physics actually differs, which is what makes this a
            // particle choice rather than a label.
            XCTAssertEqual(model.probeQ > 0, particle.positive,
                           "\(particle.id) has the wrong sign of charge.")
            if particle.electron {
                XCTAssertEqual(abs(model.probeQ), FieldModel.electronCharge,
                               accuracy: FieldModel.electronCharge * 1e-9,
                               "\(particle.id) is not carrying e.")
                XCTAssertEqual(model.probeM, FieldModel.electronMass,
                               accuracy: FieldModel.electronMass * 1e-9)
            }
        }
    }

    // MARK: The charge grip

    func testTheProbeChargeGripClampsToItsRange() {
        let model = FieldModel()
        model.setProbeMagnitude(1)
        XCTAssertEqual(model.probeChargeMagnitude,
                       FieldModel.probeChargeRange.upperBound, accuracy: 1e-18)
        model.setProbeMagnitude(-5)
        XCTAssertEqual(model.probeChargeMagnitude,
                       FieldModel.probeChargeRange.lowerBound, accuracy: 1e-18)
    }

    // MARK: Container versus subject

    /// The rule the inverted hit-test encodes: a Gauss bubble is a
    /// CONTAINER, and the thing inside it is the subject.
    ///
    /// The old ordering matched `"gauss-surface"` before resolving a
    /// charge, so a 55 cm bubble beat everything within it — and a charge
    /// inside one was only grabbable because the 12 cm proximity fallback
    /// happened to rescue it. That accident is now a rule, and this is the
    /// case that proves the rule still holds.
    func testAChargeInsideTheBubbleIsGrabbableThroughIt() {
        let charge = (id: UUID(), position: FieldModel.regionCenter)
        let hand = charge.position + SIMD3(0.05, 0, 0)

        let resolved = FieldSpaceView.resolveCharge(
            names: ["gauss-surface", "field-root"], hand: hand, charges: [charge])

        XCTAssertEqual(resolved, charge.id,
                       "A pinch 5 cm from a charge resolved to the bubble around it.")
    }

    /// And the classifier agrees about which part of the surface that hand
    /// was in, so the two halves of the rule cannot drift apart.
    func testTheSameHandReadsAsInsideNotSkin() {
        let center = FieldModel.regionCenter
        XCTAssertEqual(
            GaussGrab.classify(hand: center + SIMD3(0.05, 0, 0),
                               center: center, radius: 0.55),
            .inside)
    }
}

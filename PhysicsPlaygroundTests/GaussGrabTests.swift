//
//  GaussGrabTests.swift
//  PhysicsPlaygroundTests
//
//  The flux meter's radius and facing stopped being a slider and a picker
//  and became the act of grabbing its edge (2026-07-31). This is the
//  arithmetic behind that gesture.
//
//  The tilt is the part that matters most, because it is not a control
//  migration — it is a capability the app CLAIMED to have and did not. The
//  panel has been telling users to "tilt it edge-on to the field and the
//  flux falls to zero" for as long as the disc has existed, and
//  `gaussSurfaceNormal` had exactly two writers in the whole tree: its own
//  declaration and `reset()`, both writing (0,0,1). The instruction was
//  never actionable. These tests are what make it true.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class GaussGrabTests: XCTestCase {

    private let center = SIMD3<Double>(0, 1.35, -0.55)
    private let range = FieldModel.gaussRadiusRange

    // MARK: Where the hand is aiming

    func testTheEdgeIsGrabbableAndTheMiddleIsNot() {
        let radius = 0.30
        let band = GaussGrab.skinBand(forRadius: radius)

        XCTAssertEqual(GaussGrab.classify(hand: center + SIMD3(radius, 0, 0),
                                          center: center, radius: radius), .skin,
                       "A hand exactly on the surface must be grabbing the surface.")
        XCTAssertEqual(GaussGrab.classify(hand: center + SIMD3(radius * 0.4, 0, 0),
                                          center: center, radius: radius), .inside)
        XCTAssertEqual(GaussGrab.classify(hand: center + SIMD3(radius + band * 2, 0, 0),
                                          center: center, radius: radius), .miss)
    }

    /// A fraction alone is not enough at the small end. 25% of the 8 cm
    /// minimum radius is a 2 cm shell — thinner than the positional noise
    /// of a tracked hand, so the smallest bubble would be the one you
    /// cannot grab, which is exactly backwards.
    func testTheSmallestSurfaceIsStillGrabbable() {
        let band = GaussGrab.skinBand(forRadius: range.lowerBound)
        XCTAssertGreaterThanOrEqual(band, 0.04,
                                    "The minimum-radius bubble has no shell worth aiming at.")
    }

    /// A charge sitting inside the bubble must not be shadowed by it. This
    /// is why `.inside` exists as its own answer rather than folding into
    /// `.skin` — the caller resolves the contents first.
    func testTheInsideOfABigBubbleIsNotTheBubble() {
        XCTAssertEqual(GaussGrab.classify(hand: center + SIMD3(0.10, 0, 0),
                                          center: center, radius: 0.55), .inside,
                       "A hand deep inside the bubble was read as grabbing its skin.")
    }

    // MARK: The radius follows the hand

    func testTheSurfacePassesThroughTheFingertip() {
        for distance in [0.12, 0.25, 0.44] {
            let hand = center + SIMD3(0, 0, distance)
            XCTAssertEqual(
                GaussGrab.radius(forHand: hand, center: center, range: range),
                distance, accuracy: 1e-12,
                "The radius must simply be how far out the hand is.")
        }
    }

    func testTheRadiusPinsAtTheEndsOfItsRange() {
        XCTAssertEqual(GaussGrab.radius(forHand: center, center: center, range: range),
                       range.lowerBound, accuracy: 1e-12)
        XCTAssertEqual(GaussGrab.radius(forHand: center + SIMD3(5, 0, 0),
                                        center: center, range: range),
                       range.upperBound, accuracy: 1e-12)
    }

    // MARK: The facing follows the hand

    /// The claim the gesture makes: wherever your hand is, that is on the
    /// rim — which means the disc's normal is perpendicular to it.
    func testTheRimTurnsToMeetTheHand() {
        let normal = SIMD3<Double>(0, 0, 1)
        for hand in [SIMD3<Double>(0.3, 0, 0), SIMD3(0.2, 0.2, 0), SIMD3(0, 0.3, 0.1)] {
            let turned = GaussGrab.normal(forHand: center + hand,
                                          center: center, normal: normal)
            XCTAssertEqual(simd_length(turned), 1, accuracy: 1e-9,
                           "A facing must stay a unit vector.")
            XCTAssertEqual(simd_dot(turned, simd_normalize(hand)), 0, accuracy: 1e-9,
                           "The hand is not on the rim of the disc it produced.")
        }
    }

    /// The degenerate case, and the reason it must not be "pick something".
    /// A hand on the disc's AXIS describes every orientation equally well —
    /// the projection collapses to zero — so any answer but "leave it" is a
    /// facing the user did not choose, and the disc would snap.
    func testAHandOnTheAxisLeavesTheDiscAlone() {
        let normal = simd_normalize(SIMD3<Double>(0, 0, 1))
        let onAxis = center + normal * 0.3

        let result = GaussGrab.normal(forHand: onAxis, center: center, normal: normal)
        XCTAssertEqual(result, normal, "The disc snapped to an arbitrary facing.")
        XCTAssertFalse(result.x.isNaN || result.y.isNaN || result.z.isNaN,
                       "The degenerate case produced NaN.")
    }

    func testAHandAtTheExactCentreLeavesTheDiscAlone() {
        let normal = SIMD3<Double>(0, 0, 1)
        let result = GaussGrab.normal(forHand: center, center: center, normal: normal)
        XCTAssertEqual(result, normal)
        XCTAssertFalse(result.x.isNaN)
    }

    /// Absolute, not accumulating: the same hand always means the same
    /// disc, however it got there. (`Bloom`'s grip is relative and
    /// DECISIONS flags it as "the odd one out"; this is the other kind.)
    func testTheFacingDoesNotDriftOverALongDrag() {
        let start = SIMD3<Double>(0, 0, 1)
        let target = center + SIMD3<Double>(0.25, 0.1, 0)

        let direct = GaussGrab.normal(forHand: target, center: center, normal: start)

        var wandering = start
        for hand in [SIMD3<Double>(0.1, 0.3, 0), SIMD3(-0.2, 0, 0.2),
                     SIMD3(0.3, -0.1, 0.1), SIMD3(0.25, 0.1, 0)] {
            wandering = GaussGrab.normal(forHand: center + hand,
                                         center: center, normal: wandering)
        }
        // Both end perpendicular to the same final hand direction. They may
        // differ by a roll about it, which is the disc's own symmetry axis
        // and therefore not a difference anybody can see.
        let finalDirection = simd_normalize(target - center)
        XCTAssertEqual(simd_dot(wandering, finalDirection), 0, accuracy: 1e-9)
        XCTAssertEqual(simd_dot(direct, finalDirection), 0, accuracy: 1e-9)
    }

    // MARK: The physics the gesture exists to show

    /// The module's best teaching moment, now that it can actually be
    /// performed: turn the open disc edge-on and its flux falls to zero
    /// (Φ = EA cos θ), while the closed bubble holds Q/ε₀ however you turn
    /// it. That contrast IS Gauss's law.
    func testTiltingTheDiscEdgeOnTakesTheFluxToZero() {
        let model = FieldModel()
        model.charges = [PointCharge(position: model.gaussSurfaceCenter + SIMD3(0, 0, 0.3),
                                     charge: 2e-6)]
        model.gaussSurfaceOn = true
        model.gaussSurfaceKind = .disc
        model.setGaussNormal(SIMD3(0, 0, 1))     // face-on to the charge
        let faceOn = abs(model.gaussFlux)
        XCTAssertGreaterThan(faceOn, 0, "A disc facing a charge must catch flux.")

        model.setGaussNormal(SIMD3(0, 1, 0))     // edge-on
        XCTAssertLessThan(abs(model.gaussFlux), faceOn * 0.05,
                          "Edge-on to the field, the open disc must catch almost nothing.")
    }

    func testTheBubbleHoldsGaussLawHoweverItIsTurned() {
        let model = FieldModel()
        model.charges = [PointCharge(position: model.gaussSurfaceCenter,
                                     charge: 2e-6)]
        model.gaussSurfaceOn = true
        model.gaussSurfaceKind = .bubble

        let predicted = try? XCTUnwrap(model.gaussPredictedFlux)
        for normal in [SIMD3<Double>(0, 0, 1), SIMD3(1, 0, 0), SIMD3(0.3, 0.7, -0.2)] {
            model.setGaussNormal(normal)
            XCTAssertEqual(model.gaussFlux, predicted ?? 0,
                           accuracy: abs(predicted ?? 1) * 0.02,
                           "A closed surface's flux must not depend on its facing.")
        }
    }

    // MARK: The escape this gesture would otherwise open

    /// `moveGaussSurface` insets its clamp by the radius the surface has AT
    /// THE TIME, so growing it afterwards was never re-checked: a bubble
    /// parked against a wall and then grown pushed its own skin straight
    /// through the station. `FieldClampTests` asserts the widest bubble
    /// stays inside; this was the path around it.
    ///
    /// It barely mattered while growing meant dragging a slider in a panel.
    /// Now growing IS pulling the skin outward with your hand, against
    /// whatever wall you happen to be standing near.
    func testGrowingTheBubbleAgainstAWallPullsItBackInside() {
        let model = FieldModel()
        let station = StationBox(center: FieldModel.regionCenter,
                                 halfExtents: FieldModel.regionHalfExtents)

        model.setGaussRadius(FieldModel.gaussRadiusRange.lowerBound)
        model.moveGaussSurface(to: station.maximum)      // hard against the corner

        model.setGaussRadius(FieldModel.gaussRadiusRange.upperBound)

        let bubble = StationBox(
            center: model.gaussSurfaceCenter,
            halfExtents: SIMD3(repeating: model.gaussSurfaceRadius))
        XCTAssertTrue(station.contains(bubble, tolerance: 1e-6),
                      """
                      The bubble escaped the station by growing: centre \
                      \(model.gaussSurfaceCenter), radius \
                      \(model.gaussSurfaceRadius).
                      """)
    }

    func testTheRadiusSetterClampsToItsRange() {
        let model = FieldModel()
        model.setGaussRadius(10)
        XCTAssertEqual(model.gaussSurfaceRadius,
                       FieldModel.gaussRadiusRange.upperBound, accuracy: 1e-12)
        model.setGaussRadius(-1)
        XCTAssertEqual(model.gaussSurfaceRadius,
                       FieldModel.gaussRadiusRange.lowerBound, accuracy: 1e-12)
    }
}

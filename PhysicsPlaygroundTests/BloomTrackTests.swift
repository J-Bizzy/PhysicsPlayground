//
//  BloomTrackTests.swift
//  PhysicsPlaygroundTests
//
//  The calm track that sets a charge's |q| and a body's mass (2026-10-24).
//  It replaced a handle on the object's surface whose distance from the
//  centre was the sphere's radius: a charge's whole range took 3.7 cm of
//  hand travel and 8 mm doubled it, so tracking jitter moved the number.
//  These hold the track to what replaced that: long, logarithmic, relative,
//  clicking at round values, with the bead staying under the finger.
//

import XCTest
import RealityKit
@testable import PhysicsPlayground

@MainActor
final class BloomTrackTests: XCTestCase {

    /// A charge-like grip: 0.2–6, drawn as a sphere whose radius goes as the
    /// cube root of its value, on the calm track.
    private func chargeGrip(value: @escaping () -> Double, write: @escaping (Double) -> Void,
                            detents: [Double] = []) -> Bloom.Grip {
        .init(name: "Charge", range: 0.2...6,
              read: value, write: write, format: { "\($0)" },
              radius: { 0.03 * Float(cbrt(value())) },
              track: .init(detents: detents.map { .init(value: $0, label: nil) }))
    }

    /// An open ring, its viewer 0.8 m in front so its scale is 0.8 and its
    /// rail runs along +x.
    private func openRing(_ grip: Bloom.Grip) -> Bloom {
        let bloom = Bloom()
        bloom.configure(petals: [], grip: grip)
        settle(bloom)
        return bloom
    }

    private func settle(_ bloom: Bloom) {
        for _ in 0..<80 {
            bloom.update(anchor: .zero, viewer: [0, 0, 0.8], revealTarget: 1, dt: 1.0 / 90.0)
        }
    }

    private func child(_ name: String, of bloom: Bloom) throws -> Entity {
        try XCTUnwrap(bloom.root.children.first { $0.name == name })
    }

    /// The hand travel that crosses the whole range at this ring's distance.
    private let travel = Double(Bloom.calmTrackLength) * 0.8

    // MARK: Long and logarithmic

    func testTheWholeRangeIsAboutFifteenCentimetresAtArmsLength() {
        XCTAssertEqual(travel, 0.15, accuracy: 0.01)
    }

    func testEqualTravelMultipliesTheValueByEqualFactors() {
        let grip = chargeGrip(value: { 1 }, write: { _ in })
        XCTAssertEqual(grip.fraction(of: 0.2), 0, accuracy: 1e-12)
        XCTAssertEqual(grip.fraction(of: 6), 1, accuracy: 1e-12)
        XCTAssertEqual(grip.value(at: 0.5), (0.2 * 6.0).squareRoot(), accuracy: 1e-12)
        let step = 0.1
        let ratios = stride(from: 0.0, through: 0.8, by: 0.2).map {
            grip.value(at: $0 + step) / grip.value(at: $0)
        }
        for ratio in ratios { XCTAssertEqual(ratio, ratios[0], accuracy: 1e-12) }
        for value in [0.2, 0.7, 1, 3.3, 6] {
            XCTAssertEqual(grip.value(at: grip.fraction(of: value)), value, accuracy: 1e-12)
        }
    }

    /// Doubling a charge used to take 8 mm of hand travel. On the track it
    /// takes about three centimetres, so a millimetre or two of tracking
    /// jitter is a few per cent, not a factor.
    func testDoublingAChargeTakesCentimetresOfTravelNotMillimetres() {
        let grip = chargeGrip(value: { 1 }, write: { _ in })
        let doubling = (grip.fraction(of: 2) - grip.fraction(of: 1)) * travel
        XCTAssertGreaterThan(doubling, 0.025)
    }

    // MARK: Relative, and the bead under the finger

    func testTheValueMovesByHowFarTheHandTravelsNotWhereItLanded() throws {
        var value = 1.0
        let bloom = openRing(chargeGrip(value: { value }, write: { value = $0 }))
        let bead = try child("bloom-grip", of: bloom)
        // Landing a centimetre off the bead's centre changes nothing.
        let landing = SIMD3<Float>(0.31, 0.01, 0)
        XCTAssertTrue(bloom.beginGrip(bead, hand: landing))
        XCTAssertTrue(bloom.updateGrip(hand: landing))
        XCTAssertEqual(value, 1, accuracy: 1e-12)
        // Up, down and toward you move nothing; along the rail moves it.
        _ = bloom.updateGrip(hand: landing + [0, 0.05, 0.04])
        XCTAssertEqual(value, 1, accuracy: 1e-12)
        _ = bloom.updateGrip(hand: landing + [0.04, 0, 0])
        let grip = chargeGrip(value: { 1 }, write: { _ in })
        XCTAssertEqual(value, grip.value(at: grip.fraction(of: 1) + 0.04 / travel), accuracy: 1e-6)
        bloom.endGrip()
    }

    /// The sphere swells under the hand, and the bead must not run away from
    /// the finger as it does: the track's start is held for the whole drag.
    func testTheBeadStaysUnderTheFingerAsTheObjectGrows() throws {
        var value = 1.0
        let bloom = openRing(chargeGrip(value: { value }, write: { value = $0 }))
        let bead = try child("bloom-grip", of: bloom)
        let before = bloom.root.convert(position: bead.position, to: nil)
        XCTAssertTrue(bloom.beginGrip(bead, hand: before))
        let pull: Float = 0.06
        _ = bloom.updateGrip(hand: before + [pull, 0, 0])
        settle(bloom)
        XCTAssertGreaterThan(value, 2, "the pull should have more than doubled the charge")
        let after = bloom.root.convert(position: bead.position, to: nil)
        XCTAssertEqual(after.x - before.x, pull, accuracy: 1e-4)
        bloom.endGrip()
    }

    func testThePullStopsAtTheEndsOfTheRange() throws {
        var value = 1.0
        let bloom = openRing(chargeGrip(value: { value }, write: { value = $0 }))
        let bead = try child("bloom-grip", of: bloom)
        XCTAssertTrue(bloom.beginGrip(bead, hand: .zero))
        _ = bloom.updateGrip(hand: [1, 0, 0])
        XCTAssertEqual(value, 6, accuracy: 1e-12)
        _ = bloom.updateGrip(hand: [-1, 0, 0])
        XCTAssertEqual(value, 0.2, accuracy: 1e-12)
        bloom.endGrip()
    }

    // MARK: Clicks

    func testTheBeadClicksIntoARoundValueItPassesNear() throws {
        var value = 1.0
        let bloom = openRing(chargeGrip(value: { value }, write: { value = $0 }, detents: [1, 2, 3]))
        let grip = chargeGrip(value: { 1 }, write: { _ in })
        let bead = try child("bloom-grip", of: bloom)
        XCTAssertTrue(bloom.beginGrip(bead, hand: .zero))
        // Two millimetres short of 2 µC: in the window, so exactly 2.
        let toTwo = Float((grip.fraction(of: 2) - grip.fraction(of: 1)) * travel)
        _ = bloom.updateGrip(hand: [toTwo - 0.002, 0, 0])
        XCTAssertEqual(value, 2, accuracy: 1e-12)
        // Six millimetres short: out of it, so free — about 1.75 µC.
        _ = bloom.updateGrip(hand: [toTwo - 0.006, 0, 0])
        XCTAssertEqual(value, grip.value(at: grip.fraction(of: 2) - 0.006 / travel), accuracy: 1e-4)
        XCTAssertLessThan(value, 1.8)
        bloom.endGrip()
    }

    func testVoiceOverStepsFromOneRoundValueToTheNext() throws {
        var value = 1.0
        let bloom = openRing(chargeGrip(value: { value }, write: { value = $0 },
                                        detents: [0.5, 1, 2, 3, 4, 5, 6]))
        bloom.nudgeGrip(by: 1)
        XCTAssertEqual(value, 2)
        bloom.nudgeGrip(by: 2)
        XCTAssertEqual(value, 4)
        bloom.nudgeGrip(by: -4)
        XCTAssertEqual(value, 0.5)
        bloom.nudgeGrip(by: -1)
        XCTAssertEqual(value, 0.2, "below the lowest round value lies the end of the range")
        for _ in 0..<12 { bloom.nudgeGrip(by: 1) }
        XCTAssertEqual(value, 6)
        // From between two round values, the next one up.
        value = 2.6
        bloom.nudgeGrip(by: 1)
        XCTAssertEqual(value, 3)
    }

    // MARK: The rail

    func testAPinchAnywhereOnTheRailTakesTheBeadButOnlyOnceTheRingIsOpen() throws {
        var value = 1.0
        let bloom = Bloom()
        bloom.configure(petals: [], grip: chargeGrip(value: { value }, write: { value = $0 },
                                                     detents: [1, 2]))
        let rail = try child("bloom-track", of: bloom)
        for _ in 0..<40 {
            bloom.update(anchor: .zero, viewer: [0, 0, 0.8], revealTarget: 0, dt: 1.0 / 90.0)
        }
        XCTAssertFalse(bloom.beginGrip(rail, hand: .zero), "a folded ring hands out nothing")
        settle(bloom)
        XCTAssertTrue(bloom.beginGrip(rail, hand: .zero))
        _ = bloom.updateGrip(hand: [0.05, 0, 0])
        XCTAssertGreaterThan(value, 1)
        bloom.endGrip()
    }

    func testTheRailCarriesATickAtEveryRoundValueAndANumberWhereAsked() throws {
        let grip = Bloom.Grip(
            name: "Charge", range: 0.2...6, read: { 1 }, write: { _ in }, format: { "\($0)" },
            radius: { 0.03 }, track: FieldSpaceView.chargeTrack)
        let rail = Bloom.makeTrack(FieldSpaceView.chargeTrack, for: grip)
        // The rail, a tick per detent, and a number for all but 5 µC.
        let detents = FieldModel.magnitudeDetents.count
        XCTAssertEqual(rail.children.count, 1 + detents + (detents - 1))
        XCTAssertNotNil(rail.components[CollisionComponent.self])
    }

    // MARK: Each lab's round values

    /// Every lab's clicks lie inside its range and far enough apart on the
    /// track that two never share a window.
    func testEveryLabsRoundValuesFitTheirTrack() {
        let labs: [(String, ClosedRange<Double>, Bloom.Grip.Track)] = [
            ("charge", FieldModel.magnitudeRange, FieldSpaceView.chargeTrack),
            ("test charge", FieldModel.probeChargeRange, FieldSpaceView.probeTrack),
            ("star", OrbitalMechanicsModel.primaryMassRangeSuns, OrbitalMechanicsSpaceView.starTrack),
            ("planet", OrbitalMechanicsModel.massRangeEarths, OrbitalMechanicsSpaceView.planetTrack),
        ]
        for (name, range, track) in labs {
            let grip = Bloom.Grip(name: name, range: range, read: { range.lowerBound },
                                  write: { _ in }, format: { "\($0)" }, radius: { 0.03 },
                                  track: track)
            XCTAssertFalse(track.detents.isEmpty, name)
            let fractions = track.detents.map { grip.fraction(of: $0.value) }
            for (detent, fraction) in zip(track.detents, fractions) {
                XCTAssertTrue(range.contains(detent.value), "\(name): \(detent.value) is off its track")
                XCTAssertTrue((0...1).contains(fraction), name)
            }
            for (a, b) in zip(fractions, fractions.dropFirst()) {
                XCTAssertGreaterThan(b - a, 2 * Bloom.detentWindow,
                                     "\(name): two clicks share a window")
            }
        }
    }

    func testTickNumbersCarryOnlyTheDecimalsTheyNeed() {
        XCTAssertEqual(PhysicsFormat.compact(0.5), "0.5")
        XCTAssertEqual(PhysicsFormat.compact(1), "1")
        XCTAssertEqual(PhysicsFormat.compact(20), "20")
        XCTAssertEqual(PhysicsFormat.compact(0.05), "0.05")
        XCTAssertEqual(PhysicsFormat.compact(100), "100")
        XCTAssertEqual(PhysicsFormat.compact(1e-9 * 1e9), "1")
    }
}

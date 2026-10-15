//
//  HubTitleMotionTests.swift
//  PhysicsPlaygroundTests
//
//  The wordmark's letters move by physics, so the physics is pinned:
//  the drop is free fall then restitution, the swing is a damped
//  physical pendulum with the frequency its shape gives it, the wave's
//  tilt is its slope, and every motion ends at rest — the title must
//  land exactly where the still title stood.
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class HubTitleMotionTests: XCTestCase {

    private let g = HubTitleMotion.g

    // MARK: The drop

    func testALetterFallsFreelyFromItsHeight() {
        let h = HubTitleMotion.dropHeight
        XCTAssertEqual(HubTitleMotion.bounce(time: 0, height: h), h, accuracy: 1e-12)
        // y = h − ½ g t² until it lands, at t = √(2h/g).
        let t = 0.1
        XCTAssertEqual(HubTitleMotion.bounce(time: t, height: h), h - 0.5 * g * t * t,
                       accuracy: 1e-12)
        let contact = (2 * h / g).squareRoot()
        XCTAssertEqual(HubTitleMotion.bounce(time: contact, height: h), 0, accuracy: 1e-9)
    }

    /// Each bounce reaches e² of the height before: the impact keeps e of
    /// the speed, and height goes as speed squared.
    func testEachBounceReachesRestitutionSquaredOfTheLast() {
        let h = HubTitleMotion.dropHeight, e = HubTitleMotion.restitution
        var peaks: [Double] = []
        var previous = h, rising = false
        for step in 0...40_000 {
            let y = HubTitleMotion.bounce(time: Double(step) * 1e-4, height: h)
            XCTAssertGreaterThanOrEqual(y, -1e-12, "a letter went through its own resting place")
            if y > previous { rising = true }
            if rising && y < previous { peaks.append(previous); rising = false }
            previous = y
        }
        XCTAssertGreaterThanOrEqual(peaks.count, 2)
        XCTAssertEqual(peaks[0] / h, e * e, accuracy: 1e-3)
        XCTAssertEqual(peaks[1] / peaks[0], e * e, accuracy: 1e-3)
    }

    func testTheBounceEndsAtRestWhenItSaysItDoes() {
        let h = HubTitleMotion.dropHeight
        let end = HubTitleMotion.bounceDuration(height: h)
        XCTAssertEqual(HubTitleMotion.bounce(time: end + 1e-6, height: h), 0)
        XCTAssertEqual(HubTitleMotion.bounce(time: end + 5, height: h), 0)
        XCTAssertLessThan(end, 1.2, "a letter that bounces for over a second reads as broken")
    }

    /// A tap throws a letter up at a speed that peaks seven centimetres up.
    func testAHopPeaksAtSevenCentimetres() {
        let v = HubTitleMotion.hopSpeed
        let apex = HubTitleMotion.bounce(time: v / g, launchSpeed: v)
        XCTAssertEqual(apex, 0.07, accuracy: 1e-9)
        XCTAssertEqual(HubTitleMotion.bounce(time: 0, launchSpeed: v), 0)
    }

    // MARK: The swing

    /// With no width, the letter is a rod hung from its end, whose ω² is
    /// 3g/2L — the textbook result.
    func testTheSwingRateIsAPhysicalPendulums() {
        let length = 0.05
        XCTAssertEqual(HubTitleMotion.swingRate(width: 0, height: length),
                       (3 * g / (2 * length)).squareRoot(), accuracy: 1e-9)
        // A wider letter has more inertia about the hinge: it swings slower.
        XCTAssertLessThan(HubTitleMotion.swingRate(width: 0.05, height: 0.05),
                          HubTitleMotion.swingRate(width: 0.01, height: 0.05))
    }

    func testTheSwingStartsTiltedAtRestAndDiesAway() {
        let rate = HubTitleMotion.swingRate(width: 0.04, height: 0.05)
        let a = HubTitleMotion.swingAmplitude
        XCTAssertEqual(HubTitleMotion.swing(time: 0, rate: rate), a, accuracy: 1e-12)
        // Released from rest: no angular speed at the instant of release.
        let dt = 1e-6
        XCTAssertEqual((HubTitleMotion.swing(time: dt, rate: rate) - a) / dt, 0, accuracy: 1e-2)
        // Never beyond its damping envelope (allowing the phase term).
        for step in 0...2_000 {
            let t = Double(step) * 1e-3
            let envelope = a * exp(-HubTitleMotion.swingDamping * t) * 1.2
            XCTAssertLessThanOrEqual(abs(HubTitleMotion.swing(time: t, rate: rate)), envelope + 1e-9)
        }
        let settled = HubTitleMotion.swingSettles(after: 0)
        XCTAssertLessThan(abs(HubTitleMotion.swing(time: settled, rate: rate)), 0.0012)
    }

    // MARK: At rest

    /// The wave is millimetres, and each letter tilts with its slope.
    func testTheWaveIsGentleAndTheTiltIsItsSlope() {
        let dx = 1e-6
        for x in stride(from: -0.3, through: 0.3, by: 0.05) {
            for t in stride(from: 0.0, through: 6, by: 0.37) {
                let here = HubTitleMotion.wave(at: x, time: t)
                XCTAssertLessThanOrEqual(abs(here.lift), HubTitleMotion.waveHeight + 1e-12)
                let slope = (HubTitleMotion.wave(at: x + dx, time: t).lift - here.lift) / dx
                XCTAssertEqual(here.tilt, slope, accuracy: 1e-6)
            }
        }
    }

    func testTheGlintRunsOnceAcrossAndIsGone() {
        XCTAssertEqual(HubTitleMotion.glint(at: 0, since: -1), 0)
        let middle = HubTitleMotion.glintReach / HubTitleMotion.glintSpeed
        XCTAssertEqual(HubTitleMotion.glint(at: 0, since: middle), 1, accuracy: 1e-9)
        let gone = 2 * HubTitleMotion.glintReach / HubTitleMotion.glintSpeed + 0.5
        XCTAssertEqual(HubTitleMotion.glint(at: 0.3, since: gone), 0)
        XCTAssertLessThan(gone, HubTitleMotion.glintPeriod, "glints would overlap")
    }

    // MARK: The arrival's clock

    /// "Physics" lands across the bell, and both lines are at rest within a
    /// couple of seconds of it.
    func testTheTitleArrivesAroundTheBellAndSettles() {
        let firstLanding = HubTitleMotion.dropRelease(0)
            + (2 * HubTitleMotion.dropHeight / g).squareRoot()
        let lastLanding = HubTitleMotion.dropRelease(6)
            + (2 * HubTitleMotion.dropHeight / g).squareRoot()
        XCTAssertLessThan(firstLanding, Opening.landingTime)
        XCTAssertGreaterThan(lastLanding, Opening.landingTime)
        let swingDone = HubTitleMotion.swingSettles(after: HubTitleMotion.swingRelease(9))
        XCTAssertLessThan(swingDone - Opening.landingTime, 2.2)
    }
}

/// The living title in the real home scene.
@MainActor
final class HubTitleGlyphsTests: XCTestCase {

    private func scene(stillness: Bool = false) -> HubScene {
        let scene = HubScene()
        scene.openingAlreadyPlayed = true
        scene.stillness = stillness
        scene.build(modules: ModuleCatalog.all(appModel: AppModel()))
        return scene
    }

    /// Seventeen letters, each its own target: "Physics" and "Playground".
    func testTheWordmarkIsSeventeenLettersEachAPinchTarget() {
        let letters = scene().titleLetters
        XCTAssertEqual(letters.count, 17, "the per-letter assets did not load")
        for letter in letters {
            XCTAssertNotNil(letter.components[InputTargetComponent.self])
            XCTAssertNotNil(letter.components[CollisionComponent.self])
            XCTAssertNotNil(letter.components[HoverEffectComponent.self])
        }
    }

    /// A tap hops the letter it lands on, and the letter comes back down
    /// to exactly where it stood.
    func testATapHopsALetterAndItLandsWhereItStood() throws {
        let scene = scene()
        let letter = try XCTUnwrap(scene.titleLetters.first)
        // Let the scene run, then settle on a frame where the wave is known.
        for _ in 0..<5 { scene.animate(dt: 1.0 / 90.0) }
        XCTAssertTrue(scene.hopTitleLetter(letter))
        var highest: Float = -.greatestFiniteMagnitude
        let start = letter.position(relativeTo: nil).y
        for _ in 0..<30 {
            scene.animate(dt: 1.0 / 90.0)
            highest = max(highest, letter.position(relativeTo: nil).y)
        }
        XCTAssertGreaterThan(highest - start, 0.03, "the letter did not hop")
        // A tap on something that is not a letter is not taken.
        XCTAssertFalse(scene.hopTitleLetter(Entity()))
    }

    /// VoiceOver reaches the same thing: activating the wordmark hops
    /// every letter.
    func testActivatingTheWordmarkHopsEveryLetter() throws {
        let scene = scene()
        let letters = scene.titleLetters
        let anchor = try XCTUnwrap(letters.first?.parent?.parent?.parent)
        for _ in 0..<3 { scene.animate(dt: 1.0 / 90.0) }
        let before = letters.map { $0.position.y }
        XCTAssertTrue(SpatialActions.activate(anchor), "the wordmark has no action")
        var risen = Set<Int>()
        for _ in 0..<120 {
            scene.animate(dt: 1.0 / 90.0)
            for (index, letter) in letters.enumerated() where letter.position.y > before[index] + 0.1 {
                risen.insert(index)
            }
        }
        XCTAssertEqual(risen.count, letters.count, "not every letter hopped")
    }

    /// Under Reduce Motion the letters hold still — no wave, no hop.
    func testUnderStillnessTheLettersHoldStill() throws {
        let scene = scene(stillness: true)
        let letter = try XCTUnwrap(scene.titleLetters.first)
        scene.animate(dt: 1.0 / 90.0)
        let before = letter.position(relativeTo: nil)
        XCTAssertTrue(scene.hopTitleLetter(letter), "a still letter still owns its pinch")
        for _ in 0..<60 { scene.animate(dt: 1.0 / 90.0) }
        XCTAssertEqual(simd_distance(before, letter.position(relativeTo: nil)), 0, accuracy: 1e-6)
    }
}

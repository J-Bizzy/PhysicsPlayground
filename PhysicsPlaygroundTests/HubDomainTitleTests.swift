//
//  HubDomainTitleTests.swift
//  Physics Playground — app tests
//
//  The signage over the two doors moves, and the movement claims to be
//  physics: an electron on a tilted orbit, a ball bouncing along the
//  rule in decaying parabolic hops. Decoration in this app still has
//  to tell the truth about its shapes, so the shapes are pure
//  functions and these tests hold them — above all the one hard
//  promise of the 2026-08-03 redesign: the ball can NEVER touch a
//  letter, because its every apex is capped below the baseline.
//

import XCTest
import RealityKit
import simd
@testable import PhysicsPlayground

final class HubDomainTitleTests: XCTestCase {

    private let halfWidth: Float = 0.31
    private let halfHeight: Float = 0.14
    private let ruleY: Float = -0.20
    /// Stand-ins for a real sign's measured lanes: the letters here are
    /// 55 mm of plaque extrusion, so the front lane clears +0.055 and
    /// the back lane clears 0.
    private let frontLane: Float = 0.079
    private let backLane: Float = -0.024

    private func path(_ domain: HubDomain, _ time: Double) -> SIMD3<Float> {
        HubDomainTitle.path(for: domain, time: time,
                            halfWidth: halfWidth, halfHeight: halfHeight,
                            ruleY: ruleY,
                            frontLane: frontLane, backLane: backLane)
    }

    // MARK: The electron's orbit

    /// Wherever it is in its lap, the electron is ON its ellipse — a
    /// spark that drifts off the drawn track reads as a bug within one
    /// orbit, because the track is right there to compare against.
    func testTheElectronStaysOnItsTrack() {
        let a = halfWidth * HubDomainTitle.orbitReach
        let b = halfHeight + HubDomainTitle.orbitRise
        for step in 0..<97 {
            let position = path(.electricity, Double(step) * 0.17)
            let radial = (position.x / a) * (position.x / a)
                + (position.y / b) * (position.y / b)
            XCTAssertEqual(radial, 1, accuracy: 1e-4,
                           "the electron left its ellipse at step \(step)")
        }
    }

    /// The orbit is tilted in z so the lap crosses IN FRONT of the
    /// letters on one half and BEHIND on the other — the depth pass is
    /// what sells the type as solid, so it must actually happen. Both
    /// extremes have to reach AT LEAST their measured lane; the 2.2×
    /// overshoot beyond it is the parallax that makes the orbit read
    /// as a thing in space rather than a decal.
    func testTheOrbitCrossesInFrontAndBehindTheLetters() {
        let depths = (0..<64).map { step in
            HubDomainTitle.orbitPoint(theta: Float(step) / 64 * 2 * .pi,
                                      halfWidth: halfWidth,
                                      halfHeight: halfHeight,
                                      frontLane: frontLane,
                                      backLane: backLane).z
        }
        XCTAssertLessThanOrEqual(depths.min() ?? 0, backLane,
                       "the lap never reaches the lane behind the letters")
        XCTAssertGreaterThanOrEqual(depths.max() ?? 0, frontLane,
                       "the lap never reaches the lane in front of the letters")
    }

    /// The lap is a PLANAR ellipse — a genuinely tilted orbit, not a
    /// flat one with a depth gimmick: z is an exact linear function of
    /// y, which is what "one slanted plane" means.
    func testTheOrbitLiesInOneTiltedPlane() {
        let b = halfHeight + HubDomainTitle.orbitRise
        let mid = (frontLane + backLane) / 2
        let swing = (frontLane - backLane) / 2
        for step in 0..<64 {
            let p = HubDomainTitle.orbitPoint(
                theta: Float(step) / 64 * 2 * .pi,
                halfWidth: halfWidth, halfHeight: halfHeight,
                frontLane: frontLane, backLane: backLane)
            let expected = mid - (p.y / b) * swing * HubDomainTitle.orbitDepthGain
            XCTAssertEqual(p.z, expected, accuracy: 1e-4,
                           "the orbit left its plane at step \(step)")
        }
    }

    /// And the lap has to actually GO somewhere the letters are, or the
    /// depth swap happens in empty air where nothing can occlude it.
    /// The first orbit hung outside the lockup on every side and the
    /// "behind" half was invisible for that reason alone.
    func testTheOrbitPassesInsideTheLettersSilhouette() {
        let inside = (0..<128).contains { step in
            let p = HubDomainTitle.orbitPoint(
                theta: Float(step) / 128 * 2 * .pi,
                halfWidth: halfWidth, halfHeight: halfHeight,
                frontLane: frontLane, backLane: backLane)
            // Behind the letters AND within the block's silhouette.
            return p.z < 0 && abs(p.x) < halfWidth && abs(p.y) < halfHeight
        }
        XCTAssertTrue(inside,
                      "no part of the lap passes behind an actual letter — "
                      + "the depth crossing has nothing to sell")
    }

    // MARK: The ball's travelling bounce

    /// The turnaround points sit ON the rule, at its two ends: the run
    /// is a bounce between two real points, not a float through space.
    func testTheBallTurnsRoundOnTheRule() {
        let period = HubDomainTitle.crossingPeriod
        for crossing in 0..<4 {
            let start = path(.mechanics, Double(crossing) * period + 1e-4)
            XCTAssertEqual(start.y, ruleY + HubDomainTitle.ballRadius,
                           accuracy: 1e-2,
                           "crossing \(crossing) starts off the rule")
            XCTAssertEqual(abs(start.x),
                           halfWidth * HubDomainTitle.launchReach, accuracy: 1e-2,
                           "crossing \(crossing) starts from mid-air")
        }
    }

    /// …and those two ends are ON the rule but OUTBOARD of the type.
    func testTheBallTurnsRoundOutsideTheLettersButOnTheRule() {
        let launch = halfWidth * HubDomainTitle.launchReach
        let ruleEnd = halfWidth * HubDomainTitle.ruleOverhang
        XCTAssertGreaterThan(launch, halfWidth,
                             "the ball turns round under the letters")
        XCTAssertLessThan(launch, ruleEnd,
                          "the ball turns round off the end of the rule, in space")
    }

    /// THE hard promise of the redesign, dense-sampled: at no instant
    /// does any part of the ball enter the letters' inflated box — not
    /// in y (every hop apex plus the ball's radius stays below the
    /// baseline) and not in z (the whole run rides the front lane).
    /// The old single lob could only hope for this; the bounce has it
    /// by construction, and this holds the construction.
    func testTheBallCanNeverTouchALetter() {
        for step in 0..<800 {
            let p = path(.mechanics, Double(step) * 0.0173)
            XCTAssertLessThan(
                p.y + HubDomainTitle.ballRadius, -halfHeight + 1e-5,
                "the ball's skin reached the letters' baseline at step \(step)")
            XCTAssertGreaterThanOrEqual(
                p.z, frontLane - 1e-5,
                "the ball is inside the letter solids at step \(step)")
            XCTAssertGreaterThanOrEqual(
                p.y - HubDomainTitle.ballRadius, ruleY - 1e-4,
                "the ball fell through the rule at step \(step)")
        }
    }

    /// The hops decay like a real bounce: each apex lower than the
    /// last, by the declared restitution.
    func testTheHopsDecayLikeARealBounce() {
        let period = HubDomainTitle.crossingPeriod
        // Sample densely and take the apex within each hop's window.
        var start: Float = 0
        var apexes: [Float] = []
        for width in HubDomainTitle.hopFractions {
            let mid = start + width / 2
            apexes.append(path(.mechanics, Double(mid) * period).y)
            start += width
        }
        for index in 1..<apexes.count {
            let rest = ruleY + HubDomainTitle.ballRadius
            let previous = apexes[index - 1] - rest
            let current = apexes[index] - rest
            XCTAssertEqual(current, previous * HubDomainTitle.hopDecay,
                           accuracy: 1e-4,
                           "hop \(index) did not decay by the restitution")
        }
    }

    /// Consecutive crossings run opposite ways — a ball kept in play
    /// between two points, not a film loop rewinding.
    func testConsecutiveCrossingsAlternateDirection() {
        let period = HubDomainTitle.crossingPeriod
        let first = path(.mechanics, period * 0.1)
        let second = path(.mechanics, period * 1.1)
        XCTAssertEqual(first.x, -second.x, accuracy: 1e-3,
                       "the second crossing retraces the first instead of returning")
    }

    // MARK: The measured lanes

    /// A real sign measures its own letters and puts both lanes clear of
    /// them. This is the test that would have caught the ball flying
    /// through a glyph, and the only one that can: every number involved
    /// comes out of RealityKit's text extrusion at runtime.
    @MainActor
    func testEachSignMeasuresLanesClearOfItsOwnLetters() {
        for domain in HubDomain.allCases {
            let title = HubDomainTitle(domain: domain, width: 0.62)
            // The two line entities are the first two children.
            let letters = Array(title.root.children.prefix(2))
                .map { $0.visualBounds(relativeTo: title.root) }
            let front = letters.map(\.max.z).max() ?? 0
            let back = letters.map(\.min.z).min() ?? 0
            XCTAssertGreaterThan(
                title.frontLane, front,
                "\(domain)'s front lane is inside its own letters")
            XCTAssertLessThan(
                title.backLane, back,
                "\(domain)'s back lane is inside its own letters")
        }
    }

    // MARK: The lockup

    /// Both lines scale to the same width — the flush-both-sides lockup
    /// the wordmark set the standard for. Unequal lines read as an
    /// accident, which is exactly what the measured math exists to
    /// prevent.
    @MainActor
    func testBothLinesShareOneWidth() {
        for domain in HubDomain.allCases {
            let title = HubDomainTitle(domain: domain, width: 0.62)
            // The two line entities are the first two children.
            let lines = Array(title.root.children.prefix(2))
            XCTAssertEqual(lines.count, 2)
            let widths = lines.map {
                $0.visualBounds(relativeTo: title.root).extents.x
            }
            XCTAssertEqual(
                widths[0], widths[1],
                accuracy: max(widths[0], widths[1]) * 0.06,
                "\(domain)'s lockup lines differ in width — the flush "
                + "lockup broke")
        }
    }

    /// The sign names its door for VoiceOver — signage that only sighted
    /// users can read is half a sign.
    @MainActor
    func testTheSignCarriesItsAccessibilityLabel() {
        for domain in HubDomain.allCases {
            let title = HubDomainTitle(domain: domain, width: 0.62)
            let label = title.root.components[AccessibilityComponent.self]?.label
            XCTAssertEqual(label.map(String.init(localized:)), domain.title)
        }
    }
}

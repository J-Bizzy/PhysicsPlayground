//
//  HubDomainTitleTests.swift
//  Physics Playground — app tests
//
//  The signage over the two doors moves, and the movement claims to be
//  physics: an electron on an ellipse, a ball on a parabola that lands
//  where it can be lobbed back. Decoration in this app still has to
//  tell the truth about its shapes, so the shapes are pure functions
//  and these tests hold them.
//

import XCTest
import RealityKit
import simd
@testable import PhysicsPlayground

final class HubDomainTitleTests: XCTestCase {

    private let halfWidth: Float = 0.31
    private let halfHeight: Float = 0.14
    private let ruleY: Float = -0.20

    // MARK: The electron's orbit

    /// Wherever it is in its lap, the electron is ON its ellipse — a
    /// spark that drifts off the drawn track reads as a bug within one
    /// orbit, because the track is right there to compare against.
    func testTheElectronStaysOnItsTrack() {
        let a = halfWidth + 0.09
        let b = halfHeight + 0.055
        for step in 0..<97 {
            let position = HubDomainTitle.path(
                for: .electricity, time: Double(step) * 0.17,
                halfWidth: halfWidth, halfHeight: halfHeight, ruleY: ruleY)
            let radial = (position.x / a) * (position.x / a)
                + (position.y / b) * (position.y / b)
            XCTAssertEqual(radial, 1, accuracy: 1e-4,
                           "the electron left its ellipse at step \(step)")
        }
    }

    /// The orbit is tilted in z so the lap crosses IN FRONT of the
    /// letters on one half and BEHIND on the other — the depth pass is
    /// what sells the type as solid, so it must actually happen.
    func testTheOrbitCrossesInFrontAndBehindTheLetters() {
        let depths = (0..<64).map { step in
            HubDomainTitle.orbitPoint(theta: Float(step) / 64 * 2 * .pi,
                                      halfWidth: halfWidth,
                                      halfHeight: halfHeight).z
        }
        XCTAssertLessThan(depths.min() ?? 0, -0.03, "never passes behind")
        XCTAssertGreaterThan(depths.max() ?? 0, 0.03, "never passes in front")
    }

    // MARK: The ball's lob

    /// Launch and landing sit ON the rule, at its two ends: the arc is
    /// a throw between two real points, not a float through space.
    func testTheBallLaunchesAndLandsOnTheRule() {
        let period = 2.8
        for crossing in 0..<4 {
            let start = HubDomainTitle.path(
                for: .mechanics, time: Double(crossing) * period + 1e-4,
                halfWidth: halfWidth, halfHeight: halfHeight, ruleY: ruleY)
            XCTAssertEqual(start.y, ruleY, accuracy: 1e-2,
                           "crossing \(crossing) launches off the rule")
            XCTAssertEqual(abs(start.x), halfWidth * 0.92, accuracy: 1e-2,
                           "crossing \(crossing) launches from mid-air")
        }
    }

    /// The apex clears the top of the letters — a lob that passes
    /// THROUGH the sign it decorates is the one unforgivable frame.
    func testTheArcClearsTheSign() {
        let period = 2.8
        let apex = HubDomainTitle.path(
            for: .mechanics, time: period / 2,
            halfWidth: halfWidth, halfHeight: halfHeight, ruleY: ruleY)
        XCTAssertGreaterThan(apex.y, halfHeight + 0.10,
                             "the ball grazes the letters at the top of its arc")
        // And the path truly is a parabola: symmetric about the apex.
        let early = HubDomainTitle.path(
            for: .mechanics, time: period * 0.25,
            halfWidth: halfWidth, halfHeight: halfHeight, ruleY: ruleY)
        let late = HubDomainTitle.path(
            for: .mechanics, time: period * 0.75,
            halfWidth: halfWidth, halfHeight: halfHeight, ruleY: ruleY)
        XCTAssertEqual(early.y, late.y, accuracy: 1e-4,
                       "the arc is not symmetric — that is not a parabola")
    }

    /// Consecutive crossings run opposite ways — a ball kept in play
    /// between two points, not a film loop rewinding.
    func testConsecutiveCrossingsAlternateDirection() {
        let period = 2.8
        let first = HubDomainTitle.path(
            for: .mechanics, time: period * 0.1,
            halfWidth: halfWidth, halfHeight: halfHeight, ruleY: ruleY)
        let second = HubDomainTitle.path(
            for: .mechanics, time: period * 1.1,
            halfWidth: halfWidth, halfHeight: halfHeight, ruleY: ruleY)
        XCTAssertEqual(first.x, -second.x, accuracy: 1e-3,
                       "the second crossing retraces the first instead of returning")
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

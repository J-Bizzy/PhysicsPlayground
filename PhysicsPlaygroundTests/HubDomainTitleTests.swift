//
//  HubDomainTitleTests.swift
//  Physics Playground — app tests
//
//  The signage over the two doors: the flush lockup, and the sign
//  speaking its name to VoiceOver.
//

import XCTest
import RealityKit
import simd
@testable import PhysicsPlayground

final class HubDomainTitleTests: XCTestCase {

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

    /// The rule overhangs the type — a bar the words rest on, not a
    /// shy dash trapped beneath them.
    @MainActor
    func testTheRuleOverhangsTheType() {
        XCTAssertGreaterThan(HubDomainTitle.ruleOverhang, 1)
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

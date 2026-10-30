//
//  AccessibilityWriteCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  What VoiceOver says about an object in the room is written in one
//  place, `SpatialActions.describe`, which edits the component it finds.
//  A fresh `AccessibilityComponent()` written after `attach` replaced the
//  advertised Activate with nothing: until 2026-10-27 ten objects across
//  seven labs were read out and could not be activated, with every
//  routing test green, because the routing tests performed the action
//  directly. A source scan, so the next renderer is caught too.
//

import XCTest

final class AccessibilityWriteCriterionTests: XCTestCase {

    private func sources() throws -> [(name: String, text: String)] {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let project = tests.deletingLastPathComponent()
        let roots = [project.appendingPathComponent("PhysicsPlayground"),
                     project.appendingPathComponent("Packages/RenderKit/Sources/RenderKit")]
        var found: [(name: String, text: String)] = []
        for root in roots {
            guard FileManager.default.fileExists(atPath: root.path) else {
                XCTFail("\(root.path) is not reachable; this check would read nothing")
                throw XCTSkip("source tree not reachable")
            }
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" } ?? []
            for file in files {
                if let text = try? String(contentsOf: file, encoding: .utf8) {
                    found.append((file.lastPathComponent, text))
                }
            }
        }
        return found
    }

    func testOnlyTheHelperMakesAnAccessibilityComponent() throws {
        let offenders = try sources()
            .filter { $0.name != "SpatialAction.swift" }
            .filter { $0.text.contains("AccessibilityComponent()") }
            .map(\.name)
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.sorted().joined(separator: ", ")) build a fresh \
            AccessibilityComponent. Use `SpatialActions.describe` for a label or \
            `SpatialActions.republish` for a value: a fresh component drops the \
            Activate an earlier `attach` advertised.
            """)
    }

    /// The scan must be reading the tree: the helper itself is in it.
    func testTheScanReadsTheHelper() throws {
        let all = try sources()
        let helper = all.first { $0.name == "SpatialAction.swift" }
        XCTAssertNotNil(helper, "the scan does not reach RenderKit")
        XCTAssertTrue(helper?.text.contains("AccessibilityComponent()") == true)
        XCTAssertGreaterThan(all.count, 100, "the scan is reading too few files to mean anything")
    }
}

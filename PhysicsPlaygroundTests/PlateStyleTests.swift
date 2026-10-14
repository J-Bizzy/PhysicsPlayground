//
//  PlateStyleTests.swift
//  PhysicsPlaygroundTests
//
//  The two banks share one plate silhouette by construction. Asserting
//  the constants would be vacuous; this reads the constructed plate
//  meshes.
//

import XCTest
import RealityKit
@testable import PhysicsPlayground

@MainActor
final class PlateStyleTests: XCTestCase {


    // MARK: The nameplate sizes

    /// `HubScene.namePlate` is asked for at a named size, never a
    /// hand-typed one: there were nine, each call site believing it matched
    /// the others. Two ship — arm's length and across the room; a third is
    /// a decision, not an accident.
    func testEveryNamePlateAsksForANamedSize() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PhysicsPlayground")

        var scanned = 0
        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            scanned += 1
            for (number, line) in text.split(separator: "\n",
                                             omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
                guard trimmed.contains("namePlate(") || trimmed.contains("namePlateWidth(")
                else { continue }
                // A literal size argument on a nameplate call.
                if let range = trimmed.range(of: #"size: 0\.\d+"#, options: .regularExpression) {
                    offenders.append(
                        "\(url.lastPathComponent):\(number + 1) — \(trimmed[range])")
                }
            }
        }

        // A floor against the tree moving under this test, not a count of it.
        XCTAssertGreaterThan(scanned, 50,
                             "walked \(scanned) files — the tree moved and this scans nothing")
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) nameplate(s) ask for a hand-typed size:

            \(offenders.joined(separator: "\n"))

            Use `PlateStyle.labelSize` (arm's length) or \
            `PlateStyle.exhibitLabelSize` (across the room). If neither fits, \
            add a third NAMED step with a sentence saying what distance it is \
            for — the nine sizes this closed were nine people each believing \
            they were following the convention.
            """)
    }
}

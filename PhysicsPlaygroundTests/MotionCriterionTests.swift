//
//  MotionCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  ONE EASE, SO REDUCE MOTION CANNOT BE FORGOTTEN AGAIN.
//
//  The setting reached two of eight animated primitives. `Fade` and
//  `PickupPulse` honoured it; `Bloom`, `SpatialPicker`, both banks,
//  `Well` and `FrozenVectors` did not — and the tell is in one file and
//  one frame, where the hub's terrace hairlines freeze mid-shimmer while
//  the door signs directly above them park correctly. Nobody decided
//  that. Each primitive hand-rolled `value += (target - value) * dt *
//  rate` on the day it was written, and whether the author happened to
//  remember was the whole mechanism.
//
//  A test that LISTED the eight would be that same act of attention, so
//  this one bans the shape instead: an exponential ease written by hand
//  anywhere in the design system or RenderKit fails the build, and
//  `Motion.ease` — which snaps when the setting is on — is the only way
//  to write one. Add a primitive tomorrow and it is covered tomorrow.
//
//  In the family of `PanelControlCriterionTests` (no `Slider` in a
//  module) and `MaterialCanonCriterionTests` (no hand-rolled glass).
//

import XCTest
@testable import PhysicsPlayground

final class MotionCriterionTests: XCTestCase {

    /// Files allowed to contain the raw ease, because they ARE it.
    private let exempt: Set<String> = ["Motion.swift", "Fade.swift"]

    /// Where an animated primitive can live.
    private var searchRoots: [URL] {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // PhysicsPlaygroundTests
            .deletingLastPathComponent()      // repo root
        return [
            here.appendingPathComponent("PhysicsPlayground/DesignSystem"),
            here.appendingPathComponent("Packages/RenderKit/Sources/RenderKit"),
        ]
    }

    private func swiftFiles(under root: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// `min(dt * <rate>, 1)` is the signature of a hand-rolled
    /// frame-rate-independent ease. It is exactly what the six
    /// non-conforming primitives each wrote for themselves.
    func testNoPrimitiveRollsItsOwnEase() throws {
        var offenders: [String] = []
        for root in searchRoots {
            for file in swiftFiles(under: root) where !exempt.contains(file.lastPathComponent) {
                let source = try String(contentsOf: file, encoding: .utf8)
                for (index, line) in source.split(separator: "\n",
                                                  omittingEmptySubsequences: false).enumerated() {
                    // Skip comments — this file's own prose describes the
                    // banned shape, and so do several of the fixes'.
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
                    if line.contains("min(dt *") || line.contains("min(Float(dt) *") {
                        offenders.append("\(file.lastPathComponent):\(index + 1): \(trimmed)")
                    }
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            """
            A hand-rolled ease. Use `Motion.ease(_:toward:dt:)`, which snaps \
            when the system Reduce Motion switch is on — that switch reached \
            two of eight animated primitives precisely because each of the \
            other six wrote this line for itself:

            \(offenders.joined(separator: "\n"))
            """)
    }

    /// The searcher has to be able to find something, or the test above
    /// passes by looking in an empty directory — which is how a
    /// criterion test quietly stops being one.
    func testTheSearchActuallyReachesTheSource() {
        for root in searchRoots {
            let files = swiftFiles(under: root)
            XCTAssertGreaterThan(files.count, 3,
                                 "found \(files.count) Swift files under \(root.path) — "
                                 + "this test is looking in the wrong place")
        }
    }
}

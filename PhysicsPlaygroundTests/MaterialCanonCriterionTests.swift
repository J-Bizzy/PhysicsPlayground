//
//  MaterialCanonCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  The material canon as an assertion: nothing under Modules, Hub,
//  DesignSystem or Shell constructs a `SimpleMaterial`. Reads the
//  source, because a material inside a built entity tree is not
//  reachable by reflection in any way that fails loudly.
//

import XCTest

final class MaterialCanonCriterionTests: XCTestCase {

    /// Every shipping surface, not just the modules: the two directories
    /// that define the canon and the gallery were once outside the only
    /// test enforcing it. Fails rather than skipping when the tree is
    /// unreachable, since every check below is a negative one.
    private func scanRoots() throws -> [URL] {
        let thisFile = URL(fileURLWithPath: #filePath)
        // …/PhysicsPlayground/PhysicsPlaygroundTests/ThisFile.swift
        let app = thisFile.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PhysicsPlayground")
        let roots = ["Modules", "Hub", "DesignSystem", "Shell"]
            .map { app.appendingPathComponent($0) }
        for root in roots {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path,
                                                 isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                XCTFail("""
                    \(root.lastPathComponent) is not reachable from \
                    \(thisFile.path), so every check in this file would pass \
                    without reading it. If the tree moved, fix this path — do \
                    not let it skip.
                    """)
                throw XCTSkip("source tree not reachable")
            }
        }
        return roots
    }

    /// Every Swift file under `PhysicsPlayground/Modules`. Deliberately
    /// Not `Archive/` — cut modules keep their physics outside the build
    /// and are not shipping surfaces.
    private func moduleSources() throws -> [URL] {
        try scanRoots().flatMap { root in
            FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" }
                // `Materials` is the canon, so it necessarily contains every recipe
                // the rest of the app is forbidden to hand-roll.
                .filter { $0.lastPathComponent != "Materials.swift" } ?? []
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The anchor: a suite of negative checks needs a positive one
    /// underneath it.
    func testTheSourceTreeIsActuallyBeingRead() throws {
        let sources = try moduleSources()
        let renderers = sources.filter { $0.lastPathComponent.hasSuffix("Renderer.swift") }
        XCTAssertGreaterThanOrEqual(
            renderers.count, 6,
            "expected a renderer per shipping module; found \(renderers.map(\.lastPathComponent))")

        let usesCanon = try sources.contains { source in
            try String(contentsOf: source, encoding: .utf8).contains("Materials.")
        }
        XCTAssertTrue(usesCanon,
                      "no module source calls `Materials.` — the canon has come unwired")
    }

    /// The criterion itself: the matte primitive does not ship.
    func testNoModuleConstructsTheMattePrimitive() throws {
        for source in try moduleSources() {
            let text = try String(contentsOf: source, encoding: .utf8)
            for (number, line) in text.split(separator: "\n",
                                             omittingEmptySubsequences: false)
                .enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
                XCTAssertFalse(
                    Self.contains(trimmed, identifier: "SimpleMaterial("),
                    """
                    \(source.lastPathComponent):\(number + 1) constructs a \
                    `SimpleMaterial`.

                    A physics object looks crafted in every module or like a \
                    matte primitive in one of them. Use the canon in \
                    `RenderKit.Materials` — `energized` for lit energy, \
                    `machined`/`graphite` for built things, `glossy` for \
                    display type, `frostedGlass` for instruments — or, if \
                    none fit, build a `PhysicallyBasedMaterial` whose values \
                    are a stated decision. A material judgement is a \
                    passthrough judgement: check it on device \
                    (docs/ON_DEVICE_TESTS.md).
                    """)
            }
        }
    }

    /// Matches a token only at an identifier boundary, so a type that
    /// merely ends in the name cannot false-positive.
    private static func contains(_ line: String, identifier token: String) -> Bool {
        var search = line[...]
        while let range = search.range(of: token) {
            let isBoundary: Bool
            if range.lowerBound == search.startIndex {
                isBoundary = true
            } else {
                let previous = search[search.index(before: range.lowerBound)]
                isBoundary = !(previous.isLetter || previous.isNumber || previous == "_")
            }
            if isBoundary { return true }
            search = search[range.upperBound...]
        }
        return false
    }
}

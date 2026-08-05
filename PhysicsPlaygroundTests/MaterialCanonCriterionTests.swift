//
//  MaterialCanonCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  The material canon, as an assertion rather than a promise.
//
//  `RenderKit.Materials` exists because every module that needed a
//  machined part used to fall back to `SimpleMaterial` with a hand-typed
//  grey — the "matte primitive" its own header names. The canon landed
//  on 2026-07-30, and the fallback pattern still survived it twice: the
//  Kinematics ball was caught on 2026-08-03 (DECISIONS.md names the
//  call-site tell), and six Circuits part bodies plus two texture-missing
//  fallbacks were caught on 2026-08-05. A recipe nobody is required to
//  use is a recipe the next part quietly skips, so the requirement is a
//  test now.
//
//  Reads the SOURCE, like `PanelControlCriterionTests`, and for the same
//  reason: a material inside a built entity tree is not reachable by
//  reflection in any way that would fail loudly. Reading the file is
//  crude, but it fails for the right reason and names the line.
//
//  The rule: nothing under `PhysicsPlayground/Modules` constructs a
//  `SimpleMaterial`. A part is `energized` (lit energy), `machined` or
//  `graphite` (built things), `glossy` (display type), `frostedGlass` /
//  `glassEdge` (instruments), `contrastLine` / `luminous` (lines and
//  self-lit surfaces) — or, where those genuinely do not fit, a
//  hand-built `PhysicallyBasedMaterial` / `UnlitMaterial` whose values
//  are the decision. What it may not be is the matte primitive the canon
//  was written to retire.
//

import XCTest

final class MaterialCanonCriterionTests: XCTestCase {

    /// Walks up from this file to the repository, then down to the
    /// modules — `#filePath` is the only anchor available. FAILS rather
    /// than skipping when the tree is unreachable: every check below is
    /// a negative one, and a negative assertion over a missing directory
    /// passes vacuously.
    private func moduleDirectory() throws -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        // …/PhysicsPlayground/PhysicsPlaygroundTests/ThisFile.swift
        let project = thisFile.deletingLastPathComponent()
            .deletingLastPathComponent()
        let modules = project
            .appendingPathComponent("PhysicsPlayground")
            .appendingPathComponent("Modules")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modules.path,
                                             isDirectory: &isDirectory),
              isDirectory.boolValue else {
            XCTFail("""
                The module source is not reachable from \(thisFile.path), so \
                every check in this file would pass without reading anything. \
                If the tree moved, fix this path — do not let it skip.
                """)
            throw XCTSkip("source tree not reachable")
        }
        return modules
    }

    /// Every Swift file under `PhysicsPlayground/Modules`. Deliberately
    /// NOT `Archive/` — cut modules keep their physics outside the build
    /// and are not shipping surfaces.
    private func moduleSources() throws -> [URL] {
        let modules = try moduleDirectory()
        return FileManager.default.enumerator(
            at: modules, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    /// The anchor. A suite of negative checks needs a positive one
    /// underneath it: the walk must actually reach the renderers, and
    /// the canon must actually be in use — otherwise an empty directory
    /// (or a canon nobody imports) would satisfy everything below.
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

//
//  SellingCopyCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  Deleting a feature is not done until nothing in the repository still
//  sells it. Scoped to the two selling surfaces, README.md and
//  docs/APP_STORE.md; DECISIONS.md and the device script legitimately
//  record removed features by name. A banned name reappearing means the
//  feature came back (delete its line) or the copy rotted (fix the copy).
//

import XCTest

final class SellingCopyCriterionTests: XCTestCase {

    /// Features removed from the app whose names must not appear in
    /// selling copy. Each entry names the removal date so a reader can
    /// find the DECISIONS.md story.
    private static let removedFeatures = [
        "Foucault",     // rig removed whole, physics included (2026-08-03)
        "Gauss",        // flux meter and bubble (2026-08-03; math stays in PhysicsCore)
        "positron",     // particle bank and electron/positron mode (2026-08-03)
        "-emGauss",     // the staging argument the old shot 3 used
        "-penFoucault", // the staging arguments the old shot 5 used
        "-penSpin",
        "next step",    // the experiments system's affordance (2026-08-09)
        "Notebook",     // the Lab Notebook, capture and CSV export (2026-10-14)
        "-notebookOpen", "-notebookSeed", // its staging arguments
        "best streak",  // the hoop streak, the last progress tracking (2026-10-14)
        "Electron View", // Circuits' 4× zoom floor (2026-10-14); the zoom and true speed stay
        "Physics box",  // folded into More (2026-10-14)
        "palette bead", // pause went to the title bar, the rest to More (2026-10-14)
        "Studio Mode", "-studioMode", // Deep space replaced it (2026-10-20)
        "particle animation", // the opening is a star system forming (2026-10-20)
    ]

    // Deliberately not on that list: "experiment" is ordinary English the
    // copy uses. Ban only names that can mean nothing but the dead feature.

    private func repositoryRoot() throws -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        // …/PhysicsPlayground/PhysicsPlaygroundTests/ThisFile.swift
        return thisFile.deletingLastPathComponent().deletingLastPathComponent()
    }

    func testTheSellingSurfacesSellOnlyWhatShips() throws {
        let root = try repositoryRoot()
        let surfaces = ["README.md", "docs/APP_STORE.md"]

        var scanned = 0
        for surface in surfaces {
            let url = root.appendingPathComponent(surface)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                XCTFail("""
                    \(surface) is not readable from \(root.path) — the \
                    selling surfaces moved, and this criterion is scanning \
                    nothing. Fix the path; do not let it skip.
                    """)
                continue
            }
            scanned += 1
            for (number, line) in text.split(separator: "\n",
                                             omittingEmptySubsequences: false)
                .enumerated() {
                for name in Self.removedFeatures where
                    line.range(of: name, options: .caseInsensitive) != nil {
                    XCTFail("""
                        \(surface):\(number + 1) still sells `\(name)`, \
                        which left the app. Deleting a feature is not done \
                        until nothing in the repository still sells it \
                        (DECISIONS.md, 2026-08-02). Fix the copy — or, if \
                        the feature returned, remove its entry from this \
                        test in the same commit.
                        """)
                }
            }
        }
        XCTAssertEqual(scanned, surfaces.count,
                       "a negative criterion over unread files passes vacuously")
    }

    /// Every App Store field with a limit — a `## Name (N max…)` heading
    /// over a fenced block — fits it. The description went to 4,049 of
    /// 4,000 with Light & Optics' paragraph (2026-10-14) under a hand count
    /// that still said 3,689, and App Store Connect is where it would have
    /// been found.
    func testEveryListingFieldFitsItsLimit() throws {
        let url = try repositoryRoot().appendingPathComponent("docs/APP_STORE.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        let limit = try Regex(#"^## [^\n]*\((\d+) max"#).anchorsMatchLineEndings()

        var measured = 0
        for match in text.matches(of: limit) {
            guard let max = Int(match.output[1].substring ?? ""),
                  let open = text.range(of: "```\n", range: match.range.upperBound..<text.endIndex),
                  let close = text.range(of: "\n```", range: open.upperBound..<text.endIndex)
            else {
                XCTFail("\(match.output[0].substring ?? "") has no fenced value under it")
                continue
            }
            let field = text[open.upperBound..<close.lowerBound]
            XCTAssertLessThanOrEqual(field.count, max,
                                     "\(match.output[0].substring ?? "") is \(field.count) characters")
            measured += 1
        }
        // Name, subtitle, promotional text, keywords, description.
        XCTAssertEqual(measured, 5, "the headings moved, and this is measuring the wrong fields")
    }
}

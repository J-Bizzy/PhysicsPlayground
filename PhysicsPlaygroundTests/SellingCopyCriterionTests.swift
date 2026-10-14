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
}

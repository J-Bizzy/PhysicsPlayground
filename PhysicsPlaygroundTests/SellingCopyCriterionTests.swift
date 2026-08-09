//
//  SellingCopyCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  "Deleting a feature is not done until nothing in the repository
//  still sells it" (DECISIONS.md, 2026-08-02 — learned when six places
//  went on promising five-pendulum resonance the day after its function
//  was deleted). The 2026-08-03 removals repeated the pattern: the
//  README and the App Store copy sold the Foucault rig, the Gauss flux
//  surface and the positron test particle for two days after all three
//  left the app, including two screenshot slots staged with launch
//  arguments that no longer exist.
//
//  So the rule becomes a test, in the house style: it closes the CLASS.
//  Scope is exactly the two SELLING surfaces — README.md and
//  docs/APP_STORE.md. DECISIONS.md, ON_DEVICE_TESTS.md and the git
//  history legitimately record removed features by name and are
//  deliberately NOT scanned; history is where those names belong.
//
//  If a banned name reappears here it is one of two things: the feature
//  came back (delete its line below, in the same commit), or the copy
//  rotted again (fix the copy). Either way the build says so.
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
    ]

    // WHAT IS DELIBERATELY *NOT* ON THAT LIST, and why — because the
    // obvious next entries are both wrong, and the next person to audit
    // this file will reach for them (2026-08-09).
    //
    // "experiment" — the experiments SYSTEM was deleted, but the word is
    // ordinary English and the copy uses it that way ("nothing in it is
    // an experiment"). Matching is case-insensitive, so banning the
    // feature's name also bans the noun. A criterion that fails on fair
    // copy gets weakened by whoever hits it next, and a weakened
    // criterion is worse than none.
    //
    // "streak" — NOT a removed feature. The projectile hoop streak is
    // live (`KinematicsModel.streak`). Banning it would forbid selling
    // something that ships. The experiments system had a streak too, and
    // the collision of names is the whole trap.
    //
    // The rule this leaves: ban names that can only mean the dead
    // feature. "next step" qualifies; a common noun never does.

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

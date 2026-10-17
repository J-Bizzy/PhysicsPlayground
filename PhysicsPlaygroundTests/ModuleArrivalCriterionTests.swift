//
//  ModuleArrivalCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  Every lab arrives and departs through `Fade.tick` on
//  `AppModel.isDeparting`. A text criterion rather than a reflective
//  one: `makeScene()` hands back an `AnyView`, so a scene cannot be
//  rendered offscreen in a unit test; reading the source can see whether
//  a SpaceView that adds a renderer root also fades it.
//

import XCTest
@testable import PhysicsPlayground

final class ModuleArrivalCriterionTests: XCTestCase {

    /// Walks up from this file to the repo, then into the modules.
    private func moduleSpaceViews() throws -> [(name: String, source: String)] {
        let here = URL(fileURLWithPath: #filePath)          // …/PhysicsPlaygroundTests/…
        let modules = here
            .deletingLastPathComponent()                     // PhysicsPlaygroundTests
            .deletingLastPathComponent()                     // repo root
            .appendingPathComponent("PhysicsPlayground")
            .appendingPathComponent("Modules")

        let files = FileManager.default.enumerator(
            at: modules, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.lastPathComponent.hasSuffix("SpaceView.swift") } ?? []

        return try files
            .map { (name: $0.lastPathComponent, source: try String(contentsOf: $0, encoding: .utf8)) }
            .sorted { $0.name < $1.name }
    }

    /// The guard: if this finds nothing, everything below is vacuously true.
    func testTheSearchActuallyReachesTheSource() throws {
        let views = try moduleSpaceViews()
        XCTAssertEqual(views.count, 7,
                       "expected seven module SpaceViews, found \(views.map(\.name))")
    }

    /// The criterion. Add a module tomorrow and it is covered tomorrow.
    func testEverySceneThatAddsARootAlsoFadesIt() throws {
        for view in try moduleSpaceViews() {
            guard view.source.contains("content.add(renderer.root)") else { continue }

            XCTAssertTrue(
                view.source.contains("Fade.tick(renderer.root"),
                """
                \(view.name) adds a renderer root but never fades it, so this \
                lab appears and vanishes in a single frame while the other five \
                arrive and depart. Add, in the SceneEvents.Update closure:
                    Fade.tick(renderer.root, visible: !appModel.isDeparting,
                              duration: AppModel.departure)
                """)

            XCTAssertTrue(
                view.source.contains("renderer.root.isEnabled = false"),
                """
                \(view.name) fades its root but does not start it disabled, so \
                the apparatus is visible at full opacity for the frames before \
                the first tick — which is the hard cut it was meant to remove.
                """)
        }
    }

    /// The fade must ride the shell's flag. A module inventing its own
    /// would drift out of step with the room's dimming ramp and with the
    /// other five.
    func testTheFadeRidesTheSharedDepartureFlag() throws {
        for view in try moduleSpaceViews() {
            guard view.source.contains("Fade.tick(renderer.root") else { continue }
            XCTAssertTrue(
                view.source.contains("visible: !appModel.isDeparting"),
                "\(view.name) fades on something other than AppModel.isDeparting")
        }
    }
}

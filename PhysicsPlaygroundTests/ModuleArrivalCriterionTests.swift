//
//  ModuleArrivalCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  EVERY LAB ARRIVES AND DEPARTS, and none of them has to remember to.
//
//  Until 2026-08-23 changing the active module flipped a SwiftUI branch and
//  the apparatus was simply there, between one frame and the next. Six
//  scenes now ride `AppModel.isDeparting` through `Fade.tick`. A listing
//  test naming the six would be the same act of attention that forgets the
//  seventh, so this bans the SHAPE instead: a SpaceView that adds a
//  renderer root must also fade it.
//
//  WHY A TEXT CRITERION rather than a reflective one. `makeScene()` hands
//  back an `AnyView`, and there is no honest way to render a module
//  offscreen in a unit test and reach its root entity — so reflection
//  cannot see whether a scene fades. Reading the source can. In the family
//  of `MotionCriterionTests` (no hand-rolled ease), `PanelControlCriterionTests`
//  (no Slider in a module) and `MaterialCanonCriterionTests` (no hand-rolled
//  glass).
//
//  `testTheSearchActuallyReachesTheSource` is not ceremony. A criterion
//  test that quietly starts looking in an empty directory passes forever
//  and means nothing, and `MotionCriterionTests` carries the same guard for
//  the same reason.
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
            .map { (name: $0.lastPathComponent, source: try String(contentsOf: $0)) }
            .sorted { $0.name < $1.name }
    }

    /// The guard: if this finds nothing, everything below is vacuously true.
    func testTheSearchActuallyReachesTheSource() throws {
        let views = try moduleSpaceViews()
        XCTAssertEqual(views.count, 6,
                       "expected six module SpaceViews, found \(views.map(\.name))")
    }

    /// THE CRITERION. Add a module tomorrow and it is covered tomorrow.
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

    /// The fade must ride the SHELL's flag. A module inventing its own
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

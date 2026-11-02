//
//  ModuleArrivalCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  Every lab arrives and departs through the shell's door,
//  `AppModel.doorTick` (2026-11-02; `Fade.tick` on `isDeparting` until
//  then), and stands where its own placement says. A text criterion rather than a reflective
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
                view.source.contains("appModel.doorTick(renderer.root"),
                """
                \(view.name) adds a renderer root but never passes it through the \
                door, so this lab appears and vanishes in a single frame, and \
                the scene it replaces never learns that it has settled. Add, in \
                the SceneEvents.Update closure:
                    appModel.doorTick(renderer.root, lab: <Module>.id,
                                      settled: settle.tick(dt: event.deltaTime))
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

    /// No lab fades its root on a flag of its own: one inventing its own
    /// would drift out of step with the door and with the other six.
    func testNoLabFadesItsRootOutsideTheDoor() throws {
        for view in try moduleSpaceViews() {
            XCTAssertFalse(
                view.source.contains("Fade.tick(renderer.root"),
                "\(view.name) fades its root itself, outside AppModel.doorTick")
        }
    }

    /// A lab on its way out holds where it stood while the next one adopts
    /// its own placement: the offset is read through the door, never
    /// straight off `labPlacement`, which by then is the next lab's.
    func testALeavingLabKeepsItsOwnPlacement() throws {
        for view in try moduleSpaceViews() {
            XCTAssertFalse(
                view.source.contains("root.position = appModel.labPlacement.offset"),
                "\(view.name) follows the next lab's placement while it leaves")
        }
    }
}

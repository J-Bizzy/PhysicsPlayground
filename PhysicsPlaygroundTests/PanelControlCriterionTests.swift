//
//  PanelControlCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  The exit criterion, as an assertion rather than a promise.
//
//  It used to say: no `Slider`, `Picker` or `Toggle` in a module panel
//  (DECISIONS.md, 2026-07-29). All six modules met that on 2026-08-01,
//  and what the panels held afterwards was 71 readout `Text`s, 13
//  buttons — six of them duplicating a control already standing in the
//  room — and four collapsed cards whose entire content was prose
//  explaining where a control had gone.
//
//  So the criterion is stronger now: **no module has a panel at all.**
//  `ModuleDescriptor.makeControls` is deleted, the module window is a
//  title bar, and every control and readout stands on the apparatus.
//
//  This test exists because this specific boundary has already been
//  re-litigated once, in a full round trip: `Phase 0 — demolition: the
//  glass comes out` → `the object is the interface` → `dials live on the
//  apparatus now` → … → `the controls come back` → `Every module gets its
//  one-glance panel`. 212 commits, and it ended on the wrong side. A
//  criterion nobody can re-check is one that silently regresses, and the
//  cost of re-crossing this line is measured in months.
//
//  It reads the SOURCE, which is unusual and deliberate. The alternative
//  — instantiating each panel and walking its view tree — cannot work:
//  SwiftUI's `body` is opaque, a `Slider` nested in a card is not
//  reachable by reflection, and a test that silently inspected nothing
//  would be worse than no test at all. Reading the file is crude, but it
//  fails loudly and for the right reason.
//
//  DECISIONS.md, 2026-08-01, states the cost this guards rather than
//  glossing it: the app now has NO flat control surface, so a regression
//  in a spatial instrument has no fallback path. That is the trade. This
//  file is what stops it being unmade by accident.
//

import XCTest

final class PanelControlCriterionTests: XCTestCase {

    /// Walks up from this file to the repository, then down to the
    /// modules. `#filePath` is the only anchor available — the test
    /// bundle's own resources do not include source.
    ///
    /// It FAILS rather than skipping when the tree is unreachable, and
    /// that changed with the rewrite. Every assertion below is now a
    /// NEGATIVE one ("no module ships a panel"), and a negative
    /// assertion over a directory that does not exist passes vacuously —
    /// so the old `XCTSkip` would have meant this criterion quietly
    /// stopped being checked in exactly the environments where nobody
    /// was watching.
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

    /// Every Swift file under `PhysicsPlayground/Modules`.
    ///
    /// Deliberately NOT `Archive/`, which sits at the repository root
    /// outside the build and still holds two parked `*ControlsPanel.swift`
    /// files. Those are cut modules keeping their tested physics; they
    /// are not shipping surfaces.
    private func moduleSources() throws -> [URL] {
        let modules = try moduleDirectory()
        return FileManager.default.enumerator(
            at: modules, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    /// The anchor, and the reason the rest of this file means anything.
    ///
    /// Without it, deleting `Modules/` outright — or pointing the walk
    /// at an empty directory — would satisfy every other assertion here.
    /// A suite of negative checks needs one positive one underneath it.
    func testTheSourceTreeIsActuallyBeingRead() throws {
        let sources = try moduleSources()
        let modules = sources.filter { $0.lastPathComponent.hasSuffix("Module.swift") }
        let scenes = sources.filter { $0.lastPathComponent.hasSuffix("SpaceView.swift") }

        XCTAssertEqual(modules.count, 6,
                       "expected six module descriptors; found \(modules.map(\.lastPathComponent))")
        XCTAssertGreaterThanOrEqual(
            scenes.count, 6,
            "expected a scene per module; found \(scenes.map(\.lastPathComponent))")
    }

    /// The criterion itself.
    func testNoModuleShipsAFlatControlSurface() throws {
        let panels = try moduleSources()
            .filter { $0.lastPathComponent.hasSuffix("ControlsPanel.swift") }

        XCTAssertTrue(panels.isEmpty, """
            \(panels.map(\.lastPathComponent)) is a flat control surface \
            inside a module.

            The module window is a TITLE BAR — plus "Show in room" while \
            the space is closed, and the first-run hint for as long as it \
            stays closed. Nothing else (DECISIONS.md, 2026-08-01).

            The teach is not an exception. It moved into the room on \
            2026-08-08 and was deleted on 2026-08-09, along with \
            Circuits' insight card: a paragraph in front of the bench \
            covers the thing it describes, which is the failure a \
            paragraph BEHIND the bench had a day earlier. Three cards of \
            words rejected in three days. The apparatus explains itself.

            A control belongs on the apparatus: a SpatialLayerBank plate \
            for a latching state, a SpatialActionBank plate for a standing \
            verb, a SpatialPicker disc for a choice, a SpatialTrackControl \
            rail for a quantity, a Well to create with, a Bloom petal or \
            grip for something that belongs to one object. A readout \
            belongs on the thing it measures: a Callout for one line, a \
            RealityView attachment for a card.
            """)
    }

    /// Nothing inside a module builds a panel, a flat control, or offers
    /// one to the shell.
    func testNoModuleSourceBuildsAPanelOrAFlatControl() throws {
        // Constructor call sites and the contract's own name. The words
        // appear in these files' prose constantly — most of them in
        // comments explaining why the controls left — so comment lines
        // are skipped, exactly as they always were.
        let banned = ["Slider(", "Picker(", "Toggle(",
                      "PanelSection(", "CollapsedSection(", "makeControls"]

        for source in try moduleSources() {
            let text = try String(contentsOf: source, encoding: .utf8)
            for (number, line) in text.split(separator: "\n",
                                             omittingEmptySubsequences: false)
                .enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
                for token in banned where Self.contains(trimmed, identifier: token) {
                    XCTFail("""
                        \(source.lastPathComponent):\(number + 1) holds `\(token)`.

                        \(Self.law)
                        """)
                }
            }
        }
    }

    /// The contract itself: the shell can no longer be handed a panel.
    func testTheModuleContractHasNoControlFactory() throws {
        let shell = try moduleDirectory()
            .deletingLastPathComponent()
            .appendingPathComponent("Shell")
        for name in ["ModuleDescriptor.swift", "ModuleHostView.swift"] {
            let file = shell.appendingPathComponent(name)
            let text = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in text.split(separator: "\n",
                                             omittingEmptySubsequences: false)
                .enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
                XCTAssertFalse(
                    trimmed.contains("makeControls"),
                    """
                    \(name):\(number + 1) mentions `makeControls` outside a \
                    comment. The module contract has one view factory — \
                    `makeScene`. \(Self.law)
                    """)
            }
        }
    }

    /// Matches a token only at an identifier boundary.
    ///
    /// `SpatialPicker(` CONTAINS `Picker(`, and six space views construct
    /// one — they are the very instruments this law demands. A bare
    /// `contains` fails on the code that satisfies the rule, which is the
    /// worst possible false positive: it teaches people to delete the
    /// check rather than the violation.
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

    private static let law = """
        The interaction law (DECISIONS.md, 2026-07-29, narrowed 2026-08-01): \
        a quantity with physical extent is changed by changing that extent; \
        a quantity without extent is a discrete choice and gets a labelled \
        object in the room; a one-shot verb is a plate. A module has no flat \
        control surface at all.

        Resolve this as exactly one of three, and say which in the commit: \
        (1) it becomes an instrument in the room; (2) it becomes a readout \
        on the thing it measures; (3) it is deleted as chrome.

        And if it becomes a plate: check `reset()` restores the flag behind \
        it. Four modules had that defect.
        """
}

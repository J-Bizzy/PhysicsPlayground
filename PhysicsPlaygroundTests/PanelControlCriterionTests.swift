//
//  PanelControlCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  No module has a panel at all: `makeControls` is deleted, the module
//  window is a title bar, and every control and readout stands on the
//  apparatus. Reads the source, because SwiftUI's `body` is opaque and a
//  test that silently inspected nothing would be worse than none. The
//  cost this guards: there is no flat fallback surface for a spatial
//  instrument that regresses.
//

import XCTest

final class PanelControlCriterionTests: XCTestCase {

    /// Walks up from this file to the repository, then down to the modules.
    /// Fails rather than skipping when the tree is unreachable: every
    /// assertion below is negative and would pass vacuously.
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

    /// Every Swift file under `PhysicsPlayground/Modules`. Not `Archive/`:
    /// cut modules keeping their tested physics are not shipping surfaces.
    private func moduleSources() throws -> [URL] {
        let modules = try moduleDirectory()
        return FileManager.default.enumerator(
            at: modules, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    /// The anchor: a suite of negative checks needs one positive one
    /// underneath it.
    func testTheSourceTreeIsActuallyBeingRead() throws {
        let sources = try moduleSources()
        let modules = sources.filter { $0.lastPathComponent.hasSuffix("Module.swift") }
        let scenes = sources.filter { $0.lastPathComponent.hasSuffix("SpaceView.swift") }

        XCTAssertEqual(modules.count, 7,
                       "expected seven module descriptors; found \(modules.map(\.lastPathComponent))")
        XCTAssertGreaterThanOrEqual(
            scenes.count, 7,
            "expected a scene per module; found \(scenes.map(\.lastPathComponent))")
    }

    /// The criterion itself.
    func testNoModuleShipsAFlatControlSurface() throws {
        let panels = try moduleSources()
            .filter { $0.lastPathComponent.hasSuffix("ControlsPanel.swift") }

        XCTAssertTrue(panels.isEmpty, """
            \(panels.map(\.lastPathComponent)) is a flat control surface \
            inside a module.

            The module window is a TITLE BAR — plus "Show in Room" while \
            the space is closed, and the first-run hint for as long as it \
            stays closed. Nothing else (DECISIONS.md, 2026-08-01).

            The teach is not an exception. It moved into the room on \
            2026-08-08 and was deleted on 2026-08-09, along with \
            Circuits' insight card: a paragraph in front of the bench \
            covers the thing it describes, which is the failure a \
            paragraph BEHIND the bench had a day earlier. Three cards of \
            words rejected in three days. The apparatus explains itself.

            A control belongs on the apparatus — a Well to create with, a \
            Bloom petal or grip for something that belongs to one object, \
            a SpatialPicker disc for a choice — or behind the title bar's \
            More, the one panel, for everything secondary. A readout \
            belongs on the thing it measures: a Callout for one line, a \
            RealityView attachment for a card.
            """)
    }

    /// Nothing inside a module builds a panel, a flat control, or offers
    /// one to the shell.
    func testNoModuleSourceBuildsAPanelOrAFlatControl() throws {
        // Constructor call sites and the contract's own name. Comment lines
        // are skipped: the words appear in prose constantly.
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

    /// Matches a token only at an identifier boundary: `SpatialPicker(`
    /// contains `Picker(`, and the picker is the very instrument this law
    /// demands.
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

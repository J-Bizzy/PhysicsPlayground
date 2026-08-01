//
//  PanelControlCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  The exit criterion, as an assertion rather than a promise.
//
//  DECISIONS.md, 2026-07-29: "No `Slider`, `Picker` or `Toggle` in any
//  module panel. The panel survives as a readout surface." As of
//  2026-08-01 all six modules meet it.
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
//  SwiftUI's `body` is opaque, a `Slider` nested in a `CollapsedSection`
//  is not reachable by reflection, and a test that silently inspected
//  nothing would be worse than no test at all. Reading the file is
//  crude, but it fails loudly and for the right reason.
//

import XCTest

final class PanelControlCriterionTests: XCTestCase {

    /// Walks up from this file to the repository, then down to the
    /// modules. `#filePath` is the only anchor available — the test
    /// bundle's own resources do not include source.
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
            throw XCTSkip("source tree not reachable from \(thisFile.path)")
        }
        return modules
    }

    /// Every `*ControlsPanel.swift`, so a module that adds one is covered
    /// without anyone remembering to list it here.
    private func panelSources() throws -> [URL] {
        let modules = try moduleDirectory()
        let all = FileManager.default.enumerator(
            at: modules, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.lastPathComponent.hasSuffix("ControlsPanel.swift") }
            ?? []
        return all.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func testNoModulePanelHoldsASliderPickerOrToggle() throws {
        let panels = try panelSources()
        XCTAssertGreaterThanOrEqual(
            panels.count, 6,
            "expected a panel per module; found \(panels.map(\.lastPathComponent))")

        // Constructor call sites only. The words appear in these files'
        // prose constantly — most of them in comments explaining why the
        // controls left — so matching bare names would fail on the very
        // documentation that records the decision.
        let banned = ["Slider(", "Picker(", "Toggle("]

        for panel in panels {
            let source = try String(contentsOf: panel, encoding: .utf8)
            for (number, line) in source.split(separator: "\n",
                                               omittingEmptySubsequences: false)
                .enumerated() {
                let text = line.trimmingCharacters(in: .whitespaces)
                // Comments are where the reasoning lives; skip them.
                guard !text.hasPrefix("//"), !text.hasPrefix("///") else { continue }
                for token in banned where text.contains(token) {
                    XCTFail("""
                        \(panel.lastPathComponent):\(number + 1) holds `\(token)`.

                        The interaction law (DECISIONS.md, 2026-07-29): a \
                        quantity with physical extent is changed by changing \
                        that extent; a quantity without extent is a discrete \
                        choice and gets a labelled object in the room. A \
                        module panel is a READOUT surface.

                        Resolve this control as exactly one of three, and say \
                        which in the commit: (1) it becomes an instrument — a \
                        SpatialLayerBank plate, a SpatialTrackControl rail, a \
                        SpatialPicker disc, a Well, or a Bloom grip; (2) it \
                        becomes a readout; (3) it is deleted as chrome.

                        And if it becomes a plate: check `reset()` restores \
                        the flag behind it. Four modules had that defect.
                        """)
                }
            }
        }
    }
}

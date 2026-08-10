//
//  PlateStyleTests.swift
//  PhysicsPlaygroundTests
//
//  The two banks share one plate silhouette by construction now
//  (`PlateStyle`, 2026-08-05) — the corner radius was deliberately
//  matched from the start, but the depths had drifted (0.007 vs 0.009
//  thick) because each file typed its own numbers on a different day.
//  Asserting `PlateStyle.depth == 0.009` would be vacuous; what matters
//  is what the banks BUILD, so this reads the constructed plate meshes
//  — the scene graph, not the constants they were supposed to come from.
//

import XCTest
import RealityKit
@testable import PhysicsPlayground

@MainActor
final class PlateStyleTests: XCTestCase {

    func testBothBanksBuildTheSamePlateSilhouette() throws {
        let layerBank = SpatialLayerBank(
            accent: .white,
            layers: [LayerSwitch(id: "grid", label: "Grid",
                                 isOn: { true }, toggle: {})])
        let actionBank = SpatialActionBank(
            accent: .white,
            actions: [.init(id: "clear", label: "Clear", symbol: "trash.slash",
                            isAvailable: { true }, confirms: false, fire: {})])
        for _ in 0..<40 {
            layerBank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1.0 / 90.0)
            actionBank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1.0 / 90.0)
        }

        let layerPlate = try XCTUnwrap(
            layerBank.root.children.first { $0.name == "layer-grid" } as? ModelEntity)
        let actionPlate = try XCTUnwrap(
            actionBank.root.children.first { $0.name == "action-clear" } as? ModelEntity)

        let layerExtents = try XCTUnwrap(layerPlate.model).mesh.bounds.extents
        let actionExtents = try XCTUnwrap(actionPlate.model).mesh.bounds.extents

        XCTAssertEqual(layerExtents.x, actionExtents.x, accuracy: 1e-5,
                       "the two banks' plates differ in width")
        XCTAssertEqual(layerExtents.y, actionExtents.y, accuracy: 1e-5,
                       "the two banks' plates differ in height")
        XCTAssertEqual(layerExtents.z, actionExtents.z, accuracy: 1e-5,
                       "the two banks' plates differ in thickness — the exact "
                       + "drift PlateStyle exists to close")
    }

    // MARK: The nameplate sizes (2026-08-09)

    /// `HubScene.namePlate` is asked for at a NAMED size, never a
    /// hand-typed one.
    ///
    /// There were nine — 0.009, 0.010, 0.0104, 0.0108, 0.011, 0.012,
    /// 0.0132, 0.014 and 0.030 — for one primitive. What makes it worth
    /// a criterion rather than a one-off tidy is how it happened: every
    /// call site's comment claimed to be following the house treatment
    /// ("the house nameplate, small", "the same treatment the palette
    /// bead wears"). Nine authors each believed they were matching the
    /// others, and each typed a different number. Nothing about that is
    /// self-correcting, so the next one would have been a tenth.
    ///
    /// Two steps ship: `PlateStyle.labelSize` for something at arm's
    /// length, `PlateStyle.exhibitLabelSize` for something across the
    /// room. A third is a decision, not an accident — add it here.
    func testEveryNamePlateAsksForANamedSize() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PhysicsPlayground")

        var scanned = 0
        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            scanned += 1
            for (number, line) in text.split(separator: "\n",
                                             omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
                guard trimmed.contains("namePlate(") || trimmed.contains("namePlateWidth(")
                else { continue }
                // A literal size argument on a nameplate call.
                if let range = trimmed.range(of: #"size: 0\.\d+"#, options: .regularExpression) {
                    offenders.append(
                        "\(url.lastPathComponent):\(number + 1) — \(trimmed[range])")
                }
            }
        }

        // The app source is ~77 files. The bar is a floor against the
        // tree moving under this test, not a count of it — set at 100
        // on the first draft, which failed on a codebase that was fine.
        XCTAssertGreaterThan(scanned, 50,
                             "walked \(scanned) files — the tree moved and this scans nothing")
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) nameplate(s) ask for a hand-typed size:

            \(offenders.joined(separator: "\n"))

            Use `PlateStyle.labelSize` (arm's length) or \
            `PlateStyle.exhibitLabelSize` (across the room). If neither fits, \
            add a third NAMED step with a sentence saying what distance it is \
            for — the nine sizes this closed were nine people each believing \
            they were following the convention.
            """)
    }
}

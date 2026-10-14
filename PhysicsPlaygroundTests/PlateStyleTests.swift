//
//  PlateStyleTests.swift
//  PhysicsPlaygroundTests
//
//  The two banks share one plate silhouette by construction. Asserting
//  the constants would be vacuous; this reads the constructed plate
//  meshes.
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

    // MARK: The nameplate sizes

    /// `HubScene.namePlate` is asked for at a named size, never a
    /// hand-typed one: there were nine, each call site believing it matched
    /// the others. Two ship — arm's length and across the room; a third is
    /// a decision, not an accident.
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

        // A floor against the tree moving under this test, not a count of it.
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

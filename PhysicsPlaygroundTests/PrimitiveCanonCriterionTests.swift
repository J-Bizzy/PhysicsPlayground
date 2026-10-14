//
//  PrimitiveCanonCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  Every primitive mesh and collider comes from `Primitives`, and every
//  flat colour from `Materials.unlit`: RealityKit builds a fresh resource
//  per `generate*` call and per material, each a round trip that blocks
//  the main thread, and a lab entry once paid for a thousand of them.
//  Enforced by a source scan so the next renderer cannot drift back.
//

import XCTest

final class PrimitiveCanonCriterionTests: XCTestCase {

    private static let banned = [
        ".generateSphere(", ".generateBox(", ".generatePlane(",
        ".generateCylinder(", ".generateCone(", ".generateCapsule(",
    ]

    private func sources() throws -> [URL] {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let project = tests.deletingLastPathComponent()
        let roots = [project.appendingPathComponent("PhysicsPlayground"),
                     project.appendingPathComponent("Packages/RenderKit/Sources/RenderKit")]
        var files: [URL] = []
        for root in roots {
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                if url.pathExtension == "swift" { files.append(url) }
            }
        }
        XCTAssertGreaterThan(files.count, 50, "the scan walked nothing")
        return files
    }

    func testEveryPrimitiveComesFromTheCache() throws {
        for file in try sources() where file.lastPathComponent != "Primitives.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                for token in Self.banned where trimmed.contains(token) {
                    XCTFail("\(file.lastPathComponent):\(number + 1) calls `\(token)` directly; use `Primitives`.")
                }
            }
        }
    }

    /// A flat colour with an opacity is `Materials.unlit`. The bare
    /// `UnlitMaterial(color:)` survives only where the material is then
    /// given a texture or a per-frame colour — a recipe cannot cache those.
    func testFlatColoursComeFromTheRecipe() throws {
        for file in try sources() where file.lastPathComponent != "Materials.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (number, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), trimmed.contains("= UnlitMaterial(color:") else { continue }
                // The next line setting only blending is the pattern the recipe replaces.
                let next = number + 1 < lines.count ? lines[number + 1].trimmingCharacters(in: .whitespaces) : ""
                if next.hasPrefix(String(trimmed.split(separator: " ")[1])) && next.contains(".blending = .transparent(opacity:") {
                    XCTFail("\(file.lastPathComponent):\(number + 1) builds a flat colour by hand; use `Materials.unlit(_:opacity:)`.")
                }
            }
        }
    }
}

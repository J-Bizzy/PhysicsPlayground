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

    /// A sphere names its facets. `Primitives.sphere(radius:)` is
    /// `generateSphere`, about 8 000 triangles at any size, and a bead, a
    /// dot or a bob drawn by the hundred was most of what three labs and the
    /// home drew (2026-11-06: a swinging cradle 814 000 triangles, the home
    /// 608 000). The one dome that needs the smoothness names itself here.
    func testEverySphereNamesItsFacets() throws {
        let allowed: Set<String> = ["Primitives.swift", "RoomDimmer.swift"]
        for file in try sources() where !allowed.contains(file.lastPathComponent) {
            let text = try String(contentsOf: file, encoding: .utf8)
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (number, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"),
                      let start = trimmed.range(of: "Primitives.sphere(radius:") else { continue }
                // The call's own argument list, which may run onto the next lines.
                let window = trimmed[start.lowerBound...]
                    + lines[(number + 1)..<min(number + 3, lines.count)].joined(separator: " ")
                var depth = 0
                var call = ""
                for character in window {
                    call.append(character)
                    if character == "(" { depth += 1 }
                    if character == ")" { depth -= 1; if depth == 0 { break } }
                }
                if !call.contains("segments:") {
                    XCTFail("\(file.lastPathComponent):\(number + 1) draws an 8 000-triangle sphere; pass `segments:`.")
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

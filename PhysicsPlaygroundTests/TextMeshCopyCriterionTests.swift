//
//  TextMeshCopyCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  A text mesh has no markup; it draws what you typed. Every authored
//  paragraph lands on a mesh, and the Lagrange callout once rendered
//  its asterisks. Comments are skipped: the rule is about strings that
//  reach a reader.
//

import XCTest

final class TextMeshCopyCriterionTests: XCTestCase {

    /// Markup a mesh renders literally. Each is paired with what to do
    /// instead, because the fix is never "escape it".
    private static let markup: [(pattern: String, instead: String)] = [
        (#"\*\*[^*\n]{2,}\*\*"#, "bold — say it in words, or use capitals as the rest of this app does"),
        (#"(?<![\w*])\*[^*\n]{2,}\*(?![\w*])"#, "emphasis — rephrase so the sentence carries the stress"),
        (#"`[^`\n]{2,}`"#, "code voice — a reader in a headset has no code voice to hear"),
    ]

    private func swiftSources() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PhysicsPlaygroundTests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("PhysicsPlayground")
        var found: [URL] = []
        let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            if url.pathExtension == "swift" { found.append(url) }
        }
        return found
    }

    /// Strips comments, leaving code. Crude on purpose: a `//` inside a
    /// string costs a skipped line, a false negative.
    private func codeLines(of source: String) -> [(Int, String)] {
        var inBlock = false
        var out: [(Int, String)] = []
        for (i, raw) in source.components(separatedBy: "\n").enumerated() {
            var line = raw
            if inBlock {
                guard let end = line.range(of: "*/") else { continue }
                line = String(line[end.upperBound...])
                inBlock = false
            }
            if let start = line.range(of: "/*") {
                inBlock = line.range(of: "*/", range: start.upperBound..<line.endIndex) == nil
                line = String(line[..<start.lowerBound])
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { continue }
            if let slashes = line.range(of: "//") {
                line = String(line[..<slashes.lowerBound])
            }
            guard line.contains("\"") else { continue }
            out.append((i + 1, line))
        }
        return out
    }

    func testNoAuthoredStringCarriesMarkupAMeshWouldDraw() throws {
        var offences: [String] = []
        var scanned = 0
        var linesWithStrings = 0
        let files = try swiftSources()
        // A floor, because a scan that walks nothing passes.
        XCTAssertGreaterThan(files.count, 60, """
            the walk found \(files.count) Swift files under \
            PhysicsPlayground/. There were 80 on 2026-08-08, so the \
            enumerator is not reaching the tree and this test is \
            asserting about nothing.
            """)
        for file in files {
            scanned += 1
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (number, line) in codeLines(of: text) {
                linesWithStrings += 1
                for (pattern, instead) in Self.markup {
                    guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                    let range = NSRange(line.startIndex..., in: line)
                    guard let hit = regex.firstMatch(in: line, range: range),
                          let span = Range(hit.range, in: line) else { continue }
                    offences.append("""
                        \(file.lastPathComponent):\(number) — "\(line[span])" \
                        (\(instead))
                        """)
                }
            }
        }
        XCTAssertGreaterThan(linesWithStrings, 800, """
            only \(linesWithStrings) code lines with string literals across \
            \(scanned) files — there were 1161 on 2026-08-08, so the \
            comment stripper is eating the source.
            """)
        XCTAssertTrue(offences.isEmpty, """
            \(offences.count) string(s) carry markup that a text mesh draws \
            as characters:

            \(offences.joined(separator: "\n"))
            """)
    }

    /// The scan can fail. Without this it could be matching nothing at
    /// all and reporting a clean tree forever.
    func testTheScanRecognisesTheMarkupItBans() {
        let samples = ["let s = \"orbit *around* the point\"",
                       "let s = \"a **hard** stop\"",
                       "let s = \"call `reset()` first\""]
        for sample in samples {
            let lines = codeLines(of: sample)
            XCTAssertEqual(lines.count, 1, sample)
            let hit = Self.markup.contains { pattern, _ in
                guard let regex = try? NSRegularExpression(pattern: pattern)
                else { return false }
                return regex.firstMatch(
                    in: sample, range: NSRange(sample.startIndex..., in: sample)) != nil
            }
            XCTAssertTrue(hit, "the scan does not recognise: \(sample)")
        }
    }

    /// …and does not fire on prose that merely contains a star or a
    /// multiplication sign, which this app's copy is full of.
    func testTheScanLeavesHonestProseAlone() {
        let innocent = ["let s = \"the star's pull\"",
                        "let s = \"5 * 3 = 15\"",
                        "let s = \"resonance 5x\""]
        for sample in innocent {
            let hit = Self.markup.contains { pattern, _ in
                guard let regex = try? NSRegularExpression(pattern: pattern)
                else { return false }
                return regex.firstMatch(
                    in: sample, range: NSRange(sample.startIndex..., in: sample)) != nil
            }
            XCTAssertFalse(hit, "the scan fires on honest prose: \(sample)")
        }
    }
}

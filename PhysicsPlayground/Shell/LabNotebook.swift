//
//  LabNotebook.swift
//  Physics Playground — Shell
//
//  The record you keep: a notebook entry is a timestamped row — which
//  module, a one-line title, and the parameters and measured values true
//  at that instant, captured from the module's own live readout. Entries
//  persist across launches and export as CSV and Markdown.
//

import Foundation
import Observation

/// One recorded observation.
struct NotebookEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var moduleID: String
    var moduleTitle: String
    var title: String
    var date: Date
    /// Ordered so a table reads the way the module presented it.
    var readings: [Reading]

    struct Reading: Codable, Equatable {
        var name: String
        var value: String
        var unit: String

        init(_ name: String, _ value: String, _ unit: String = "") {
            self.name = name
            self.value = value
            self.unit = unit
        }
    }

    var summary: String {
        readings.prefix(3)
            .map { "\($0.name) \($0.value)\($0.unit.isEmpty ? "" : " " + $0.unit)" }
            .joined(separator: " · ")
    }
}

@MainActor
@Observable
final class LabNotebook {
    nonisolated static let key = "notebook.entries.v1"
    nonisolated static let capacity = 200

    private(set) var entries: [NotebookEntry] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([NotebookEntry].self, from: data) {
            entries = decoded
        }
    }

    @discardableResult
    func record(moduleID: String, moduleTitle: String, title: String,
                readings: [NotebookEntry.Reading]) -> NotebookEntry {
        let entry = NotebookEntry(moduleID: moduleID, moduleTitle: moduleTitle,
                                  title: title, date: Date(), readings: readings)
        entries.insert(entry, at: 0)
        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
        persist()
        return entry
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        entries = []
        persist()
    }

    func entries(forModule moduleID: String) -> [NotebookEntry] {
        entries.filter { $0.moduleID == moduleID }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    // MARK: Export

    /// One row per reading, so the file drops straight into a
    /// spreadsheet or a plotting script.
    var csv: String {
        // "lab", the word the wearer reads everywhere else.
        var lines = ["timestamp,lab,observation,quantity,value,unit"]
        let formatter = ISO8601DateFormatter()
        for entry in entries.reversed() {
            let stamp = formatter.string(from: entry.date)
            for reading in entry.readings {
                let fields = [stamp, entry.moduleTitle, entry.title,
                              reading.name, reading.value, reading.unit]
                lines.append(fields.map(Self.escaped).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n")
    }

    /// A readable lab write-up — what actually gets pasted into a report.
    var markdown: String {
        var out = ["# Physics Playground — lab notebook", ""]
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let grouped = Dictionary(grouping: entries.reversed()) { $0.moduleTitle }
        for moduleTitle in grouped.keys.sorted() {
            out.append("## \(moduleTitle)")
            out.append("")
            for entry in grouped[moduleTitle] ?? [] {
                out.append("### \(entry.title) — \(formatter.string(from: entry.date))")
                out.append("")
                out.append("| Quantity | Value | Unit |")
                out.append("| --- | --- | --- |")
                for reading in entry.readings {
                    out.append("| \(reading.name) | \(reading.value) | \(reading.unit) |")
                }
                out.append("")
            }
        }
        return out.joined(separator: "\n")
    }

    private nonisolated static func escaped(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

//
//  ControlSegments.swift
//  RenderKit — Controls
//
//  One of a few named choices as one row: the stock segmented control,
//  exactly one segment selected (2026-11-04). For a choice whose options
//  are short and few — More's three tabs, a clock's six speeds, two
//  glasses — where a grid of latching buttons wrapped onto a second line
//  and read as six separate things rather than one setting. The value
//  lives with its owner and is read and written through closures, like
//  every control in the family.
//

import SwiftUI

public struct ControlSegments<ID: Hashable>: View {
    private let title: String
    private let options: [(id: ID, label: String)]
    @Binding private var selection: ID?

    public init(_ title: String, options: [(id: ID, label: String)],
                selection: Binding<ID?>) {
        self.title = title
        self.options = options
        self._selection = selection
    }

    /// For an owner that keeps the state behind closures. `selected` may
    /// be nil — a clock set from the command line to a speed the row does
    /// not list — and then no segment is selected.
    public init(_ title: String, options: [(id: ID, label: String)],
                selected: @escaping () -> ID?, select: @escaping (ID) -> Void) {
        let source = ClosureSource<ID?>(read: selected,
                                        write: { if let id = $0 { select(id) } })
        self.init(title, options: options,
                  selection: Binding(get: { source.read() }, set: { source.write($0) }))
    }

    public var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.id) { option in
                Text(option.label).tag(Optional(option.id))
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.extraLarge)
        .frame(minHeight: ControlMetrics.minimumTarget - 16)
        .accessibilityLabel(title)
    }
}

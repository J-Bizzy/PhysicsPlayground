//
//  ControlToggle.swift
//  RenderKit — Controls
//
//  The one switch. Two presentations of the same stock control: a
//  button-style toggle that stands alone (on reads as the system's
//  selected platter, never as a glow — the glow belongs to `LiveGlow`),
//  and a row — name on the left, system switch on the right — for a list
//  of settings, where a switch is what a wearer expects. State stays with
//  its owner: the toggle reads and writes through a binding, so a reset
//  that flips the model flips the switch too.
//

import SwiftUI

public struct ControlToggle: View {
    public enum Presentation {
        /// A latching button: the control on its own, in a bank or a bar.
        case button
        /// Name and switch across a row: one line of a settings list.
        case row
        /// A latching button that runs the width of its column, symbol
        /// over name: one cell of a grid of layers (2026-11-04). The name
        /// gets the cell's whole width, so "Equipotentials" stands on one
        /// line where, beside its symbol, it broke as "Equipoten-tials".
        case tile
        /// A latching button across the whole width, symbol and name: a
        /// switch with controls of its own under it, the size of the
        /// buttons it stands among.
        case wide
    }

    private let title: String
    /// Nil for a choice among several, where the selected platter already
    /// says which one is chosen and a glyph would only cost width.
    private let systemImage: String?
    private let iconOnly: Bool
    private let presentation: Presentation
    @Binding private var isOn: Bool

    public init(_ title: String, systemImage: String?,
                iconOnly: Bool = false, presentation: Presentation = .button,
                isOn: Binding<Bool>) {
        self.title = title
        self.systemImage = systemImage
        self.iconOnly = iconOnly
        self.presentation = presentation
        self._isOn = isOn
    }

    /// For an owner that keeps the state behind closures — a model flag
    /// read every frame.
    public init(_ title: String, systemImage: String?, iconOnly: Bool = false,
                presentation: Presentation = .button,
                isOn: @escaping () -> Bool,
                set: @escaping (Bool) -> Void) {
        let source = ClosureSource(read: isOn, write: set)
        self.init(title, systemImage: systemImage, iconOnly: iconOnly,
                  presentation: presentation,
                  isOn: Binding(get: { source.read() }, set: { source.write($0) }))
    }

    public var body: some View {
        switch presentation {
        case .button:
            Toggle(isOn: $isOn) {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                        .labelStyle(.controlLabel(iconOnly: iconOnly))
                } else {
                    Text(title)
                        .font(.body.weight(.medium))
                        .modifier(ControlTitleLines())
                        .frame(minHeight: ControlMetrics.minimumTarget - 16)
                }
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .buttonBorderShape(iconOnly ? .circle : .capsule)
            .controlSize(.extraLarge)
            .help(title)
            .accessibilityLabel(title)
        case .tile:
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: systemImage ?? "circle")
                        .font(.body.weight(.semibold))
                    Text(title)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: ControlMetrics.minimumTarget,
                       alignment: .leading)
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: ControlMetrics.tileRadius))
            .controlSize(.extraLarge)
            .help(title)
            .accessibilityLabel(title)
        case .wide:
            Toggle(isOn: $isOn) {
                Label(title, systemImage: systemImage ?? "circle")
                    .labelStyle(.controlLabel(iconOnly: false, fillsWidth: true))
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .help(title)
            .accessibilityLabel(title)
        case .row:
            Toggle(isOn: $isOn) {
                Label(title, systemImage: systemImage ?? "circle")
                    .labelStyle(.controlLabel(iconOnly: false))
            }
            .toggleStyle(.switch)
            .frame(minHeight: ControlMetrics.minimumTarget)
        }
    }
}

/// A model flag behind closures, boxed so a `Binding` can hold it. The
/// closures are only ever called on the main actor, where SwiftUI reads
/// and writes bindings.
final class ClosureSource<Value>: @unchecked Sendable {
    let read: () -> Value
    let write: (Value) -> Void

    init(read: @escaping () -> Value, write: @escaping (Value) -> Void) {
        self.read = read
        self.write = write
    }
}

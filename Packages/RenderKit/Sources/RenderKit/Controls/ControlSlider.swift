//
//  ControlSlider.swift
//  RenderKit — Controls
//
//  The one continuous control: a name, its live value, and a stock
//  slider, at least 60 pt tall. For a quantity with no extent of its own
//  to stretch — a voltage, a field, g. While a hand is on it the slider
//  wears `LiveGlow`, the one mark of "this is live". The value lives in
//  the model; the slider reads and writes it through closures, clamped
//  to the range.
//

import SwiftUI

public struct ControlSlider: View {
    private let title: String
    private let systemImage: String?
    private let range: ClosedRange<Double>
    private let step: Double?
    private let read: () -> Double
    private let write: (Double) -> Void
    private let format: (Double) -> String
    /// What VoiceOver says for a value — the format's symbols in words.
    private let speak: (Double) -> String

    @State private var isEditing = false

    public init(_ title: String,
                systemImage: String? = nil,
                range: ClosedRange<Double>,
                step: Double? = nil,
                read: @escaping () -> Double,
                write: @escaping (Double) -> Void,
                format: @escaping (Double) -> String,
                speak: ((Double) -> String)? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.range = range
        self.step = step
        self.read = read
        self.write = write
        self.format = format
        self.speak = speak ?? format
    }

    private var value: Binding<Double> {
        let range = range
        let source = ClosureSource(read: read, write: write)
        return Binding(
            get: { min(max(source.read(), range.lowerBound), range.upperBound) },
            set: { source.write(min(max($0, range.lowerBound), range.upperBound)) })
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.body.weight(.medium))
                Spacer(minLength: 12)
                Text(format(value.wrappedValue))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(isEditing ? .primary : .secondary)
                    .contentTransition(.numericText())
            }
            // The slider below says both; the header would be two more stops
            // saying them again.
            .accessibilityHidden(true)
            Group {
                if let step {
                    Slider(value: value, in: range, step: step) { editing in
                        isEditing = editing
                    }
                } else {
                    Slider(value: value, in: range) { editing in
                        isEditing = editing
                    }
                }
            }
            .frame(minHeight: ControlMetrics.minimumTarget - 16)
            .accessibilityLabel(title)
            .accessibilityValue(speak(value.wrappedValue))
        }
        .frame(minHeight: ControlMetrics.minimumTarget)
        .liveGlow(isEditing)
    }
}

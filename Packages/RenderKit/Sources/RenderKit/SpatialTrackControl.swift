//
//  SpatialTrackControl.swift
//  RenderKit — a labelled slider for a continuous quantity, standing in
//  the room.
//
//  The family's `ControlSlider` on its own glass, carried by an entity:
//  a pinch drags the stock slider, and SwiftUI hit-tests, hovers and reads
//  it to VoiceOver. The value lives in the model; the slider reads and
//  writes it through closures. `refresh()` tells the view when the shown
//  value moved under it (a reset, a scrub), so a mounting view must still
//  call it in its own update loop.
//
//  The older hand-mapping API (`owns`, `adjust(hand:)`) survives for
//  callers that route a drag by hand; nothing in the room hands it one
//  now, because the slider carries no collider of its own.
//

import Foundation
import RealityKit
import SwiftUI
import simd

/// What the slider shows, bumped only when the displayed value changes
/// under it, so the view re-reads its model; and the range it maps,
/// which a track over a changing span moves in place.
@MainActor
@Observable
final class TrackDisplay {
    var version = 0
    var range: ClosedRange<Double>

    init(range: ClosedRange<Double>) { self.range = range }
}

@MainActor
public final class SpatialTrackControl {
    public let root = Entity()
    public let name: String

    private let layout: TrackLayout
    /// The values the rail maps, end to end. Settable: the Time Capsule's
    /// rail maps whatever has been recorded, so its range moves between
    /// pauses, and the slider is told.
    public var range: ClosedRange<Double> {
        didSet {
            guard range != oldValue else { return }
            display.range = range
            lastShown = ""
            refresh()
        }
    }
    private let read: () -> Double
    private let write: (Double) -> Void
    private let format: (Double) -> String
    /// A second, quieter line under the slider — for a value that derives
    /// something (the ΔV rail's E = V/d).
    private let subtitle: ((Double) -> String)?
    private let display: TrackDisplay
    private var lastShown = ""
    private var isDragging = false

    /// - center: position within the entity this track is added to.
    /// - normal: which way the slider faces — the reader's side.
    public init(name: String,
                center: SIMD3<Float>,
                normal: SIMD3<Float>,
                accent: UIColor,
                range: ClosedRange<Double>,
                layout: TrackLayout = TrackLayout(),
                read: @escaping () -> Double,
                write: @escaping (Double) -> Void,
                format: @escaping (Double) -> String,
                subtitle: ((Double) -> String)? = nil,
                spokenName: String? = nil) {
        self.name = name
        self.layout = layout
        self.range = range
        self.display = TrackDisplay(range: range)
        self.read = read
        self.write = write
        self.format = format
        self.subtitle = subtitle

        root.name = name
        root.position = center
        root.orientation = Self.facing(normal)

        let width = CGFloat(layout.length) * CGFloat(ControlMetrics.pointsPerMeter)
        let display = self.display
        let card = TrackCard(title: spokenName ?? name,
                             read: read, write: write, format: format,
                             subtitle: subtitle, display: display)
            .frame(width: width)
            .padding(.horizontal, ControlMetrics.panelPadding)
            .padding(.vertical, 10)
            .glassBackgroundEffect(
                in: RoundedRectangle(cornerRadius: ControlMetrics.panelRadius,
                                     style: .continuous))
        root.addChild(ControlAttachment.entity(card, name: "\(name)-slider"))
        refresh()
    }

    /// Whether the track is present and live.
    public var isEnabled: Bool {
        get { root.isEnabled }
        set {
            root.isEnabled = newValue
            if !newValue { isDragging = false }
        }
    }

    /// Whether a hand-routed drag landed on this track. The slider carries
    /// no collider, so a tap in the room never resolves to it.
    public func owns(_ entity: Entity) -> Bool {
        guard root.isEnabled else { return false }
        var current: Entity? = entity
        while let candidate = current {
            if candidate === root { return true }
            current = candidate.parent
        }
        return false
    }

    public var isAdjusting: Bool { isDragging }

    /// Where the value sits along the track, in the track's own frame.
    public var beadOffset: SIMD3<Float> {
        SIMD3<Float>(layout.offset(forFraction: layout.fraction(forValue: read(), in: range)))
    }

    /// Sets the value from a hand position in the track's parent space.
    /// Absolute: wherever along the track the hand is, that is the value.
    @discardableResult
    public func adjust(hand: SIMD3<Double>) -> Bool {
        guard root.isEnabled else { return false }
        isDragging = true
        let local = root.orientation.inverse.act(
            SIMD3<Float>(hand) - root.position)
        let fraction = layout.fraction(forHandInTrackSpace: SIMD3<Double>(local))
        write(layout.value(forFraction: fraction, in: range))
        refresh()
        return true
    }

    public func endAdjust() { isDragging = false }

    /// One step, a twentieth of the range.
    public func nudge(by steps: Double) {
        let span = range.upperBound - range.lowerBound
        let next = read() + steps * span / 20
        write(min(max(next, range.lowerBound), range.upperBound))
        refresh()
    }

    /// Tells the slider the model moved, when the shown text changed.
    public func refresh() {
        let value = read()
        let shown = format(value) + (subtitle.map { "\n" + $0(value) } ?? "")
        guard shown != lastShown else { return }
        lastShown = shown
        display.version &+= 1
    }

    /// A quaternion whose local +Z maps to `normal`, +Y kept upright, so the
    /// slider runs horizontally across the reader's view.
    private static func facing(_ normal: SIMD3<Float>) -> simd_quatf {
        let z = simd_length(normal) > 1e-6 ? simd_normalize(normal) : SIMD3(0, 0, 1)
        let reference: SIMD3<Float> = abs(z.y) < 0.95 ? [0, 1, 0] : [1, 0, 0]
        let x = simd_normalize(simd_cross(reference, z))
        let y = simd_cross(z, x)
        return simd_quatf(simd_float3x3(columns: (x, y, z)))
    }
}

/// The slider and its derived line, re-read whenever `display` moves.
private struct TrackCard: View {
    let title: String
    let read: () -> Double
    let write: (Double) -> Void
    let format: (Double) -> String
    let subtitle: ((Double) -> String)?
    let display: TrackDisplay

    var body: some View {
        // Read so a model change the view cannot observe still redraws it.
        let _ = display.version
        VStack(alignment: .leading, spacing: 4) {
            ControlSlider(title, range: display.range, read: read, write: write,
                          format: format)
            if let subtitle {
                Text(subtitle(read()))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

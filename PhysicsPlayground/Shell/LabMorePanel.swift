//
//  LabMorePanel.swift
//  Physics Playground — Shell
//
//  What More opens in a lab: one glass panel, the fallback for anything
//  that is not the apparatus. Three tabs (2026-11-04, owner: the panel
//  was "very messy" — one long scroll of switches, greyed controls with
//  a reason under each, a clock on two lines and nine buttons of worlds):
//    • Lab — the lab's own controls (`ModuleDescriptor.more`) and a slider
//      for each quantity it has no object for (`adjustables`), placed by
//      kind (`MoreLayout`): choices, the layers as two-column tiles, each
//      switch with what it reveals, sliders, verbs, then Clear and Reset;
//    • Values — its live numbers (`readings`), the Physics box folded in;
//    • Room — move the lab, Deep space, how dim, and Settings.
//  Every control is the one family's, so nothing here is new to the hand.
//

import RenderKit
import SwiftUI

struct LabMorePanel: View {
    let module: ModuleDescriptor

    enum Tab: String, CaseIterable {
        case lab, values, room

        var title: String {
            switch self {
            case .lab: "Lab"
            case .values: "Values"
            case .room: "Room"
            }
        }
    }

    /// Opens on the lab's controls, every time: More is mounted only
    /// while it is open, and a panel that remembered Values would open
    /// on numbers to a wearer who came for a switch.
    @State private var tab: Tab = LabMorePanel.initialTab

    /// Tall enough for the busiest tab at default type; the rest scrolls.
    /// Each tab is only as tall as what it holds.
    private static let maxHeight: CGFloat = 700
    /// 440 pt at default type, growing with it — but no wider than a
    /// panel beside a window can stand, so the largest sizes wrap instead.
    /// Wide enough for two tiles to hold "Equipotentials" side by side.
    @ScaledMetric(relativeTo: .body) private var scaledWidth: CGFloat = 440
    private var width: CGFloat { min(scaledWidth, 560) }

    var body: some View {
        ControlPanel {
            VStack(alignment: .leading, spacing: 16) {
                ControlSegments("More", options: Tab.allCases.map { (id: $0, label: $0.title) },
                                selected: { tab }, select: { tab = $0 })
                ScrollView {
                    Group {
                        switch tab {
                        case .lab: LabTab(module: module)
                        case .values: ReadingsGrid(module: module)
                        case .room: RoomTab()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: Self.maxHeight)
                .fixedSize(horizontal: false, vertical: true)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(width: width)
    }

    /// `-moreValues 1` opens on Values and `-moreTab lab|values|room` on
    /// any tab, for a still: the simulator cannot pinch a segment.
    private static var initialTab: Tab {
        #if DEBUG
        let defaults = UserDefaults.standard
        if let name = defaults.string(forKey: "moreTab"), let tab = Tab(rawValue: name) {
            return tab
        }
        if defaults.bool(forKey: "moreValues") { return .values }
        #endif
        return .lab
    }
}

/// Where each of a lab's More items stands. Decided by kind, once, so
/// every lab's More reads the same from top to bottom, and the module
/// lists stay what they were: what the lab offers, in no layout at all.
struct MoreLayout {
    /// A few named options as one segmented row: a clock, a glass.
    var choices: [MoreItem] = []
    /// Plain switches — the layers and modes — as a grid of tiles.
    var tiles: [MoreItem] = []
    /// A switch or verb with what it alone makes usable.
    var groups: [MoreItem] = []
    /// Quantities with no object to stretch.
    var sliders: [MoreItem] = []
    /// Things to do or add: buttons and menus.
    var verbs: [MoreItem] = []
    /// Verbs that throw work away, at the foot beside Reset.
    var foot: [MoreItem] = []

    init(_ items: [MoreItem], adjustables: [PhysicsAdjustable] = []) {
        for item in items {
            switch item {
            case .choice: choices.append(item)
            case .toggle: tiles.append(item)
            case .group: groups.append(item)
            case .slider: sliders.append(item)
            case .verbs: verbs.append(item)
            case let .action(_, _, _, _, destructive, _, _):
                if destructive { foot.append(item) } else { verbs.append(item) }
            }
        }
        sliders += adjustables.map { .slider($0) }
    }

    /// Top to bottom.
    var bands: [[MoreItem]] { [choices, tiles, groups, sliders, verbs, foot] }
}

/// The Lab tab: the lab's controls in `MoreLayout`'s order, and Reset.
private struct LabTab: View {
    let module: ModuleDescriptor
    @Environment(AppModel.self) private var appModel

    private static let columns = [GridItem(.flexible(), spacing: ControlMetrics.spacing),
                                  GridItem(.flexible(), spacing: ControlMetrics.spacing)]

    var body: some View {
        let layout = MoreLayout(module.more, adjustables: module.adjustables)
        VStack(alignment: .leading, spacing: 18) {
            ForEach(layout.choices) { MoreItemView(item: $0) }
            if !layout.tiles.isEmpty {
                LazyVGrid(columns: Self.columns, alignment: .leading,
                          spacing: ControlMetrics.spacing) {
                    ForEach(layout.tiles) { MoreItemView(item: $0) }
                }
            }
            ForEach(layout.groups) { MoreItemView(item: $0) }
            ForEach(layout.sliders) { MoreItemView(item: $0) }
            // One a row, the width of the panel: a menu's chevron and a
            // name like "Add a world" do not fit half of it.
            ForEach(layout.verbs) { MoreItemView(item: $0) }
            Divider()
            foot(layout.foot)
        }
    }

    /// Clear and Reset together, side by side while they fit; stacked at
    /// the sizes where side by side would cut "Reset lab" to "Res…".
    private func foot(_ clears: [MoreItem]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: ControlMetrics.spacing) {
                ForEach(clears) { MoreItemView(item: $0, fillsWidth: false) }
                Spacer(minLength: 0)
                resetButton
            }
            VStack(alignment: .leading, spacing: ControlMetrics.spacing) {
                ForEach(clears) { MoreItemView(item: $0, fillsWidth: false) }
                resetButton
            }
        }
    }

    /// Arms first: in Circuit Workshop it wipes a bench that persists
    /// across launches.
    private var resetButton: some View {
        ControlButton("Reset lab", systemImage: "arrow.counterclockwise",
                      emphasis: .destructive, confirms: true) {
            appModel.resetActiveModule(module)
        }
        .accessibilityHint("Returns this lab to how it opened")
    }
}

/// The Room tab: where the lab stands and what stands round it.
private struct RoomTab: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var placement = appModel.labPlacement
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: ControlMetrics.spacing),
                                GridItem(.flexible(), spacing: ControlMetrics.spacing)],
                      alignment: .leading, spacing: ControlMetrics.spacing) {
                ControlToggle("Move the lab", systemImage: "move.3d",
                              presentation: .tile, isOn: $placement.isPlacing)
                    .accessibilityHint("Shows an anchor you can drag to move the whole lab")
                ControlToggle("Deep space", systemImage: "sparkles",
                              presentation: .tile,
                              isOn: { appModel.surroundings == .deepSpace },
                              set: { appModel.choose($0 ? .deepSpace : .room) })
                    .accessibilityHint("Stands you among the stars instead of in your room")
            }
            // There is no room to dim in deep space, so there is no slider.
            if appModel.surroundings != .deepSpace {
                ControlSlider("Dim the room", systemImage: "circle.lefthalf.filled",
                              range: 0...1,
                              read: { appModel.roomDimming },
                              write: { appModel.setDimming($0) },
                              format: { "\(Int(($0 * 100).rounded())) %" },
                              speak: { "\(Int(($0 * 100).rounded())) percent" })
            }
            Divider()
            ControlButton("Settings", systemImage: "gearshape") {
                openWindow(id: SettingsView.windowID)
            }
        }
    }
}

/// One `MoreItem`, in the family's controls.
struct MoreItemView: View {
    let item: MoreItem
    /// A verb runs the width of its column, except at the foot, where it
    /// stands beside Reset.
    var fillsWidth = true
    /// A switch across the whole width rather than a cell of the grid:
    /// one that leads a group, or stands in one.
    var wide = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let reason = item.unavailableReason
        switch item {
        case let .toggle(_, title, symbol, isOn, set, _):
            ControlToggle(title, systemImage: symbol, presentation: wide ? .wide : .tile,
                          isOn: isOn, set: set)
                .unavailable(reason)
        case let .action(_, title, symbol, confirms, destructive, _, run):
            ControlButton(title, systemImage: symbol,
                          emphasis: destructive ? .destructive : .standard,
                          fillsWidth: fillsWidth, confirms: confirms, action: run)
                .unavailable(reason)
        case let .choice(_, title, options, selected, select):
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.body.weight(.medium))
                    .accessibilityHidden(true)
                ControlSegments(title, options: options, selected: selected, select: select)
            }
        case let .verbs(_, title, items, note, _, run):
            ControlMenu(title, systemImage: "plus", note: note,
                        items: items.map { .init(id: $0.id, label: $0.label, systemImage: $0.symbol) },
                        choose: run)
                .unavailable(reason)
        case let .slider(adjustable, _):
            let format = adjustable.format ?? {
                PhysicsFormat.measurement($0, adjustable.unit, decimals: adjustable.decimals)
            }
            ControlSlider(adjustable.label, range: adjustable.range,
                          read: adjustable.read, write: adjustable.write,
                          format: format,
                          speak: { PhysicsFormat.spoken(format($0)) })
                .unavailable(reason)
        case let .group(lead, reveals, items):
            let shown = reveals()
            VStack(alignment: .leading, spacing: ControlMetrics.spacing) {
                MoreItemView(item: lead, wide: true)
                if shown {
                    // Indented under the switch that brought them, with a
                    // hairline down their left so they read as its own.
                    VStack(alignment: .leading, spacing: ControlMetrics.spacing) {
                        ForEach(items) { MoreItemView(item: $0, wide: true) }
                    }
                    .padding(.leading, 18)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.tertiary)
                            .frame(width: 2)
                            .padding(.vertical, 6)
                            .padding(.leading, 4)
                            .accessibilityHidden(true)
                    }
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: shown)
        }
    }
}

/// A control that cannot be used now, greyed, with one dim line under it
/// saying why (2026-11-02). VoiceOver hears the reason as the control's
/// hint, so the line is not a second stop.
private struct Unavailable: ViewModifier {
    let reason: String?

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content
                .disabled(reason != nil)
                .accessibilityHint(reason ?? "")
            if let reason {
                Text(reason)
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: reason)
    }
}

extension View {
    /// Greys this More control while `reason` is set, and says why.
    func unavailable(_ reason: String?) -> some View {
        modifier(Unavailable(reason: reason))
    }
}

/// One reading as one VoiceOver stop: its words, its law on request,
/// and the trait that tells VoiceOver it changes on its own.
private struct ReadingAccessibility: ViewModifier {
    let row: Reading

    func body(content: Content) -> some View {
        let element = content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ReadingsGrid.spoken(row))
            .accessibilityAddTraits(.updatesFrequently)
        if let law = ReadingsGrid.law(row) {
            element.accessibilityCustomContent("Law", law)
        } else {
            element
        }
    }
}

/// The lab's live numbers, refreshed eight times a second: what the
/// Physics box used to stand in the room.
struct ReadingsGrid: View {
    let module: ModuleDescriptor

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast

    /// What VoiceOver says for a row: the reading, its units in words.
    /// The law is there on request (`law`), not on every swipe.
    static func spoken(_ row: Reading) -> String {
        PhysicsFormat.spoken("\(row.name): \(row.value) \(row.unit)")
    }

    /// The law under a reading, as VoiceOver's "more content".
    static func law(_ row: Reading) -> String? {
        row.formula.map { PhysicsFormat.spoken(Formula.plain($0)) }
    }

    /// The law's ink: dim so the column of numbers reads first, less dim
    /// when the wearer has asked for more contrast.
    private var lawStyle: HierarchicalShapeStyle {
        contrast == .increased ? .secondary : .tertiary
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 8)) { _ in
            let rows = module.readings()
            // Leading, explicitly: a timeline stacks its children centred,
            // which set the grid in from the edge whenever a note below it
            // ran wider.
            VStack(alignment: .leading, spacing: ControlMetrics.spacing) {
            if typeSize.isAccessibilitySize {
                // Three columns cannot hold a number at these sizes: each
                // reading stands as its name over its value.
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.value).font(.body.monospacedDigit())
                            Text(row.unit).font(.callout).foregroundStyle(.secondary)
                        }
                        if let formula = row.formula {
                            Text(Formula.attributed(formula))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(lawStyle)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .modifier(ReadingAccessibility(row: row))
                }
            } else {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        // The name cell speaks for the row: a modifier on the
                        // GridRow lands on every cell, and the row was read
                        // out three times.
                        Text(row.name)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .modifier(ReadingAccessibility(row: row))
                        Text(row.value)
                            .font(.body.monospacedDigit())
                            .gridColumnAlignment(.trailing)
                            .lineLimit(1)
                            .accessibilityHidden(true)
                        Text(row.unit)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityHidden(true)
                    }
                    // The law, under the number it governs: smaller and
                    // dimmer than the reading, so the column of numbers
                    // still reads first.
                    if let formula = row.formula {
                        GridRow {
                            Text(Formula.attributed(formula))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(lawStyle)
                                .fixedSize(horizontal: false, vertical: true)
                                .gridCellColumns(3)
                                .padding(.top, -3)
                                .padding(.bottom, 2)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            }
            if let note = module.physicsNote() {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            }
        }
    }
}

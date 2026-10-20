//
//  LabMorePanel.swift
//  Physics Playground — Shell
//
//  What More opens in a lab: one glass panel, the fallback for anything
//  that is not the apparatus. Four parts, top to bottom:
//    • the lab's own secondary controls (`ModuleDescriptor.more`) and a
//      slider for each quantity it has no object for (`adjustables`);
//    • its live numbers (`readings`) — the Physics box, folded in;
//    • the room: move the lab, Deep space, how dim;
//    • Settings and Reset (Reset arms first, like every destructive verb).
//  Every control is the one family's, so nothing here is new to the hand.
//

import RenderKit
import SwiftUI

struct LabMorePanel: View {
    let module: ModuleDescriptor
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow

    /// Tall enough for the busiest lab at default type; the rest scrolls.
    private static let maxHeight: CGFloat = 760
    private static let width: CGFloat = 400

    var body: some View {
        @Bindable var appModel = appModel
        @Bindable var placement = appModel.labPlacement
        ControlPanel {
            ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !module.more.isEmpty || !module.adjustables.isEmpty {
                        ControlSection("This lab") {
                            ForEach(module.more) { item in
                                MoreItemView(item: item)
                            }
                            ForEach(module.adjustables) { adjustable in
                                MoreItemView(item: .slider(adjustable))
                            }
                        }
                    }

                    let readings = module.readings()
                    if !readings.isEmpty {
                        ControlSection("Values") {
                            ReadingsGrid(module: module)
                        }
                        .id(Self.valuesID)
                    }

                    ControlSection("Room") {
                        ControlToggle("Move the lab", systemImage: "move.3d",
                                      presentation: .row, isOn: $placement.isPlacing)
                            .accessibilityHint("Shows an anchor you can drag to move the whole lab")
                        ControlToggle("Deep space", systemImage: "sparkles",
                                      presentation: .row,
                                      isOn: { appModel.surroundings == .deepSpace },
                                      set: { appModel.choose($0 ? .deepSpace : .room) })
                            .accessibilityHint("Stands you among the stars instead of in your room")
                        // There is no room to dim in deep space.
                        ControlSlider("Dim the room", systemImage: "circle.lefthalf.filled",
                                      range: 0...1,
                                      read: { appModel.roomDimming },
                                      write: { appModel.setDimming($0) },
                                      format: { "\(Int(($0 * 100).rounded())) %" })
                            .disabled(appModel.surroundings == .deepSpace)
                    }

                    HStack(spacing: ControlMetrics.spacing) {
                        ControlButton("Settings", systemImage: "gearshape") {
                            openWindow(id: SettingsView.windowID)
                        }
                        Spacer(minLength: 0)
                        // Arms first: in Circuit Workshop it wipes a bench that
                        // persists across launches.
                        ControlButton("Reset lab", systemImage: "arrow.counterclockwise",
                                      emphasis: .destructive, confirms: true) {
                            appModel.resetActiveModule(module)
                        }
                        .accessibilityHint("Returns this lab to how it opened")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: Self.maxHeight)
            .scrollBounceBehavior(.basedOnSize)
            #if DEBUG
            // `-moreValues 1` opens More scrolled to its Values: in a lab
            // with a long list of controls they are below the fold, and
            // the simulator cannot scroll.
            .onAppear {
                if UserDefaults.standard.bool(forKey: "moreValues") {
                    scroller.scrollTo(Self.valuesID, anchor: .top)
                }
            }
            #endif
            }
        }
        .frame(width: Self.width)
    }

    private static let valuesID = "values"
}

/// One `MoreItem`, in the family's controls.
struct MoreItemView: View {
    let item: MoreItem

    var body: some View {
        switch item {
        case let .toggle(_, title, symbol, isOn, set, isEnabled):
            ControlToggle(title, systemImage: symbol, presentation: .row,
                          isOn: isOn, set: set)
                .disabled(!isEnabled())
        case let .action(_, title, symbol, confirms, destructive, isEnabled, run):
            ControlButton(title, systemImage: symbol,
                          emphasis: destructive ? .destructive : .standard,
                          fillsWidth: true, confirms: confirms, action: run)
                .disabled(!isEnabled())
        case let .choice(_, title, options, selected, select):
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.body.weight(.medium))
                ChoiceRow(options: options, selected: selected(), select: select)
            }
        case let .verbs(_, title, items, run):
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.body.weight(.medium))
                let columns = [GridItem(.adaptive(minimum: 150), spacing: ControlMetrics.spacing)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: ControlMetrics.spacing) {
                    ForEach(items, id: \.id) { item in
                        ControlButton(item.label, systemImage: item.symbol,
                                      fillsWidth: true) { run(item.id) }
                    }
                }
            }
        case let .slider(adjustable, isEnabled):
            ControlSlider(adjustable.label, range: adjustable.range,
                          read: adjustable.read, write: adjustable.write,
                          format: adjustable.format ?? {
                              PhysicsFormat.measurement($0, adjustable.unit,
                                                        decimals: adjustable.decimals)
                          })
                .disabled(!isEnabled())
        }
    }
}

/// A few named choices as the family's toggles, exactly one selected.
private struct ChoiceRow: View {
    let options: [(id: String, label: String)]
    let selected: String?
    let select: (String) -> Void

    var body: some View {
        // Wraps rather than squeezing: a clock with six speeds is two rows.
        let columns = [GridItem(.adaptive(minimum: 100), spacing: ControlMetrics.spacing)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: ControlMetrics.spacing) {
            ForEach(options, id: \.id) { option in
                ControlToggle(option.label, systemImage: nil,
                              isOn: { selected == option.id },
                              set: { _ in select(option.id) })
            }
        }
    }
}

/// The lab's live numbers, refreshed eight times a second: what the
/// Physics box used to stand in the room.
struct ReadingsGrid: View {
    let module: ModuleDescriptor

    /// What VoiceOver says for a row: the reading, then its law, spoken
    /// without the subscript markup.
    static func spoken(_ row: Reading) -> String {
        let reading = "\(row.name): \(row.value) \(row.unit)"
        guard let formula = row.formula else { return reading }
        return reading + ". " + Formula.plain(formula)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 8)) { _ in
            let rows = module.readings()
            // Leading, explicitly: a timeline stacks its children centred,
            // which set the grid in from the edge whenever a note below it
            // ran wider.
            VStack(alignment: .leading, spacing: ControlMetrics.spacing) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.name)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(row.value)
                            .font(.body.monospacedDigit())
                            .gridColumnAlignment(.trailing)
                            .lineLimit(1)
                        Text(row.unit)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Self.spoken(row))
                    // The law, under the number it governs: smaller and
                    // dimmer than the reading, so the column of numbers
                    // still reads first.
                    if let formula = row.formula {
                        GridRow {
                            Text(Formula.attributed(formula))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .gridCellColumns(3)
                                .padding(.top, -3)
                                .padding(.bottom, 2)
                        }
                        .accessibilityHidden(true)
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

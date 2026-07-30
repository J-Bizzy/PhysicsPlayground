//
//  StationSection.swift
//  Physics Playground — Design System
//
//  One station's controls in a world's window panel: expanded when that
//  station is focused, collapsed to a live readout when it is not.
//
//  This is PROPERTY 3 of the focus contract (see StationFocus): sections
//  COLLAPSE, they never disappear. Three panels stacked at full height
//  is a wall nobody reads, but removing two of them would put a
//  capability behind a choice — and the standing rule is that nothing
//  may be the only path to a capability, and nothing may be unreachable
//  in the simulator or under VoiceOver. A collapsed section is still in
//  the accessibility tree, still one tap from open, still reachable
//  without hands.
//
//  It differs from `CollapsedSection` in exactly one way, and that way
//  is the point: its disclosure is BOUND to focus rather than owned
//  privately, so opening a section here attends to that apparatus in the
//  room and attending to an apparatus in the room opens its section.
//  The panel is the second, always-reachable path to focus.
//
//  Collapsed does not mean silent. Each header carries the station's
//  single most important live number, so a glance at a folded panel
//  still reports all three benches — which is the whole reason a
//  readout-only panel survives in an app whose controls moved into the
//  room.
//

import SwiftUI

struct StationSection<Content: View>: View {
    let title: String
    /// The one number worth seeing while this section is folded.
    let readout: String
    let accent: Color
    let isFocused: Bool
    let focus: () -> Void
    @ViewBuilder let content: Content

    init(_ title: String, readout: String, accent: Color,
         isFocused: Bool, focus: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.readout = readout
        self.accent = accent
        self.isFocused = isFocused
        self.focus = focus
        self.content = content()
    }

    var body: some View {
        PanelSection {
            DisclosureGroup(isExpanded: expansion) {
                VStack(alignment: .leading,
                       spacing: DesignTokens.Panel.rowSpacing) {
                    content
                }
                .padding(.top, 10)
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(DesignTokens.TypeScale.sectionHeader)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 12)
                    Text(readout)
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                        .foregroundStyle(isFocused ? accent : .secondary)
                }
            }
            .tint(.secondary)
            .accessibilityHint(isFocused
                ? "This bench is the one being attended to"
                : "Opens this bench's controls and brings it forward in the room")
        }
    }

    /// Opening a section attends to its station. CLOSING one is a no-op
    /// rather than an unfocus: something is always focused, so the way
    /// to fold this is to open another.
    private var expansion: Binding<Bool> {
        Binding(get: { isFocused },
                set: { wantsOpen in if wantsOpen { focus() } })
    }
}

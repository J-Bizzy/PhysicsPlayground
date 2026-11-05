//
//  ControlMenu.swift
//  RenderKit — Controls
//
//  A list of like verbs behind one button (2026-11-04): the family's
//  bordered capsule, its symbol and name, and a chevron saying it opens.
//  For "Add a world" and "Load a circuit", whose nine and five buttons
//  were each a grid taller than everything else in More. Opening the
//  menu and choosing from it are two deliberate presses on two targets,
//  which is why a choice that replaces work (a preset over the bench)
//  does not arm as well: the menu is the second press. A note, when there
//  is one, heads the list and says what a choice will do.
//

import SwiftUI

public struct ControlMenu: View {
    public struct Item: Identifiable {
        public let id: String
        public let label: String
        public let systemImage: String?

        public init(id: String, label: String, systemImage: String? = nil) {
            self.id = id
            self.label = label
            self.systemImage = systemImage
        }
    }

    private let title: String
    private let systemImage: String
    private let note: String?
    private let items: [Item]
    private let choose: (String) -> Void

    public init(_ title: String, systemImage: String, note: String? = nil,
                items: [Item], choose: @escaping (String) -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.note = note
        self.items = items
        self.choose = choose
    }

    public var body: some View {
        Menu {
            if let note {
                Section(note) { choices }
            } else {
                choices
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.body.weight(.medium))
                    .modifier(ControlTitleLines())
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: ControlMetrics.minimumTarget - 16)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityHint(note ?? "Opens a list to choose from")
    }

    @ViewBuilder private var choices: some View {
        ForEach(items) { item in
            Button {
                choose(item.id)
            } label: {
                if let symbol = item.systemImage {
                    Label(item.label, systemImage: symbol)
                } else {
                    Text(item.label)
                }
            }
        }
    }
}

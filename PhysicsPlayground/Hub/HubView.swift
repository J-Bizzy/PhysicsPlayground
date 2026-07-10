//
//  HubView.swift
//  Physics Playground — Hub
//
//  The module catalog: a grid of cards, one per physics module. Picking a
//  card activates the module and opens the shared immersive space. This
//  window-based catalog is the hub's first form — the walk-through hub
//  space comes once there are multiple modules to walk between.
//

import SwiftUI

struct HubView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Panel.sectionSpacing) {
                VStack(spacing: 6) {
                    Text("Physics Playground")
                        .font(DesignTokens.TypeScale.screenTitle)
                    Text("Pick a simulation and it appears in your room.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(ModuleCatalog.all(appModel: appModel)) { module in
                        ModuleCard(module: module) {
                            enter(module)
                        }
                    }
                }
            }
            .padding(DesignTokens.Panel.outerPadding)
        }
    }

    private func enter(_ module: ModuleDescriptor) {
        appModel.activeModuleID = module.id
        Task {
            if !appModel.isImmersiveSpaceOpen {
                _ = await openImmersiveSpace(id: PlaygroundSpaceView.spaceID)
            }
        }
    }
}

private struct ModuleCard: View {
    let module: ModuleDescriptor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DesignTokens.Panel.rowSpacing) {
                Image(systemName: module.icon)
                    .font(.system(size: 34))
                    .foregroundStyle(module.accent)
                Text(module.title)
                    .font(DesignTokens.TypeScale.cardTitle)
                Text(module.blurb)
                    .font(DesignTokens.TypeScale.label)
                    .foregroundStyle(.secondary)
                    .lineLimit(3, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignTokens.Panel.padding)
        }
        .buttonStyle(.plain)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: DesignTokens.Panel.cornerRadius)
        )
        .hoverEffect()
        .accessibilityLabel("\(module.title). \(module.blurb)")
        .accessibilityHint("Opens this simulation in your room")
    }
}

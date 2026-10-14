//
//  SelectionHalo.swift
//  Physics Playground — DesignSystem
//
//  The one "this is selected" veil. The shape stays the caller's; the
//  shared constant is the opacity. A halo is decoration, never a target:
//  no collider, no input, hidden until selected — the factory guarantees it.
//

import RealityKit
import RenderKit

enum SelectionHalo {
    /// How present the veil is, everywhere.
    static let opacity: Float = 0.22

    /// The scene-graph name every halo wears, so `SelectionHaloTests`
    /// can find it and check selection is actually visible.
    static let entityName = "selection-halo"

    /// A soft unlit shell in the selection colour, disabled until the
    /// caller's selection logic wakes it.
    @MainActor
    static func make(mesh: MeshResource) -> ModelEntity {
        let material = Materials.unlit(DesignTokens.Palette.selectionHaloUI, opacity: opacity)
        let halo = ModelEntity(mesh: mesh, materials: [material])
        halo.name = entityName
        halo.isEnabled = false
        return halo
    }
}

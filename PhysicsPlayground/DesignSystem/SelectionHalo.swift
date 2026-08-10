//
//  SelectionHalo.swift
//  Physics Playground — DesignSystem
//
//  The one "this is selected" veil, as a factory.
//
//  Three modules each hand-rolled it — Magnetism a box shell at 0.22,
//  Circuits a sphere at 0.18, Electric Fields a sphere at 0.25 — three
//  opacities for one concept, drifted apart because each was typed on a
//  different day. The SHAPE stays the caller's: a halo tracks the object
//  it wraps (a box for a bar magnet, a sphere for a charge or a part),
//  and unifying that would be the wrong kind of consistency. What is one
//  concept is how present the veil is, so that is the shared constant.
//
//  A halo is decoration, never a target: no collider, no input, hidden
//  until its object is selected. The factory guarantees all three.
//

import RealityKit

enum SelectionHalo {
    /// How present the veil is, everywhere.
    static let opacity: Float = 0.22

    /// The scene-graph name every halo wears.
    ///
    /// Added 2026-08-09 so a halo can be FOUND. Three modules each build
    /// one, hand it to a private per-object visual, and never name it —
    /// which meant nothing outside those renderers could tell a halo
    /// from any other unlit shell, and so nothing ever checked whether
    /// selection was visible at all. It was not: `Fade.tick` could not
    /// leave a settled state, and a halo is built disabled, so no halo
    /// in this app had ever been drawn. `SelectionHaloTests` is what
    /// this name is for.
    static let entityName = "selection-halo"

    /// A soft unlit shell in the selection colour, disabled until the
    /// caller's selection logic wakes it.
    @MainActor
    static func make(mesh: MeshResource) -> ModelEntity {
        var material = UnlitMaterial(color: DesignTokens.Palette.selectionHaloUI)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        let halo = ModelEntity(mesh: mesh, materials: [material])
        halo.name = entityName
        halo.isEnabled = false
        return halo
    }
}

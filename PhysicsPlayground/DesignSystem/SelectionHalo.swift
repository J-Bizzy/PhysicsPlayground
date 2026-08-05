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

    /// A soft unlit shell in the selection colour, disabled until the
    /// caller's selection logic wakes it.
    @MainActor
    static func make(mesh: MeshResource) -> ModelEntity {
        var material = UnlitMaterial(color: DesignTokens.Palette.selectionHaloUI)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        let halo = ModelEntity(mesh: mesh, materials: [material])
        halo.isEnabled = false
        return halo
    }
}

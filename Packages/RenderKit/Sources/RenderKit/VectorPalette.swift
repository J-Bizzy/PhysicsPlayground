//
//  VectorPalette.swift
//  RenderKit
//
//  The colour of each physical vector, app-wide: velocity blue,
//  acceleration orange, force red. One canon, owned by the rendering
//  package so the design tokens and RenderKit's primitives read from
//  the same place. Per-module decompositions (Pendulums' gravity and
//  tension components) keep their own colours, taught by their legends.
//

import UIKit

public enum VectorPalette {
    public static let velocity: UIColor = .systemBlue
    public static let acceleration: UIColor = .systemOrange
    public static let force: UIColor = .systemRed

    /// Gravity is a force and still needs its own colour: a component of a
    /// sum must be distinguishable from the sum. Cyan rather than purple,
    /// because `.systemPurple` is ΔE 0 from `pendulumsAccent`, the furniture
    /// of the one module that draws this arrow. #59E5FF is ΔE 79 from the
    /// nearest thing it shares a room with.
    public static let gravity: UIColor = UIColor(red: 0.35, green: 0.90,
                                                 blue: 1.0, alpha: 1)
}

//
//  VectorPalette.swift
//  RenderKit
//
//  THE colour of each physical vector, app-wide. This file exists
//  because the app had four dialects: the design tokens said force is
//  red, Springs drew it green, Pendulums hardcoded near-misses of the
//  tokens, and the frozen-time arrows introduced orange force — which
//  collided head-on with orange-means-acceleration everywhere else.
//  An arrow language you have to relearn per lab is not a language.
//
//  One canon, owned by the rendering package so both the app's design
//  tokens and RenderKit's own primitives read from the same place:
//
//    velocity      — blue    (where it's going)
//    acceleration  — orange  (how the going is changing)
//    force         — red     (what's doing the changing)
//
//  Per-module DECOMPOSITIONS keep their own colours (Pendulums' purple
//  gravity and yellow tension components, for instance) — those are
//  local vocabulary, and each module's legend teaches them. The trio
//  above is the shared grammar and is not module property.
//

import UIKit

public enum VectorPalette {
    public static let velocity: UIColor = .systemBlue
    public static let acceleration: UIColor = .systemOrange
    public static let force: UIColor = .systemRed

    /// GRAVITY IS A FORCE AND STILL NEEDS ITS OWN COLOUR.
    ///
    /// Pendulums drew the gravity arrow and the NET force arrow in the
    /// identical `force` red — reasoning, in a comment, that gravity is
    /// a force and the vector language should say so. True, and the
    /// consequence was two arrows from the same bob in the same colour
    /// with no way to tell which was which. The module's own legend had
    /// been promising "purple gravity" the whole time.
    ///
    /// A component of a sum needs to be distinguishable from the sum.
    ///
    /// CYAN, NOT THE PURPLE THE LEGEND PROMISED. `.systemPurple` was the
    /// obvious first choice and it is ΔE 0.0 from `pendulumsAccent` —
    /// the accent worn by every plate and label in the one module that
    /// draws this arrow. Trading "same as the net force" for "same as
    /// the furniture" is not a fix.
    ///
    /// The legend was wrong either way: it had been promising purple
    /// while the arrow was drawn red, so no wording was being preserved
    /// by keeping it. #59E5FF is ΔE 79 from the nearest thing it shares
    /// a room with.
    public static let gravity: UIColor = UIColor(red: 0.35, green: 0.90,
                                                 blue: 1.0, alpha: 1)
}

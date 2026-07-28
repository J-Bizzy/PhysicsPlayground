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
}

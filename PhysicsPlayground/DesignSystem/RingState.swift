//
//  RingState.swift
//  Physics Playground — Design System
//
//  Which object's control ring is open. A reference type ON PURPOSE: a
//  @State value read from a RealityKit update closure comes back stale —
//  tap gesture and per-frame sync must share one live object.
//

import Foundation

@MainActor
final class RingState {
    /// The tapped object whose ring is unfolded, or nil when folded.
    var openID: UUID?
}

//
//  RingState.swift
//  Physics Playground — Design System
//
//  Which object's control ring is open, shared between a module's tap
//  gesture and its render loop. A reference type ON PURPOSE: a SwiftUI
//  @State value read from a RealityKit update closure comes back stale
//  (the trap documented in Bloom's header) — the tap and the per-frame
//  sync must share one live object. Hold it as @State in the SpaceView;
//  the reference never changes, only its `openID`.
//

import Foundation

@MainActor
final class RingState {
    /// The tapped object whose ring is unfolded, or nil when folded.
    var openID: UUID?
}

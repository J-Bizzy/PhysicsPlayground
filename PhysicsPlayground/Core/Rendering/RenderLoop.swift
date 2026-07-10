//
//  RenderLoop.swift
//  Physics Playground — Core kernel
//
//  The observation-driven render loop every simulation renderer uses:
//  run the render closure once inside withObservationTracking, get told the
//  moment any @Observable property it read changes, re-render, re-arm.
//  Deterministic and independent of SwiftUI view diffing — this replaced
//  RealityView's update closure after its change tracking proved unreliable
//  (adds and mid-drag changes weren't re-rendering).
//

import Foundation
import Observation

@MainActor
final class RenderLoop {
    private var render: (@MainActor () -> Void)?

    /// Renders now, then re-renders on every observed change until `stop()`.
    func start(_ render: @escaping @MainActor () -> Void) {
        self.render = render
        tick()
    }

    func stop() {
        render = nil
    }

    private func tick() {
        guard let render else { return }
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            // onChange fires once (from any thread) at the first mutation;
            // hop to the main actor, re-render, and re-arm the tracking.
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }
}

//
//  GeometryPipeline.swift
//  RenderKit
//
//  A coalescing background worker for expensive geometry (streamline
//  tracing, isosurface marching, trail meshes). The frame-rate contract for
//  every simulation: heavy math NEVER runs on the main thread.
//
//  Submit jobs as fast as state changes; if they arrive faster than
//  rebuilds finish, intermediate jobs are dropped and only the newest runs
//  ("newest state wins"). Results are applied back on the main actor.
//

import Foundation

@MainActor
public final class GeometryPipeline<Job: Sendable, Output: Sendable> {
    private let compute: @Sendable (Job) -> Output
    private let apply: @MainActor (Output) -> Void
    private var pendingJob: Job?
    private var isRunning = false

    public init(
        compute: @escaping @Sendable (Job) -> Output,
        apply: @escaping @MainActor (Output) -> Void
    ) {
        self.compute = compute
        self.apply = apply
    }

    public func submit(_ job: Job) {
        pendingJob = job
        guard !isRunning else { return }
        isRunning = true
        Task { [weak self] in
            while let next = self?.takePending() {
                guard let compute = self?.compute else { break }
                let output = await Task.detached(priority: .userInitiated) {
                    compute(next)
                }.value
                self?.apply(output)
            }
            self?.isRunning = false
        }
    }

    private func takePending() -> Job? {
        defer { pendingJob = nil }
        return pendingJob
    }
}

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
//  IT IS ALSO CANCELLABLE, since 2026-08-07, and was not before. The
//  driving `Task` was never stored and neither loop checked
//  `Task.isCancelled`, so a trace in flight when a lab closed ran to
//  completion and then uploaded a `MeshResource` and enabled an entity
//  on a renderer whose scene was being torn down. Five renderers use
//  this, and Magnetism's field-line job is the heavy one — 2400 steps
//  per line plus an O(n²) dedup sweep — so "leave Magnetism during a
//  drag" is a real path to seconds of compute nobody can see and a
//  write into a dead scene.
//

import Foundation

@MainActor
public final class GeometryPipeline<Job: Sendable, Output: Sendable> {
    private let compute: @Sendable (Job) -> Output
    private let apply: @MainActor (Output) -> Void
    private var pendingJob: Job?
    private var isRunning = false
    private var worker: Task<Void, Never>?

    public init(
        compute: @escaping @Sendable (Job) -> Output,
        apply: @escaping @MainActor (Output) -> Void
    ) {
        self.compute = compute
        self.apply = apply
    }

    deinit { worker?.cancel() }

    public func submit(_ job: Job) {
        pendingJob = job
        guard !isRunning else { return }
        isRunning = true
        worker = Task { [weak self] in
            while !Task.isCancelled, let next = self?.takePending() {
                guard let compute = self?.compute else { break }
                let output = await Task.detached(priority: .userInitiated) {
                    compute(next)
                }.value
                // Checked AFTER the await: the whole point is the work
                // that finishes once the scene it was for is gone.
                guard !Task.isCancelled else { break }
                self?.apply(output)
            }
            self?.isRunning = false
        }
    }

    /// Abandons the job in flight and everything queued behind it. Call
    /// from a renderer's teardown; submitting again afterwards starts a
    /// fresh worker.
    public func cancel() {
        worker?.cancel()
        worker = nil
        pendingJob = nil
        isRunning = false
    }

    private func takePending() -> Job? {
        defer { pendingJob = nil }
        return pendingJob
    }
}

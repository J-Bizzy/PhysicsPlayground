//
//  GeometryPipeline.swift
//  RenderKit
//
//  Coalescing background worker for expensive geometry: newest state wins,
//  heavy math never on the main thread, results applied on the main actor.
//  Cancellable — call cancel() from teardown, or a trace that outlives its
//  lab writes into a dead scene.
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
                // Checked AFTER the await — the danger is work finishing
                // once the scene it was for is gone.
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

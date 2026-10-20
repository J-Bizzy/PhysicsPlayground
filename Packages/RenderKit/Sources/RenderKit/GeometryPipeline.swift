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
    /// How a job arriving while another waits is folded into it. Without
    /// one the newest job simply replaces the pending one.
    private let coalesce: ((Job, Job) -> Job)?
    /// The least time between two results applied, seconds; 0 applies each
    /// as it lands. A result is a mesh written in place, and RealityKit
    /// lets only so many such writes be in flight at once: Electric Fields'
    /// lines and shells, each rewritten every frame while a charge moved,
    /// left the main thread waiting on the renderer half of every frame.
    /// Jobs arriving in between fold into the next, as ever.
    private let minimumInterval: Double
    private var pendingJob: Job?
    private var isRunning = false
    private var worker: Task<Void, Never>?

    public init(
        compute: @escaping @Sendable (Job) -> Output,
        apply: @escaping @MainActor (Output) -> Void,
        coalesce: ((Job, Job) -> Job)? = nil,
        minimumInterval: Double = 0
    ) {
        self.compute = compute
        self.apply = apply
        self.coalesce = coalesce
        self.minimumInterval = minimumInterval
    }

    deinit { worker?.cancel() }

    public func submit(_ job: Job) {
        if let coalesce, let waiting = pendingJob {
            pendingJob = coalesce(waiting, job)
        } else {
            pendingJob = job
        }
        guard !isRunning else { return }
        isRunning = true
        worker = Task { [weak self] in
            while !Task.isCancelled, let next = self?.takePending() {
                guard let compute = self?.compute else { break }
                let output = await Task.detached(priority: .userInitiated) {
                    compute(next)
                }.value
                // Checked after the await — the danger is work finishing
                // once the scene it was for is gone.
                guard !Task.isCancelled else { break }
                let applied = ContinuousClock.now
                self?.apply(output)
                // Paced: the worker rests out the interval (the main thread
                // does not), and whatever arrived meanwhile goes next.
                if let interval = self?.minimumInterval, interval > 0 {
                    let rest = Duration.seconds(interval) - (ContinuousClock.now - applied)
                    if rest > .zero { try? await Task.sleep(for: rest) }
                }
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

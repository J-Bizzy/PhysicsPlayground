//
//  Settle.swift
//  RenderKit
//
//  Whether a freshly built scene has finished arriving. The first frames
//  after a scene mounts run long — 30 to 250 ms in the simulator, every
//  lab and the home alike — while the engine takes in thousands of new
//  entities, and anything that fades or moves through those frames
//  stutters. So a scene shows itself only once it has run a few frames in
//  a row inside the budget, or a second's worth of frames have passed
//  whatever the pacing. Fed each frame's real delta, before any clamp.
//

public struct Settle: Sendable {
    /// A frame inside this is clean: half again a 90 Hz frame.
    public static let budget = 1.5 / 90.0
    /// How many clean frames in a row settle a scene.
    public static let cleanFrames = 12
    /// Settled after this many frames whatever they took, so a device
    /// that never quite makes the budget still shows the scene. Frames,
    /// not seconds: one multi-second delta after the space presents would
    /// spend a time cap at once.
    public static let frameCap = 60

    /// What a scene waits at: drawn, so its first visible frame does not
    /// pay for preparing everything it draws (at 0 the engine skips it, and
    /// that frame ran 40–50 ms), but too faint to be seen.
    public static let hiddenOpacity: Float = 0.005

    public private(set) var isSettled = false
    private var clean = 0
    private var frames = 0

    public init() {}

    /// Counts one frame of `dt` seconds; true once settled, and from then on.
    @discardableResult
    public mutating func tick(dt: Double) -> Bool {
        guard !isSettled else { return true }
        frames += 1
        clean = dt < Self.budget ? clean + 1 : 0
        if clean >= Self.cleanFrames || frames >= Self.frameCap {
            isSettled = true
            #if DEBUG
            print("[frames] settled after \(frames) frames")
            #endif
        }
        return isSettled
    }
}

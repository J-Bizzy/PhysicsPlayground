# Archive — cut from the shelf, kept on disk

Modules removed in the 2026-07-28 remaster, with the reason each failed
the "strongly three-dimensional" test:

- **Springs** — a block on a rail is a ONE-dimensional oscillator.
- **ElasticField** — a membrane is two-dimensional.
- **Optics** — an optical bench is a line of elements in a row.
- **Waves** — returned once as a walkable interference volume, then cut
  again on 2026-07-29 when the app narrowed to two labs (E&M and
  Mechanics). Its dot lattice sampled the field at 1.11 points per
  wavelength — below Nyquist — so adjusting frequency re-aliased the
  picture instead of informing it, and that could not be tuned out at a
  729-dot budget over a 2.4 m region. `PhysicsCore/Waves` keeps the
  physics: exact retarded-time Doppler, the phasor decomposition,
  `DoubleSlit`. Its tests live in `Archive/Tests`.
- **Optics** — stays archived; not returning with the two-lab scope.
  `PhysicsCore/Optics` still holds full 3-D ray tracing, tested.
- **WindTunnel** — cut 2026-07-30, owner's call, and the only one here
  removed for scope rather than for a defect: the app ships two labs,
  Electricity & Magnetism and Mechanics & Energy, and a wind tunnel
  belongs to neither. It worked. `PhysicsCore/Fluids` is deliberately
  NOT pruned — `FluidGrid`, `DragBody` and `SurfacePressure` stay on
  disk and their tests keep running in `swift test`, so reviving this
  costs a module folder rather than a rebuild. Note this also retires
  the outstanding `WindTunnelRenderer.planePoint(fromWorld:)` scale-rig
  prerequisite recorded in `DECISIONS.md` (2026-07-29).
- **Fields / Oscillators** — the old merged-module wrappers, already
  unused since the modules were split back apart.

Nothing here is deleted. The physics these leaned on lives in
PhysicsCore and is still fully tested. To restore a module: move its
folder back under `PhysicsPlayground/Modules/`, add its one line to
`ModuleCatalog.all`, and its id to `HubDomain.moduleIDs`.

**These are snapshots, not living code.** Nothing here compiles — the
`Archive/` tree sits outside the Xcode synchronized root — so an
archived module can go stale against the app that moved on without it,
and restoring one may mean repairing it first. The standing example:
`Archive/Fields/FieldsModule.swift` still calls `MagnetismSpaceView`,
which was deleted when Magnetism became a station of the E&M world. A
restore is a merge, not a `git mv`.

## Models

`Archive/Models/` holds the USDZ a cut module was drawn with — Optics,
WindTunnel and Waves, moved here on 2026-08-01. They were still sitting
in `PhysicsPlayground/Models/`, which is a `PBXFileSystemSynchronizedRootGroup`:
everything under it is copied into the bundle whether or not any code
loads it, so ~1.1 MB of geometry for three modules that do not exist was
shipping in every build. Nothing referenced them — the only USDZ the app
loads are `Models/Circuits/*` (`CircuitsRenderer`) and
`Models/Kinematics/LauncherBarrel.usdz` (`KinematicsRenderer`).

They are MOVED rather than deleted so the restore path above stays whole:
bring the folder back to `PhysicsPlayground/Models/` along with the
module's own folder.

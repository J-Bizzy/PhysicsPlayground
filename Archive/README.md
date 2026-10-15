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
- **Optics** — stayed archived until 2026-10-14, when Light & Optics
  returned as a new lab (`Modules/Optics`) built on a new room-scale
  tracer, `PhysicsCore/Optics/LightTracer`. The bench files here stay
  archived: they assume the line of elements that got them cut.
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

## What PhysicsCore still carries for these, in full

The Fluids note above was the only place this was written down, which
made it read as a decision about the wind tunnel rather than the policy
it actually is. Audited 2026-08-09: **seventeen source files and about
110 tests in `PhysicsCore` exist only for archived modules.** No app
module reaches any of them; they compile into the library and run on
every `swift test`.

| Area | Files | Tests |
|---|---|---|
| Optics | `RayOptics`, `RayOptics3D`, `Prism`, `GlassBlock`, `Refraction` | 23 |
| Waves | `DoubleSlit`, `WaveField`, `EmissionTrail` | 17 |
| Fluids | `FluidGrid`, `SurfacePressure`, `PotentialFlow` | 29 + `FluidGridBench` |
| Magnetism (unused half) | `Induction`, `CurrentLoop` | 12 |
| Math | `MarchingSquares`, `Isosurface`, `StreamlineTracer` | 28 |
| Oscillations | `ElasticSheet` | 13 |

Kept on purpose, for the reason the Fluids line gives — reviving a
module should cost a module folder, not a rebuild — and because this is
real, exact, tested physics that happens not to have a room right now.
The cost is seconds on the fast suite and zero bytes in the app: none
of it is linked into anything the six modules reach.

Two things that are NOT in that table, because they look archived and
are not: `DragBody` is live (`ObstacleField`, in `Shell/RoomModel`),
and `StationBox` is live (`DesignSystem/InstrumentRail`). Deleting
either while "pruning the wind tunnel" would break the shipping app.

`FluidGridBench` is the one genuinely stale item — a timing probe
measuring `FluidGrid` "at the size the wind tunnel actually runs", and
nothing runs that size. It is a benchmark for a resolution the app does
not use.

Nothing here is deleted. The physics these leaned on lives in
PhysicsCore and is still fully tested. To restore a module: move its
folder back under `PhysicsPlayground/Modules/`, add its one line to
`ModuleCatalog.all`, and its id to `HubDomain.moduleIDs` — and recover
its hub miniature from git history: the five archived vignette builders
were deleted from `HubVignettes.swift` on 2026-08-03 (they were the one
piece of archive still compiled into the shipping binary), so a restore
also means reviving the module's builder and its `make(for:)` case from
the commit that removed them.

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

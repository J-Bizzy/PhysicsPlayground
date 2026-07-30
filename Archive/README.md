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
- **Fields / Oscillators** — the old merged-module wrappers, already
  unused since the modules were split back apart.

Nothing here is deleted. The physics these leaned on lives in
PhysicsCore and is still fully tested. To restore a module: move its
folder back under `PhysicsPlayground/Modules/`, add its one line to
`ModuleCatalog.all`, and its id to `HubDomain.moduleIDs`.

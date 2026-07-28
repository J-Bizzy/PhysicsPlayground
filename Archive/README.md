# Archive — cut from the shelf, kept on disk

Modules removed in the 2026-07-28 remaster, with the reason each failed
the "strongly three-dimensional" test:

- **Springs** — a block on a rail is a ONE-dimensional oscillator.
- **ElasticField** — a membrane is two-dimensional.
- **Optics** — an optical bench is a line of elements in a row.
- **Waves** — cut pending a rebuild as an interference VOLUME you stand
  inside, rather than a plane of ripples. Scheduled to return.
- **Fields / Oscillators** — the old merged-module wrappers, already
  unused since the modules were split back apart.

Nothing here is deleted. The physics these leaned on lives in
PhysicsCore and is still fully tested. To restore a module: move its
folder back under `PhysicsPlayground/Modules/`, add its one line to
`ModuleCatalog.all`, and its id to `HubDomain.moduleIDs`.

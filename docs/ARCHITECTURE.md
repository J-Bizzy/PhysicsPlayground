# Architecture

Deeper structure for Physics Playground. Read this before adding a module or moving code between layers.

## Layer rule

```
PhysicsCore → RenderKit → App target
```

The dependency points one way only. **PhysicsCore never imports RealityKit or SwiftUI** — that's what keeps `swift test` fast. Physics types are explicitly `nonisolated`; this project infers `@MainActor` on unannotated types, so the omission is deliberate, not an oversight.

## Module contract

Every lab is a `ModuleDescriptor`: a catalog card, `makeControls`/`makeScene`, and shared closures (`isPaused`/`togglePause`, `reset`, `captureReadings`). The shell renders all other chrome identically by construction — a module supplies only its physics and its scene. Four files per module (`<Name>Model`, `<Name>Module`, `<Name>Renderer`, `<Name>SpaceView`), registered with one line in `ModuleCatalog.all`. Six experiences ship, grouped behind the Home Screen's two domain doors (`HubDomain`).

### One apparatus per room, and the one wired pair

**An experience gets the room to itself.** The app tried the alternative — merged "worlds" standing two and three benches in one room with a focus mechanic deciding which was attended to — and undid it for geometry, with the measurement recorded in `DECISIONS.md` (2026-07-30): every bench ended a step out of reach, and the orrery proved impossible outright. Domain grouping lives at the front door now, not in the room.

The exception is **wiring, not layout**: an experience may summon a partner apparatus it is physically cabled to. `Modules/Circuits/EMFieldStation` + `EMFeedLine` are the pattern — Circuit Workshop's electromagnet switch stands the magnetic field up beside the bench, cabled to the inductor, and folds it away again (`isEnabled`, never mid-gesture teardown). Rules a wired pair must keep, each held by `CircuitsCoilAnnexTests` or a comment at the code it governs:

- The pair's volumes stay **disjoint** (`PhysicsCore.StationBox` — general AABB/containment/reach math, testable in `swift test` without a simulator), and the summoned apparatus is within a step.
- Gestures route by walking the hit entity up to its owning root, and the scale rig is **routed** — `spatialScale(rigs:routing:)`, never `spatialScale(_:)`, which targets any entity and would zoom both apparatus on one pinch.
- The host solves first, so the cable carries **this frame's** current, not last frame's.
- Pause freezes the pair together — a frozen circuit driving a live magnet is a frame of physics that never happened.
- Placement is a **constant** translation of the summoned root (safe because every grab is a `RelativeDrag` — hand *displacement* — which a constant offset leaves untouched; an animating one would slide a held body out from under the fingers).

Model-level clamps back every declared footprint (`CircuitsModel.buildHalfExtents`, `FieldModel.regionHalfExtents` — held by `CircuitsModelTests` and `FieldClampTests`). The merged worlds forced these into existence and they are kept on purpose: a charge that could be dragged across the room was a bug with or without a neighbour.

## Conventions

- **Room-scale only, always.** No tables, planes, or miniature dioramas. This has regressed multiple times — don't reintroduce it.
- **Vector/color language is fixed and owned by `VectorPalette`:** red = positive/N-pole, blue = negative, green/purple = ± test probe, arrow length + brightness = field strength. Colors come from `DesignTokens`, never ad hoc.
- **The per-frame path touches only entity transforms.** Mesh regeneration, field-line tracing, and isosurfaces go through `RenderKit.GeometryPipeline`'s background worker, never inline in the render tick.
- **`RealityView`'s `update:` closure is unreliable** for continuous animation. Tick from `SceneEvents.Update` for anything that must animate while idle.
- **A stopped ARKit `DataProvider` can never be restarted.** Route every room-sensing need through `RoomModel.retain()`/`release()`; never spin up a private `ARKitSession`.
- **Default apparatus placement** is roughly a 0.9 m cube centered at `(0, 1.3, −1.0)` in immersive-space coordinates; `LabPlacement` lets the user relocate a lab from there.
- **`Archive/` is not dead code.** Cut modules keep their tested physics in `PhysicsCore`. Restoring one: move the folder back, add its line to `ModuleCatalog.all` and its id to the hub's domain list. See `Archive/README.md`.

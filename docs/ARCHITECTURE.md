# Architecture

Deeper structure for Physics Playground. Read this before adding a module or moving code between layers.

## Layer rule

```
PhysicsCore → RenderKit → App target
```

The dependency points one way only. **PhysicsCore never imports RealityKit or SwiftUI** — that's what keeps `swift test` fast. Physics types are explicitly `nonisolated`; this project infers `@MainActor` on unannotated types, so the omission is deliberate, not an oversight.

## Module contract

Every lab is a `ModuleDescriptor`: a catalog card, `makeScene`, and shared closures (`isPaused`/`togglePause`, `reset`, `captureReadings`). The shell renders all other chrome identically by construction — a module supplies only its physics and its scene.

**A module has no flat control surface.** `makeControls` and the six `*ControlsPanel.swift` were deleted on 2026-08-01: a module's window is a title bar, plus "Show in room" while the immersive space is closed and the first-run hint until it is dismissed. Every control and every readout stands on the apparatus — a plate, a rail, a disc, a well, a petal, a `Callout`, or a RealityView attachment. `PanelControlCriterionTests` fails the build if a panel comes back, and it states the cost the decision accepted: there is no fallback surface, so a regression in a spatial instrument has nowhere to fall back to. Four files per module (`<Name>Model`, `<Name>Module`, `<Name>Renderer`, `<Name>SpaceView`), registered with one line in `ModuleCatalog.all`. Six experiences ship, grouped behind the Home Screen's two domain doors (`HubDomain`).

### One apparatus per room

**An experience gets the room to itself.** The app tried the alternative — merged "worlds" standing two and three benches in one room with a focus mechanic deciding which was attended to — and undid it for geometry, with the measurement recorded in `DECISIONS.md` (2026-07-30): every bench ended a step out of reach, and the orrery proved impossible outright. Domain grouping lives at the front door now, not in the room. No module reaches into another's model.

Model-level bounds are split by WHO they bind (2026-08-03, superseding the merged-worlds-era drag clamps — see DECISIONS.md). A hand meets no invisible wall: drags in Electric Fields and Magnetism obey the hand exactly, floored only by the real floor. What remains clamped is the FREE simulation — room-scale safety boxes (`FieldModel.safetyHalfExtents`, `MagnetismModel.safetyHalfExtents`) that keep drifting charges and gliding magnets from sailing to infinity, held by `FieldClampTests` and `MagnetismInertiaTests`. The nominal region boxes (`FieldModel.regionHalfExtents`, `CircuitsModel.buildHalfExtents`) survive as layout references — instrument clearance is still measured against them.

## Conventions

- **Room-scale only, always.** No tables, planes, or miniature dioramas. This has regressed multiple times — don't reintroduce it.
- **Vector/color language is fixed and owned by `VectorPalette`:** red = positive/N-pole, blue = negative, green/purple = ± test probe, arrow length + brightness = field strength. Colors come from `DesignTokens`, never ad hoc.
- **The per-frame path touches only entity transforms.** Mesh regeneration, field-line tracing, and isosurfaces go through `RenderKit.GeometryPipeline`'s background worker, never inline in the render tick.
- **`RealityView`'s `update:` closure is unreliable** for continuous animation. Tick from `SceneEvents.Update` for anything that must animate while idle.
- **A readout is a `Callout` (one line, tethered) or a RealityView attachment (a card).** Three rules for an attachment, all learned the hard way: `.allowsHitTesting(false)`, because an attachment carries a collider for its content and a readout that intercepts a pinch is `SpatialScaleHandle` again; `.environment(model)` explicitly, because the environment does not flow into an attachment the way it flows down a view tree; and **quantise every live value to its displayed precision**, because an attachment is rasterised into a texture and what costs is how often the rendered output changes, not how often `body` runs. If the anchor hangs under a scale rig, compensate — position rides the rig, size must not.
- **A stopped ARKit `DataProvider` can never be restarted.** Route every room-sensing need through `RoomModel.retain()`/`release()`; never spin up a private `ARKitSession`.
- **Default apparatus placement** is roughly a 0.9 m cube centered at `(0, 1.3, −1.0)` in immersive-space coordinates; `LabPlacement` lets the user relocate a lab from there.
- **`Archive/` is not dead code.** Cut modules keep their tested physics in `PhysicsCore`. Restoring one: move the folder back, add its line to `ModuleCatalog.all` and its id to the hub's domain list. See `Archive/README.md`.

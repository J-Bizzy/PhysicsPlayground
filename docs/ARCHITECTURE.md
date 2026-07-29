# Architecture

Deeper structure for Physics Playground. Read this before adding a module or moving code between layers.

## Layer rule

```
PhysicsCore → RenderKit → App target
```

The dependency points one way only. **PhysicsCore never imports RealityKit or SwiftUI** — that's what keeps `swift test` fast. Physics types are explicitly `nonisolated`; this project infers `@MainActor` on unannotated types, so the omission is deliberate, not an oversight.

## Module contract

Every lab is a `ModuleDescriptor`: a catalog card, `makeControls`/`makeScene`, and shared closures (`isPaused`/`togglePause`, `reset`, `captureReadings`). The shell renders all other chrome identically by construction — a module supplies only its physics and its scene. Four files per module (`<Name>Model`, `<Name>Module`, `<Name>Renderer`, `<Name>SpaceView`), registered with one line in `ModuleCatalog.all`.

## Conventions

- **Room-scale only, always.** No tables, planes, or miniature dioramas. This has regressed multiple times — don't reintroduce it.
- **Vector/color language is fixed and owned by `VectorPalette`:** red = positive/N-pole, blue = negative, green/purple = ± test probe, arrow length + brightness = field strength. Colors come from `DesignTokens`, never ad hoc.
- **The per-frame path touches only entity transforms.** Mesh regeneration, field-line tracing, and isosurfaces go through `RenderKit.GeometryPipeline`'s background worker, never inline in the render tick.
- **`RealityView`'s `update:` closure is unreliable** for continuous animation. Tick from `SceneEvents.Update` for anything that must animate while idle.
- **A stopped ARKit `DataProvider` can never be restarted.** Route every room-sensing need through `RoomModel.retain()`/`release()`; never spin up a private `ARKitSession`.
- **Default apparatus placement** is roughly a 0.9 m cube centered at `(0, 1.3, −1.0)` in immersive-space coordinates; `LabPlacement` lets the user relocate a lab from there.
- **`Archive/` is not dead code.** Cut modules keep their tested physics in `PhysicsCore`. Restoring one: move the folder back, add its line to `ModuleCatalog.all` and its id to the hub's domain list. See `Archive/README.md`.

# Architecture

Deeper structure for Physics Playground. Read this before adding a module or moving code between layers.

## Layer rule

```
PhysicsCore → RenderKit → App target
```

The dependency points one way only. **PhysicsCore never imports RealityKit or SwiftUI** — that's what keeps `swift test` fast. Physics types are explicitly `nonisolated`; this project infers `@MainActor` on unannotated types, so the omission is deliberate, not an oversight.

## Module contract

Every lab is a `ModuleDescriptor`: a catalog card, `makeScene`, shared closures (`isPaused`/`togglePause`, `reset`, `readings`), and its secondary controls (`more`, `adjustables`). The shell renders all other chrome identically by construction — a module supplies only its physics and its scene.

**A module draws no controls of its own.** The room holds the apparatus; the title bar's More holds everything secondary, and the shell draws it. A module *declares* its secondary controls as `ModuleDescriptor.more` items (toggle, verb, choice, slider) and its no-extent quantities as `adjustables`, and the shell renders both in the one control family (`RenderKit/Controls`) inside `Shell/LabMorePanel.swift`, beside its live `readings`. A value an object can carry is changed by handling the object — a grip on its surface, a drag — never by a slider for it (2026-10-14, `docs/redesign-audit.md`). `PanelControlCriterionTests` fails the build if a module source builds a flat control, and `ControlLanguageCriterionTests` fails it if anything in the app draws a control outside the family. Four files per module (`<Name>Model`, `<Name>Module`, `<Name>Renderer`, `<Name>SpaceView`), registered with one line in `ModuleCatalog.all`. Seven experiences ship, as seven portals on the home, ordered by domain (`HubDomain`).

### One apparatus per room

**An experience gets the room to itself.** The app tried the alternative — merged "worlds" standing two and three benches in one room with a focus mechanic deciding which was attended to — and undid it for geometry, with the measurement recorded in `DECISIONS.md` (2026-07-30): every bench ended a step out of reach, and the orrery proved impossible outright. Domain grouping lives at the front door now, not in the room. No module reaches into another's model.

Model-level bounds are split by WHO they bind (2026-08-03, superseding the merged-worlds-era drag clamps — see DECISIONS.md). A hand meets no invisible wall: drags in Electric Fields, Magnetism and Circuit Workshop obey the hand exactly, floored only by the real floor. What remains clamped is the FREE simulation — room-scale safety boxes (`FieldModel.safetyHalfExtents`, `MagnetismModel.safetyHalfExtents`, `CircuitsModel.safetyHalfExtents`) that keep drifting charges, gliding magnets and released parts from sailing to infinity, held by `FieldClampTests`, `MagnetismInertiaTests` and `CircuitsModelTests`. The nominal region boxes (`FieldModel.regionHalfExtents`, `CircuitsModel.buildHalfExtents`) survive as layout references — instrument clearance is still measured against them, and a reset lays its apparatus out inside them.

**This paragraph described Circuits for three weeks before Circuits complied** (fixed 2026-08-26). `buildHalfExtents` was still a hand clamp, and the visible cost was a part pulled from the rack being born 12 cm from your fingers — a jump that could not be fixed by moving the rack, since the clearance rule puts the rack outside the box by construction. If you are adding a module, the split is the rule, not the aspiration.

## Conventions

- **Room-scale only, always.** No tables, planes, or miniature dioramas. This has regressed multiple times — don't reintroduce it. **One owner-chosen exception (2026-10-18):** Circuit Workshop's turntable — a slim disc that hovers under the still-floating circuit as its container and its handle (spin it, carry it), never a surface parts rest on. It does not license a table anywhere else.
- **Vector/color language is fixed and owned by `VectorPalette`:** red = positive/N-pole, blue = negative, green/purple = ± test probe, arrow length + brightness = field strength. Colors come from `DesignTokens`, never ad hoc.
- **The per-frame path touches only entity transforms.** Mesh regeneration, field-line tracing, and isosurfaces go through `RenderKit.GeometryPipeline`'s background worker, never inline in the render tick. The one stated exception (2026-09-06): a bounded ring-buffer mesh rewritten in place through RealityKit's `LowLevelMesh` — `RenderKit.TrailRibbons`, Orbital Mechanics' trails, every body a part of one mesh so a frame is one write per buffer (2026-10-17) — is a buffer write, not regeneration, and belongs on the tick.
- **`RealityView`'s `update:` closure is unreliable** for continuous animation. Tick from `SceneEvents.Update` for anything that must animate while idle.
- **A readout is a `Callout` (one line, tethered) or a RealityView attachment (a card).** Three rules for an attachment, all learned the hard way: `.allowsHitTesting(false)`, because an attachment carries a collider for its content and a readout that intercepts a pinch is `SpatialScaleHandle` again; `.environment(model)` explicitly, because the environment does not flow into an attachment the way it flows down a view tree; and **quantise every live value to its displayed precision**, because an attachment is rasterised into a texture and what costs is how often the rendered output changes, not how often `body` runs. If the anchor hangs under a scale rig, compensate — position rides the rig, size must not.
- **A stopped ARKit `DataProvider` can never be restarted.** Route every room-sensing need through `RoomModel.retain()`/`release()`; never spin up a private `ARKitSession`.
- **Default apparatus placement** is roughly a 0.9 m cube centered at `(0, 1.3, −1.0)` in immersive-space coordinates; `LabPlacement` lets the user relocate a lab from there.
- **`Archive/` is not dead code.** Cut modules keep their tested physics in `PhysicsCore`. Restoring one: move the folder back, add its line to `ModuleCatalog.all` and its id to the hub's domain list. See `Archive/README.md`.

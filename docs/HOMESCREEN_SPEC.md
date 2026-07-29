# Physics Playground — Homescreen Spec (v3)

Target: visionOS (Vision Pro), mixed-immersion home space.

**History.** v2 was written from a screenshot of the pre-rebuild homescreen, with no knowledge of the codebase. The rebuild has since shipped most of v2's intent — often deliberately in a different shape, with the reasoning recorded in code comments. v3 replaces v2: §1 documents what is actually built, §2 locks the decisions that diverged from v2, §3 is the surviving open work. The full v2-vs-code conflict analysis lives in the 2026-07-29 planning notes; visual values (color, type, motion) live in `DESIGN_SYSTEM.md`.

---

## 1. The homescreen as built

Two rendering paths; the spatial one is primary:

- **The constellation** (`Hub/HubSpaceView.swift`) — the immersive-space hub. `HubView` auto-opens the immersive space on arrival, so this is what users see.
- **The 2D fallback** (`Hub/HubView.swift`) — a plain window with a bare floating title and a two-column glass grid of the modules, used before/without the immersive space.

### Exhibits

Eight modules (`ModuleCatalog.all`), each shown as a **shell-free live miniature** — a running procedural mini-simulation of that lab (`Hub/HubVignettes.swift`), not an icon or a card. Miniatures are normalized to a constant 0.27 m world size and placed at **authored constellation slots** at genuinely different azimuths, heights (0.96–1.94 m), and depths (1.62–3.05 m), scaled by the `arcDistance`/`arcHeight` settings. Domain order assigns slots, so related labs sit near each other. Each exhibit wears a domain-colored progress ring (gold when the module's experiments are complete) and a billboarded name plate.

### Focus (the "what can this do" answer)

A head-direction focus mechanic, not eye-gaze hover: the exhibit nearest the user's look ray (26° cone, with hysteresis; `RoomModel`'s head pose) grows, steps toward the user, and lights an accent halo; the others recede and their names fade. The focused exhibit reveals a billboarded glass **focus panel**: module name, domain chip, one-line promise (`HubDomains.promise`), progress gauge with "N of M experiments", a "New" badge or last-played timestamp, and an **Enter** button.

### Entering a module

Pinch the exhibit or its Enter button → the exhibit swells toward the user (0.42 s, with a pop sound), then the scene swaps to the full room-scale module. An arrival, not a hard cut.

### Persistent chrome

**The Palette bead** (`Shell/Palette.swift`) — a single small glass sphere, the app's only permanent piece of interface, at a fixed spot low and to the right. Pinch it and it unfolds into a ring of the labs' own live miniatures plus exactly two petals, pause and reset. Inside a module, the 2D window shows a floating title bar (`Shell/ModuleHostView.swift`): back, module switcher, place-lab, Studio Mode, reset-with-confirm.

### Title

A two-line 3D bubble wordmark ("Physics / Playground") floats above the constellation center — **on first launch only** (`hasSeenWordmark`). After that, the room's contents identify the app.

### Comfort

`scene.stillness` stills the hub's idle motion when either the app's reduce-motion setting or the system setting is on (`HubSpaceView.swift:46`).

---

## 2. Locked decisions

These diverge from v2 deliberately. Don't revisit one without adding a `DECISIONS.md` entry saying why.

1. **Constellation, not arc.** One radius + one height "is a poster with a curve in it" (`HubSpaceView.swift:191`). Slots are authored, not generated.
2. **Shell-free exhibits, not cards.** The exhibits wore cards for a while; the furniture is gone (`HubSpaceView.swift:614`). The hover glow lights the physics itself.
3. **No floating domain headers.** Labels explaining a grouping the colors already carry are exactly the caption the rebuild deletes (`HubSpaceView.swift:273`). Domain color survives on the ring and the panel chip.
4. **The bead, not a dock.** The app already had a six-affordance persistent rail and killed it for one bead with two petals (`Palette.swift:7-19`). v2's dock would reverse that. The dock's *contents* that matter became §3's open work instead.
5. **No Quick Demo button.** Every exhibit *is* a perpetual live demo.
6. **Focus, not hover.** Head-direction cone with hysteresis instead of `HoverEffectComponent` gaze values — works in the simulator, testable, legible at room scale. Values in `DESIGN_SYSTEM.md`.
7. **One-shot wordmark.** Persistent branding fails the spec's own keep-the-room-calm rule.
8. **No Search, no Daily Challenge surface.** Eight modules are all visible at once; challenges were rebuilt as the experiments layer. The unused `streak`/`nextStep` engines (`Shell/Experiments.swift`) are raw material if motivation surfacing is ever wanted.
9. **Procedural vignettes, not `.usdz`; `RoomModel` for head pose, never a private `ARKitSession`; animation ticked from `SceneEvents.Update`.** v2 §8's implementation notes are void where they conflict with `docs/ARCHITECTURE.md`.

## 3. Open work (the surviving spec)

In priority order. Each is its own scoped task.

1. **Lab Notebook surface.** The model is fully built (`Shell/LabNotebook.swift`: record, CSV/Markdown export, persistence) and every module supplies `captureReadings` — but nothing calls either. Needs: a capture trigger reachable mid-experiment, and a view to read/export entries. Where the trigger lives (a third bead petal? the title bar?) is a design decision to make against locked decision 4.
2. **Coach-mark rendering.** The state machine exists and advances at the right moments (`AppSettings.coachStage`; advanced on first focus and first module entry) but no view renders a tip. Script, unchanged from v2: ① "Look at a module to preview it" ② "Pinch to step inside" ③ "Track everything in your Lab Notebook". Never shown again after completion.
3. **Settings window.** First real UI over `AppSettings`. Scope is what the model actually holds: reduce motion, master/ambient volume, arc distance & height, recenter, reset onboarding tips — plus destructive reset of experiment progress (confirm dialog). Dropped from v2: SI/Imperial units (the app's identity is exact SI physics), language, voice narration, dominant hand.
4. **Constellation slot wrap.** 7 authored slots, 8 modules — `constellationPoint` wraps with `index % count` (`HubSpaceView.swift:222`), so the 8th module reuses slot 0's exact position and two exhibits can overlap. Author an 8th slot.

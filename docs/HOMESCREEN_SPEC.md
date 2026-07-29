# Physics Playground — Homescreen Spec (v4)

Target: visionOS (Vision Pro), mixed-immersion home space.

**History.** v3 (2026-07-29) documented the rebuilt constellation homescreen and locked its decisions. Later the same day, user direction called for a flagship-quality redesign with a persistent title; the result is the **Gallery**, which replaces the constellation. v4 documents the Gallery as built. Decisions that changed have entries in `DECISIONS.md` (same date); visual values live in `DESIGN_SYSTEM.md`.

---

## 1. The homescreen as built

Two rendering paths; the spatial one is primary:

- **The Gallery** (`Hub/HubSpaceView.swift`, geometry in `Hub/GalleryLayout.swift`) — the immersive-space hub. `HubView` auto-opens the immersive space on arrival.
- **The 2D front door** (`Hub/HubView.swift`) — the plain window, shown only before/without the immersive space: app name and tagline, an "Enter the Gallery" button, a domain-grouped catalog with per-module experiment progress, and an inline error banner with manual Retry if the space fails to open (the failure used to be swallowed silently).

### The Gallery

A crescent of **four floating graphite terraces**, one per `HubDomain`, arcing around the user at azimuths −54°/−18°/+18°/+54°, at slightly varied radii (1.90–2.05 m at the default distance) and slab-top heights (0.92–1.12 m at the default height). Each terrace:

- is a dark rounded slab (0.42 m deep, 0.055 m thick) with a **domain-coloured emissive hairline** along its front-top edge — the only place domain colour lives besides the progress ring and the focus panel chip; there are still no floating text headers;
- carries one **pedestal puck** per module (r 0.085 m, 0.36 m pitch), each holding the module's **shell-free live miniature** (`Hub/HubVignettes.swift`), normalized to a constant 0.24 m world size, with a billboarded bubble-type name plate in front of the puck and the domain-coloured **progress ring** (gold when complete).

Slab widths derive from module counts (`0.36·n + 0.08`); a module outside every domain extends its fallback domain's slab, so the old slot-wrap overlap bug is structurally impossible (`GalleryLayoutTests`). The **distance setting scales the crescent's plan** (radials, widths, pitch) and the **height setting scales terrace heights**; exhibits keep constant world size. A soft warm pool of light on the real floor ties the crescent to the room.

### Title

The two-line 3D bubble wordmark ("Physics / Playground", 0.60 m wide, champagne rule beneath) floats **permanently** above the crescent's centre (≈2.1 m at defaults). The one-shot `hasSeenWordmark` behavior is deleted.

### Focus

Unchanged mechanic (head-direction cone 26° with hysteresis, `RoomModel`'s look ray; `-hubFocus <id>` pins it in the simulator), retuned expression: the focused exhibit **lifts 0.09 m off its puck** and scales to 1.22, a pool of its accent light appears on the pedestal, others recede and their names fade. The single billboarded glass **focus panel** (`HubFocusPanel`) is unchanged: domain chip, promise line, N-of-M progress dial, New/last-played badge, Enter button.

### Entering

Pinch the exhibit or its Enter button → 0.42 s swell-and-rise with a pop, the terrace's hairline flares, then the scene swaps to the module.

### Idle life & comfort

Miniatures breathe ±8 mm on desynced periods and run their physics; hairlines shimmer slowly; the title bobs. All idle motion is stilled by `scene.stillness` (in-app reduce-motion setting or the system switch). Everything ticks from one `SceneEvents.Update` subscription (`[weak scene]`, cancelled on disappear).

### Persistent chrome

Unchanged from v3: the **Palette bead** (`Shell/Palette.swift`) with three petals — pause, settings (gear, opens the settings window), reset — and the module window's floating title bar (`Shell/ModuleHostView.swift`), which now also hosts an optional per-module flat control panel (`ModuleDescriptor.makeControls`; Electric Fields is the first user).

---

## 2. Locked decisions (v4 status)

Numbering from v3. Don't revisit a standing one without a `DECISIONS.md` entry.

1. ~~Constellation, not arc~~ — **superseded**: the Gallery's terraces (DECISIONS 2026-07-29). Slots are still authored, still not a single-radius poster.
2. **Shell-free exhibits, not cards** — stands, amended in scope: the terraces are architecture *beneath* the miniatures, never framing around them.
3. **No floating domain headers** — stands: domain colour is carried by the hairline, ring, and chip; no text labels.
4. **The bead, not a dock** — stands (amended once: the settings gear petal, DECISIONS 2026-07-29).
5. **No Quick Demo button** — stands; every exhibit is a perpetual live demo.
6. **Focus, not hover** — stands, unchanged mechanic.
7. ~~One-shot wordmark~~ — **reversed**: the wordmark is persistent (DECISIONS 2026-07-29).
8. **No Search, no Daily Challenge surface** — stands.
9. **Procedural vignettes; `RoomModel` for head pose; `SceneEvents.Update` ticking** — stands.

## 3. Open work

1. **Lab Notebook surface.** Unchanged from v3: the model is fully built (`Shell/LabNotebook.swift`) and every module supplies `captureReadings`, but nothing calls either. The trigger's home is a design decision against locked decision 4.
2. **Coach-mark rendering.** The state machine exists (`AppSettings.coachStage`, advanced on first focus and first module entry — both triggers survive in the Gallery) but no view renders a tip. Script: ① "Look at a module to preview it" ② "Pinch to step inside" ③ "Track everything in your Lab Notebook". Anchors must target the Gallery layout.
3. **Ambient volume (continuous).** The settings window ships master volume + ambient on/off; a continuous ambient level awaits a gain path into the ambient loop.

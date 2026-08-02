# Physics Playground — Homescreen Spec (v4)

Target: visionOS (Vision Pro), mixed-immersion home space.

**History.** v3 (2026-07-29) documented the rebuilt constellation homescreen and locked its decisions. Later the same day, user direction called for a flagship-quality redesign with a persistent title; the result is the **Gallery**, which replaces the constellation. v4 documents the Gallery as built. Decisions that changed have entries in `DECISIONS.md` (same date); visual values live in `DESIGN_SYSTEM.md`.

---

## 1. The homescreen as built

Two rendering paths; the spatial one is primary:

- **The Gallery** (`Hub/HubSpaceView.swift`, geometry in `Hub/GalleryLayout.swift`) — the immersive-space hub. `HubView` auto-opens the immersive space on arrival.
- **The 2D front door** (`Hub/HubView.swift`) — the plain window, shown only before/without the immersive space: app name and tagline, an "Enter the Gallery" button, a domain-grouped catalog with per-module experiment progress, and an inline error banner with manual Retry if the space fails to open (the failure used to be swallowed silently).

### The Gallery

A crescent of **two floating graphite terraces**, one per `HubDomain`, arcing around the user at azimuths **−28° (Electricity & Magnetism) and +28° (Mechanics & Energy)**, at slightly varied radii (1.95 / 2.05 m at the default distance) and slab-top heights (1.00 / 0.92 m at the default height). Values are authored in `GalleryLayout.slots`.

*(Was four terraces at ±54°/±18° while the catalog held four domains. The catalog was cut to two doors on 2026-07-30 when the merged-worlds geometry failed; the code followed and this paragraph did not, until 2026-08-01.)*

Each terrace:

- is a dark rounded slab (0.42 m deep, 0.055 m thick) with a **domain-coloured emissive hairline** along its front-top edge — one of the four places domain colour lives, alongside the door signage, the progress ring and the focus panel chip;
- carries one **pedestal puck** per module (r 0.085 m, 0.36 m pitch), each holding the module's **shell-free live miniature** (`Hub/HubVignettes.swift`), normalized to a constant 0.24 m world size, with a billboarded bubble-type name plate in front of the puck and the domain-coloured **progress ring** (gold when complete).

Slab widths derive from module counts (`0.36·n + 0.08`); a module outside every domain extends its fallback domain's slab, so the old slot-wrap overlap bug is structurally impossible (`GalleryLayoutTests`). The **distance setting scales the crescent's plan** (radials, widths, pitch) and the **height setting scales terrace heights**; exhibits keep constant world size. A soft warm pool of light on the real floor ties the crescent to the room.

### Title and signage

The two-line wordmark ("Physics / Playground", champagne rule beneath) floats **permanently** above the crescent's centre (≈2.1 m at defaults). The one-shot `hasSeenWordmark` behaviour is deleted.

Its **voice is the machined plaque** — `HubTitleStyle.shipping = .plaque`, pinned in code on 2026-07-31 after an audition against three alternatives. There is no setting; the other voices remain in the enum as what the choice was made against. A plaque is one solid, not a stack.

Each terrace also carries an **animated 3-D door sign** (`HubDomainTitle`) naming its domain, with one kinetic element apiece — an electron lapping the E&M sign, a ball on a true parabola over Mechanics. **This reverses the earlier "no floating domain headers" rule** (2026-07-30), which is why the branding budget was re-opened for exactly two signs. Under reduce-motion the signs park at a composed rest pose rather than freezing mid-flight.

### Focus

Unchanged mechanic (head-direction cone 26° with hysteresis, `RoomModel`'s look ray; `-hubFocus <id>` pins it in the simulator), retuned expression: the focused exhibit **lifts 0.09 m off its puck** and scales to 1.22, a pool of its accent light appears on the pedestal, others recede and their names fade. The single billboarded glass **focus panel** (`HubFocusPanel`) is unchanged: domain chip, promise line, N-of-M progress dial, New/last-played badge, Enter button.

### Entering

Pinch the exhibit or its Enter button → 0.42 s swell-and-rise with a pop, the terrace's hairline flares, then the scene swaps to the module.

### Idle life & comfort

Miniatures breathe ±8 mm on desynced periods and run their physics; hairlines shimmer slowly; the title bobs. All idle motion is stilled by `scene.stillness`, which follows the **system** `accessibilityReduceMotion` switch — the in-app duplicate was deleted and there is no `reduceMotion` in `AppSettings`. Everything ticks from one `SceneEvents.Update` subscription (`[weak scene]`, cancelled on disappear).

### Persistent chrome

Unchanged from v3: the **Palette bead** (`Shell/Palette.swift`) with three petals — pause, settings (gear, opens the settings window), reset — and the module window's floating title bar (`Shell/ModuleHostView.swift`).

**The title bar is now the whole window** (DECISIONS 2026-08-01). `ModuleDescriptor.makeControls` and the six `*ControlsPanel.swift` are deleted; every control and readout stands on the apparatus. The bar gained a **Key** button (the legend, as a popover) and shows a **warning triangle** when the room cannot be sensed. The catalog card carries the next experiment's *step* as well as its title, because the module window no longer has anywhere to put it.

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

1. ~~Lab Notebook surface~~ — **shipped** (2026-07-29): capture petal on the bead (its fourth and final), book button in every module title bar, Notebook window with CSV/Markdown export.
2. ~~Coach-mark rendering~~ — **deleted by decision** (2026-07-29): onboarding is each module's first-run hint, rendered by the shell until dismissed. See DECISIONS.md.
3. ~~Ambient volume (continuous)~~ — **closed as a non-feature** (2026-08-01). Settings ships master volume plus ambient on/off, and that is the whole honest surface: there is no gain path into the ambient loop, so a continuous slider would be a control over nothing. The app deliberately ships no dead slider. If a gain path is ever built, the slider comes with it and not before.
4. ~~Module window panels~~ — **deleted** (2026-08-01). Listed here only so the trail is complete: the window is a title bar, and `PanelControlCriterionTests` fails the build if a panel comes back. `Archive/Models/` now also holds the USDZ of the cut modules, which had been shipping in the bundle.
5. **Pre-public-repo sweep — `Archive/`: DECIDED TO KEEP, and the reasoning is on the record.** It is 30 files and 464 KB, tracked, and **not referenced by the Xcode project at all** — it compiles nothing, ships nothing, and cannot affect the app bundle or a submission. What it holds is five cut modules whose *physics is still live and tested* in `PhysicsCore` (Optics 665 lines, Fluids 1 067, Waves 332, `ElasticSheet` 273, the spring oscillators) — roughly 2 600 of PhysicsCore's 6 573 lines are reachable only from there, and `swift test` exercises every one of them on every run. That is defensible as parked work with a documented restore path and indefensible as an accident, which is why `Archive/README.md` says which it is. **Deleting it is the owner's call, not a cleanup**, and it is the last thing that would need doing before the repo goes public if the answer changes.
   - One genuine grave inside it: `PhysicsCore/Waves/EmissionTrail` has **zero references anywhere**, including the Archive itself.

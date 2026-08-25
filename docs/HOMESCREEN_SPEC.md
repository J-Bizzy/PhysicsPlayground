# Physics Playground — Homescreen Spec (v4)

Target: visionOS (Vision Pro), mixed-immersion home space.

**History.** v3 (2026-07-29) documented the rebuilt constellation homescreen and locked its decisions. Later the same day, user direction called for a flagship-quality redesign with a persistent title; the result is the **Gallery**, which replaces the constellation. v4 documents the Gallery as built. Decisions that changed have entries in `DECISIONS.md` (same date); visual values live in `DESIGN_SYSTEM.md`.

---

## 1. The homescreen as built

Two rendering paths; the spatial one is primary:

- **The Gallery** (`Hub/HubSpaceView.swift`, geometry in `Hub/GalleryLayout.swift`) — the immersive-space hub. `HubView` auto-opens the immersive space on arrival.
- **THERE IS NO 2D FRONT DOOR (2026-08-22).** The app launches straight into the Gallery: `Info.plist` sets `UIApplicationPreferredDefaultSceneSessionRole` to `UISceneSessionRoleImmersiveSpaceApplication`, so the ImmersiveSpace declared first in `PhysicsPlaygroundApp` is the launch scene and the arrival choreography plays unasked. A flat slab asking permission to enter a room-scale place was a door in front of a door. What the space waits on instead is `PropCache` — nothing builds until the cache is warm (`PlaygroundSpaceView.ready`), because `PropCache.prototype` falls back to a synchronous load and a cold gallery parses twenty usdz on Thread 1. The wait is the same length it always was; the user now spends it looking at their own room rather than at a button.
- **The window behind it** (`Hub/HubView.swift`) — reached by "Put the Gallery away" or the Digital Crown, never at launch: app name and tagline, an "Enter the Gallery" button (the way BACK, deliberately kept — deleting it would strand the user who just asked for their room back), a domain-grouped catalog carrying each lab's promise line, and an inline error banner with manual Retry if the space fails to open (the failure used to be swallowed silently). Since 2026-08-07 the catalog stays up, compactly, while the Gallery is in the room — it is the accessibility path, and hiding it was a defect. The per-module experiment progress it used to show went with the experiments on 2026-08-09.

### The Gallery

A crescent of **two floating graphite terraces**, one per `HubDomain`, arcing around the user at azimuths **−28° (Electricity & Magnetism) and +28° (Mechanics & Energy)**, at slightly varied radii (1.95 / 2.05 m) and a **shared** slab-top height of **0.96 m**. Values are authored in `GalleryLayout.slots`.

> The heights were 1.00 / 0.92 and were unified on 2026-08-04 — staggered tops read as uneven rather than as designed. The radii stay varied because that is what makes the crescent read as an arc rather than a wall; the heights were the pair that looked like a mistake. (Spec corrected 2026-08-09; it had described the pre-unification values for five days.)

*(Was four terraces at ±54°/±18° while the catalog held four domains. The catalog was cut to two doors on 2026-07-30 when the merged-worlds geometry failed; the code followed and this paragraph did not, until 2026-08-01.)*

Each terrace:

- is a **modelled optical bench** (0.42 m deep, 0.055 m thick), tiled from a 0.36 m bay per module plus two 0.04 m end caps (`Tools/galleryplatforms.py` → `GalleryBay.usdz`, `GalleryCap.usdz`), T-slotted along its length, with a **domain-coloured emissive hairline** lying in the machined channel along its front rail — one of the two places domain colour lives, alongside the door signage (the progress ring went with the experiments on 2026-08-09; the focus panel's chip was deleted 2026-08-04);
- carries one **three-ball kinematic mount** per module (r 0.085 m, 0.36 m pitch — `GalleryMount.usdz`), each holding the module's **shell-free live miniature** (`Hub/HubVignettes.swift`), normalized to a constant 0.24 m world size, with a billboarded bubble-type name plate in front of the mount.

*(Terraces were plain boxes and the pucks plain cylinders until 2026-08-09. Tiles rather than one asset because the layout sizes a terrace from its module count; nothing here is stretched to fit.)*

Slab widths derive from module counts (`0.36·n + 0.08`); a module outside every domain extends its fallback domain's slab, so the old slot-wrap overlap bug is structurally impossible (`GalleryLayoutTests`). Exhibits keep constant world size (0.24 m) whatever the crescent does.

> **The distance and height SETTINGS are gone**, and so is the floor light pool. Both sentences survived here until 2026-08-09.
>
> The two sliders were replaced by the **grab bar**: you take the gallery in your hands and put it where you want it, which is one gesture instead of two numbers in a settings window, and it is the same verb every lab uses. `arcDistanceDefault` and `arcHeightDefault` are now constants.
>
> The floor pool died because **y = 0 is not the user's floor**. It was drawn at the origin, which lands somewhere between the ankles and the ceiling depending on where the wearer calibrated — a warm light tying the crescent to a plane that is not the room's.

### Title and signage

The two-line wordmark ("Physics / Playground", champagne rule beneath) floats **permanently** above the crescent's centre (≈2.1 m at defaults). The one-shot `hasSeenWordmark` behaviour is deleted.

Its **voice is the machined plaque**, pinned in code on 2026-07-31 after an audition against three alternatives. There is no setting, and since 2026-08-02 there is no enum either — `HubTitleStyle` is a namespace, because a four-case taxonomy with one reachable case is a choice mechanism with nothing to choose.

**Contrast comes from a per-glyph KEYLINE** (`HubTitleStyle.keylined`), not from a panel: each letter is generated, placed on measured prefix advances, and given a dark casing swelled 22% about its own centre and set back behind its face. Ivory metal over a cream wall is light-on-light, and raising the emissive floor does not fix that — a backing plate did, for one day (2026-08-08), and the owner cut the black rectangle on 2026-08-09. A dark copy offset backward, and a dark copy scaled as a whole string, have both been tried and both fail; see the builder's own comment.

Each terrace also carries a **3-D door sign** (`HubDomainTitle`) naming its domain — a static **keylined** machined lockup in the domain accent, with a shimmering rule under the type. Same `HubTitleStyle.keylined` the wordmark uses, so all three pieces of display type in the gallery are one treatment (2026-08-10; before that the signs were bare metal and a photograph showed the floor lamp reading straight through MAGNETISM). **This reverses the earlier "no floating domain headers" rule** (2026-07-30), which is why the branding budget was re-opened for exactly two signs.

> **The kinetic elements were deleted 2026-08-04** — an electron lapping the E&M sign, a ball on a true parabola over Mechanics. This paragraph described both as shipping until 2026-08-09, and carried a reduce-motion clause about them "parking at a composed rest pose rather than freezing mid-flight", which was vacuous once there was no flight to freeze. The signs are lockups now, and the one thing that still moves is the rule's shimmer.
>
> Note §2's decision 3 still records "No floating domain headers — stands", which this section reverses. The spec has contradicted itself on that point since the signs landed; the signs are what ships.

### The pad

A **modelled hexagonal docking cradle** (`GalleryCradle.usdz`) floating front and centre at 1.05 m, milled with a pocket and ringed by three **latch fingers** (`GalleryLatch.usdz`) that close over a lab as it lands and open when it is lifted out. Hexagonal against a gallery of circles on purpose: it is the one platform in the room that is not a shelf.

*(The plinth beneath it came off 2026-08-03 — one leg touching a floor the app cannot see. The plate kept the exact height the column gave it, because that number was measured. The cylinder became a cradle on 2026-08-09.)*

### Focus

Unchanged mechanic (head-direction cone 26° with hysteresis, `RoomModel`'s look ray; `-hubFocus <id>` pins it in the simulator): the focused exhibit **lifts 0.09 m off its puck** and scales to 1.22, and a pool of its accent light appears on the pedestal. Names stay legible at all times (owner, 2026-08-04 — a gallery whose captions vanish until you stare at them cannot be read at a glance); what IS focus-gated is the **promise line** (`HubDomain.promise`), one sentence of "what you actually do here" that fades in under the focused exhibit's name.

**THE FOCUS PANEL IS GONE.** `HubFocusPanel` — domain chip, promise line, progress dial, New badge and Enter button — was deleted on 2026-08-04. This section described it as shipping until 2026-08-07. Its two load-bearing jobs were rehomed then: the promise line above, and the Enter button as a **machined ENTER plaque** standing on each puck's terrace (see *Entering*).

### Entering

**One door, reached two ways** (rewritten 2026-08-09). The door is the **pad**: a lab standing on the modelled cradle front and centre turns there with **Load Module** hanging over it, and that button is the only thing in the room that opens a lab.

- **Tap an exhibit** and it flies to the pad by itself (0.5 s), where the cradle's three latch fingers close over it.
- **Or carry it there** and release inside the 0.34 m snap radius (0.28 s to settle). The better story, and still the one nobody discovers unaided — which is why the tap now demonstrates it.

Either way, entering is: 0.42 s swell-and-rise with a pop, the terrace's hairline flares, then the scene swaps to the module.

A **tap on the exhibit still does not enter**, and 2026-07-29's reasoning is why: entering by tap made the gallery one large accidental-activation surface. Moving a lab across the room is not entering, so the tap does not reinstate the problem. **VoiceOver goes straight in** — the exhibit publishes both `.activate` and an "Enter" custom action — because the ceremony's payload is entirely visual.

*(History: the pad was the ONLY way in from 2026-08-04 to 08-07, when the focus panel's Load button was deleted and nothing replaced it. An ENTER plaque on every puck closed that gap and stood until 2026-08-09, when it and the pad's teach card were both cut. `GalleryDoorTests` covers the door now; the plaque's tests are its ancestor.)*

### Idle life & comfort

Miniatures breathe ±8 mm on desynced periods and run their physics; hairlines shimmer slowly; the title bobs. All idle motion is stilled by `scene.stillness`, which follows the **system** `accessibilityReduceMotion` switch — the in-app duplicate was deleted and there is no `reduceMotion` in `AppSettings`. Everything ticks from one `SceneEvents.Update` subscription (`[weak scene]`, cancelled on disappear).

### Persistent chrome

Unchanged from v3: the **Palette bead** (`Shell/Palette.swift`) with four petals — pause, capture (the notebook), settings (gear), reset; the fourth was added on 2026-07-29 and the count is capped there — and the module window's floating title bar (`Shell/ModuleHostView.swift`).

**The title bar is now the whole window** (DECISIONS 2026-08-01). `ModuleDescriptor.makeControls` and the six `*ControlsPanel.swift` are deleted; every control and readout stands on the apparatus. The bar gained a **Key** button (the legend, as a popover) and shows a **warning triangle** when the room cannot be sensed. *(It also carried the next experiment's step until 2026-08-09.)*

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
8. **No Search, no Daily Challenge surface** — stands, and **hardened 2026-08-09**: the experiments system, which was the app's only progress surface, was deleted entirely. The hub tracks nothing about the user.
9. **Procedural vignettes; `RoomModel` for head pose; `SceneEvents.Update` ticking** — stands.

## 3. Open work

1. ~~Lab Notebook surface~~ — **shipped** (2026-07-29): capture petal on the bead (its fourth and final), book button in every module title bar, Notebook window with CSV/Markdown export.
2. ~~Coach-mark rendering~~ — **deleted by decision** (2026-07-29): onboarding is each module's first-run hint, rendered by the shell until dismissed. See DECISIONS.md.
3. ~~Ambient volume (continuous)~~ — **closed as a non-feature** (2026-08-01). Settings ships master volume plus ambient on/off, and that is the whole honest surface: there is no gain path into the ambient loop, so a continuous slider would be a control over nothing. The app deliberately ships no dead slider. If a gain path is ever built, the slider comes with it and not before.
4. ~~Module window panels~~ — **deleted** (2026-08-01). Listed here only so the trail is complete: the window is a title bar, and `PanelControlCriterionTests` fails the build if a panel comes back. `Archive/Models/` now also holds the USDZ of the cut modules, which had been shipping in the bundle.
5. **Pre-public-repo sweep — `Archive/`: DECIDED TO KEEP, and the reasoning is on the record.** It is 47 files and 1.6 MB, tracked, and **not referenced by the Xcode project at all** — it compiles nothing, ships nothing, and cannot affect the app bundle or a submission. What it holds is five cut modules whose *physics is still live and tested* in `PhysicsCore` (Optics 665 lines, Fluids 1 067, Waves 332, `ElasticSheet` 273, the spring oscillators) — roughly 2 600 of PhysicsCore's 7 457 lines are reachable only from there, and `swift test` exercises every one of them on every run. That is defensible as parked work with a documented restore path and indefensible as an accident, which is why `Archive/README.md` says which it is. **Deleting it is the owner's call, not a cleanup**, and it is the last thing that would need doing before the repo goes public if the answer changes.
   - ~~One genuine grave inside it: `PhysicsCore/Waves/EmissionTrail` has **zero references anywhere**, including the Archive itself.~~ **Wrong, corrected 2026-08-03:** it is constructed twice in `PhysicsCoreTests/DoubleSlitDopplerTests.swift`, so it is tested code with no *app* caller — the same standing as everything else in the Archive's physics, not a grave.

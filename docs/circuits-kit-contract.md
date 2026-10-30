# Circuit Workshop: the contract for the Solid Schematic (Phase 3)

2026-10-30, on branch `redesign/circuit-kit`. The owner chose C, the Solid Schematic (`circuits-kit-directions.md`).

This is the table of every number the assets and the Swift share, old → new, with what reads each one. **Nothing in Swift changes until it is approved.**

## The design in one paragraph

**Every part is its own schematic symbol, made solid and floating on the line.**
- **No base.** A part is its two brass terminal dots, the line between them, and the component standing on that line as its own symbol.
- **Symbols "of revolution" where that is possible,** so they read from any side:
  - the battery's copper and zinc plates;
  - the capacitor's two real plates;
  - the inductor's copper helix;
  - the fuse's glass cartridge.
- **Planar strokes face the wearer**, where a symbol needs a plane: the lamp's circle, the switch's blade, the LED's arrows, the AC wave and the motor's ring.
- **Leads and wires are one line.** Both are a dark jacket over a core in the voltage ramp's colour, so the circuit reads as one continuous drawing.
- **Ink carries a brass keyline,** so the drawing reads against a white wall and against space.

C2, the prototype of this paragraph, rendered in both lights:

![C2 in a bright room](../Tools/propsheets/dirC2/loop-room.png)
![C2 in Deep space](../Tools/propsheets/dirC2/loop-studio.png)

## Decisions inside this table

My defaults are in bold. Overrule any of them.

| | Decision | Default | Why |
|---|---|---|---|
| D1 | Who draws the leads | **Swift**, as the wire's line: core 2.2 mm, jacket 3.7 mm at 0.82, coloured by the terminal's net | Fixes C's Deep space failure (C2 proves it). The lead is at its terminal's potential, so colouring it is true. |
| D2 | How ink strokes are drawn | **A dark casing with a brass keyline** | It is `contrastLine`'s casing-and-core rule, in 3-D. |
| D3 | When the switch closes the circuit | **When the drawn blade reaches the contact, 0.12 s after the tap.** Opening is immediate. | A real switch closes when the blade lands. The bulb lighting on the landing is the payoff. |
| D4 | The motor's flywheel | **The flywheel is the inertia.** Model J = ½m(r_o² + r_i²) of the milled steel ring: 0.00052 kg·m², not 0.0009. | "The motor carries something whose rotation reads", and it is honest. Spin-up at 9 V / 8 Ω goes from 0.72 s to 0.42 s. The alternative is a ring twice as thick that keeps 0.0009. |
| D5 | Electron dots | **A Circuits-only low-poly dot** (`CircuitElectron.usdz`: an icosphere core of 320 triangles and a halo of 80) in place of `Primitives.sphere`, which is 8,064. **All dots are drawn as one instanced entity** (`MeshInstancesComponent`, visionOS 26.0, the deployment target), so they cost 2 draws however many there are. **Fallback:** if the per-frame instance write trips the in-flight limit the frame-pacing pass found (measured with `-frameLog`), one entity per dot, no halo, and a pool of 120. | Today's 4× bench breaks Apple's budget (below), and 200 dots are 400 draws on their own. `RenderKit.Primitives` stays as it is, so the other six labs don't change. |
| D6 | The battery wearing its EMF as a stack of cells | **Cut**, unless you fund it | It would be honest only if EMF moved in whole 1.5 V cells. Today it moves continuously from 1 to 24 V. |
| D7 | Orientation | **The symbol's plane faces the stage's front**, standing or lying | Today's "top to the front" rule would turn a standing part's symbol edge-on. That is A's flaw, and C has planar strokes too. |
| D8 | The multimeter | **It keeps its 1:1 meter form.** Its two defects are fixed; it is not redrawn as a symbol. | It is an instrument at true size (its 2026 rationale). |

## The ten parts

Coordinates are in each part's RealityKit frame: the line is x, up is y, and +z faces the wearer (D7). Terminal 0 is −X; for a battery it is +, for an LED the anode.

| Part | Milled element (one USDZ) | Swift's live piece: what drives it | Lead's inner end (x) |
|---|---|---|---|
| Battery | A copper disc (+, Ø 66 mm) at x −0.008, a zinc disc (−, Ø 36 mm) at +0.0085, and a keylined + | none (D6) | −0.012 / +0.014 |
| AC source | A keylined ring Ø 60 mm on the line, with a brass sine inside it | `ac-bead`: rides the sine at `acPhase(of:)`, at most 1.5 Hz | ±0.031 |
| Resistor | Steel end caps (the ceramic body stays procedural, live bands), plus a keylined ANSI zigzag across its face, to be judged in Phase 4 | `ceramic`: bands from the value; heat from `thermalEnergy` (unchanged) | ±0.028 |
| Capacitor | Two plates Ø 52 mm, 8 mm apart; the − plate (+X) dished, which is the polarised symbol | `cap-plate-0` / `-1`: red (+Q) and blue (−Q), intensity \|V\| / 24 V in 8 steps | ±0.008 |
| Inductor | A copper helix, 8 turns, Ø 28 mm, air core | none (the field layer is unchanged) | ±0.027 |
| Bulb | A glass globe Ø 60 mm, a keylined ring Ø 64 mm, brass end caps, and a steel support on one diagonal | `bulb-filament` coil on the other diagonal. Its colour is the blackbody at T = T_ref·(P / 3 W)^¼ (2700 K at 3 W), through PhysicsCore's Planck-to-sRGB; brightness and glow in 16 steps; point light. | ±0.031 |
| LED | A red epoxy cone (the triangle) from the anode side pointing at a disc (the bar), with two keylined arrows | `led-core`: the cone lit at 625 nm in steps of \|I\| / 4 mA, only when forward; a dark die once burned out | −0.013 / +0.008 |
| Motor | A steel flywheel ring Ø 80 mm (r_i 26 mm, 20 mm thick) in the face plane, round a graphite hub with a keylined M | `rotor`: the ring turns by ω·dt about +z, with one brass marker. Above 20 rev/s it crossfades to `rotor-blur`. | ±0.012 |
| Fuse | A glass cartridge Ø 13 × 34 mm with brass caps; the IEC symbol *is* a cartridge | `fuse-bridge`: the middle third goes when it fails; the glass takes a scorch tint | ±0.024 |
| Switch | A brass pivot dot at x −0.032 and a brass contact ring at +0.032 | `lever`: a brass blade Ø 8 mm and an ebony knob Ø 19 mm, open 30°, on a damped spring (D3) | −0.039 / +0.027 |

## The contract, old → new

| Value | Old | New | Read by | Tests |
|---|---|---|---|---|
| `terminalOffset` | 0.085 | **0.085, unchanged** (saved benches' joints stay joints) | `CircuitsModel`, the renderer, alignment | `CircuitsAlignmentTests` unchanged |
| `contactRadius` | 0.012 (Swift sphere, 8,064 tris) | **0.0085**, a milled `CircuitDot.usdz` of about 500 tris | `makeModule` | `CircuitPropTests` |
| `terminalTargetRadius` | 0.026 | **0.023**. The rule allows (0.017 + 0.030) / 2 = 0.0235. | `CircuitsSpaceView`, `makeVisual` | `ColliderCriterionTests` (numbers only) |
| Carry box x clamp | 0.057 | **0.060** = 0.085 − 0.023 − 0.002 | `makeVisual` | collider tests |
| Body \|x\| limit | < 0.059, the whole body | **< 0.060, the element only**; the leads belong to Swift | `CircuitPropTests` | rewritten |
| `jointLength` | 0.052 (two ball diameters + 4 mm) | **0.038** (two dot diameters + 4 mm) | `CircuitsModel` | `CircuitsConnectionTests` |
| Joint visual | champagne collar, r 0.015 × 0.016 | **one junction dot**, r 0.0106: the two dots merge, as a schematic marks a junction | the renderer | `CircuitsConnectionTests` ("collar" → "junction") |
| `jointGrabRadius` | 0.022 | **0.022, unchanged** (allowed 0.0256) | the renderer | — |
| `wireGrabInset` | 0.028 | **0.025** (target + 2 mm) | the renderer | `CircuitsConnectionTests` |
| Wire core / jacket | r 0.0032 / 0.0062 | **r 0.0022 / 0.0037**; the leads use the same | `layOut` | new budget test |
| Leads | milled traces on the carrier | **two Swift segments per part**, from ±0.085 to the inner ends above, voltage-coloured | `makeModule`, sync | new |
| `CircuitCarrier.usdz`, `carrierTop`, `carrierBottom` | the plate, −0.012, −0.026 | **retired**; `moduleBottom(kind)` comes from the element's bounds | renderer, `HubDioramas` | `CircuitPropTests`, `HubDioramaTests` |
| `bulbCentre` / `ledGlowHeight` | 0.024 / 0.013 | **0 / 0** (on the line) | renderer | `CircuitPropTests` |
| Motor rotor | cross (0.05, 0.008), 2 × 13,068 tris | **ring at the origin, about +z** | renderer | live-state tests |
| `switchPivot` | (−0.028, 0.004, 0) | **(−0.032, 0, 0)** | renderer | — |
| `resistorAxis` / `fuseAxis` / `acFace` | 0.006 / 0 / −0.0018 | **0 / 0 / retired** (the needle goes) | renderer | `CircuitsModuleTests` |
| Capacitor gauge | `capacitor-gauge` bar, `gaugeFill` | **plate tints**; `gaugeFill` keeps its \|V\| / 24 maths | renderer | `CircuitsModuleTests` |
| `moduleOrientation` | top to the front when upright | **face (+z) to the front whenever the axis is ≥ 15° from it**; otherwise it carries its roll | renderer | `CircuitsModuleTests` (rewritten) |
| `labelOffset` | below, at −0.050; beside along local z | **below, at −0.052; beside along local y** | renderer | `CircuitsModuleTests` |
| `shelfPreviewScale` | 0.60 | **0.60, unchanged**: 0.187 m × 0.6 = 0.112 fits 0.12 | `CircuitsPartsLayout` | preview test |
| `motorInertia` | 0.0009 | **0.00052** (D4) | `CircuitsModel` | motor tests; new test against the milled ring |
| Switch close | instant | **0.12 s after the tap, when the blade lands** (D3); a pending close in the Time Capsule | `CircuitsModel` | `TimeCapsuleRoundTripTests`, new timing test |
| Electron dot | 2 × `Primitives.sphere` (16,128 tris), one entity pair per dot | **`CircuitElectron.usdz`**: core r 0.0026 plus halo r 0.0045, 400 tris, instanced (D5) | renderer | `CircuitBudgetTests` |
| Stage, its numbers, `stageClearance` | 0.45, 0.30 | **unchanged.** Its keyline is fixed (the `band()` defect). | — | `CircuitsStageTests` unchanged |
| Multimeter | 86 × 168 × 32 mm | **unchanged**. Its detents move back onto the case. | `Multimeter.swift` | `MultimeterTests` unchanged |

**Retired with it:**
- the chamfered carrier and its mirrored back symbol;
- the champagne collar;
- the AC needle;
- the cross rotor;
- the gauge bar;
- Swift's 8,064-triangle contact spheres.

**Kept:**
- every connection rule;
- the solver;
- terminal 0 = battery + at −X;
- the turntable;
- the shelf;
- the resistor's procedural bands;
- states shown on the part, never in words.

## Feel: snap, seat, lift

All of it is drawn only. The model's part is where the hand is.
- **Snap.**
  - **Pull-in:** inside the last 10 mm before a lead reaches a joinable terminal (within `leadReach`), the drawn part leans toward the pose `alignment(for:)` would give it, weighted by a smoothstep.
  - **Seat:** on release, today's exact alignment and its 0.12 s glide. The two dots merge into the junction dot, and a new `.seat` thunk plays.
  - **Unseat:** pulling a joint apart, the junction strains through today's 12 mm `PressLatch` promotion, then splits into two dots with a pop.
- **Lift.** A held part rides 6 mm up and settles back on release (`Motion.ease`). `LiveGlow` stays the "held" signal; a body never changes size in the hand.
- **The switch.** A new damped spring in `RenderKit/Motion` overshoots on opening and bounces on closing, without ever leaving the contact. `.clack` sounds on the landing.
- **Reduce Motion** snaps all of it, through `Motion.isReduced`. Nothing new flashes faster than 3 Hz.

## Budget, defended

Apple gives these budgets for RealityKit on visionOS: **"less than 250 draw calls in the Shared Space (or 500 in a Full Space); 250k vertices and 250k triangles in the Shared Space (or 500k in a Full Space)"** ([Reducing the rendering cost of RealityKit content on visionOS](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos)). The lab runs in an immersive space. I hold it to the stricter Shared Space figures anyway, so Deep space's sky and the window have room.

**Today, already over:**
- the starter loop in Electron View at 4× is about **682k triangles** on its own;
- a bench that fills the 200-dot pool reaches **3.2M**.

**Ceilings that `CircuitBudgetTests` will enforce:**

| | Triangles | Draws |
|---|---:|---:|
| Element, per part | ≤ 8,000 (bulb ≤ 14,000; C2 measured 3.5k, 13.5k and 3.9k, milled leads included) | ≤ 5 |
| Dots, leads and live pieces, per part | ≤ 2,500 | ≤ 8 |
| Starter loop with the skyline, at 4× | **≤ 70,000** (estimate about 55k, a fifth of today's 682k) | **≤ 120** (estimate about 75) |
| All ten parts with the full 200-dot pool (worst case) | **≤ 250,000** (estimate about 220k) | **≤ 400** (under the 500 a Full Space allows) |

How the estimates add up:
- **Starter loop:** elements ≈ 19k, dots 3k, leads 3k, wires 1.5k, the turntable 12.9k, the skyline 1.6k, and 36 dots × 400 = 14.4k.
- **Draws:** each glyph of a `GlyphRun` label is its own entity, so the worst case's draws are mostly value and skyline labels. `CircuitBudgetTests` counts them rather than trusting this paragraph.
- **On device:** Phase 5 confirms the numbers with the RealityKit Trace template.

## Tests

**Changed:**
- `CircuitPropTests`, rewritten:
  - every element and the dot exist;
  - each lies along x within |x| < 0.060 and is centred on the line;
  - the dot's radius is `contactRadius`;
  - glass is see-through;
  - the copper disc, the wider plate, is at −X;
  - the LED cone points +X;
  - the flywheel's inertia equals `motorInertia`;
  - no faces fall outside a material subset (read from the USD at mill time, and asserted in `propsheet stats`).
- `CircuitsModuleTests`: the orientation rule, the label offset, and the live-entity names.
- `CircuitsConnectionTests`: the junction dot and the new lengths.
- `ColliderCriterionTests`: the new numbers, same rule.
- `HubDioramaTests`: `moduleBottom`.
- `VignettePropTests`: the asset names.
- `TimeCapsuleRoundTripTests`: the pending close.
- The motor model tests: the new J.

**New:**
- **`CircuitBudgetTests`:** walks every `makeModule(kind)` and a staged 4× bench, and holds the ceilings above.
- **`CircuitsLiveStateTests`.** Each drives the model value and asserts what is drawn:
  - the bulb's colour is monotone in watts and reads 2700 K at 3 W;
  - the motor ring advances by ω·dt, and blurs above 20 rev/s;
  - the switch blade crosses the contact at the commit;
  - the capacitor's plate tints follow the sign and |V|;
  - the LED is lit only in forward bias;
  - the fuse bridge goes;
  - the AC bead sits at the phase.
- **`CircuitsFeelTests`:** the pull-in weight is zero beyond 10 mm and monotone, and the model's pose is untouched; the lift; the Reduce Motion snap.
- **`MotionSpringTests`** (RenderKit): the overshoot, the settle, the snap under Reduce Motion.
- **The switch's close timing,** in `CircuitsModelTests`.
- **The `.seat` recipe** in `SoundEffectsTests`, with `oneShotVersion` going from 4 to 5.

## What Phase 4 and 5 touch

**Phase 4 (assets):**
- `Tools/circuitparts.py`, rewritten;
- `Tools/multimeter.py`, its two fixes;
- `Tools/blenderprops.py`, the `band()` slot fix, which re-mills the stage.

**Phase 5 (Swift):**
- `CircuitsRenderer`, `CircuitsModel` (D3 and D4), `CircuitsSpaceView` (targets and feel);
- `HubDioramas`, `Multimeter`;
- `RenderKit/Motion` (the spring);
- `SoundEffects` and `SoundPalette` (the seat).

**Not touched:**
- the solver;
- `RenderKit.Primitives`;
- the other labs;
- the turntable's behaviour;
- the shelf's layout.

## As milled (Phase 4, 2026-10-30)

From here on, the authority is `Tools/circuitparts.py`'s top-level literals: `LEAD_INNER`, `DOT_RADIUS`, `WIRE_CORE`, `WIRE_JACKET`, `ELEMENT_CLAMP`, `PART_ASSETS`, `LIVE_CHILDREN`, `MOTOR_INERTIA`, `SWITCH_*` and `AC_WAVE`. `propsheet.py` reads them, and Phase 5's tests hold the Swift to them.

Milling refined the approved table in these places:

| Value | Approved | As milled | Why |
|---|---|---|---|
| Keylines (D2) | brass | **champagne** | The design system gives brass to "a wire lands here" and champagne to symbol inlays. Brass stays on the dots, caps and switch rings, where current enters. |
| `motorInertia` (D4) | 0.00052 | **0.000543** | The rim plus its web, as milled. `circuitparts.py` refuses to export a flywheel that disagrees with `MOTOR_INERTIA` by more than 1%. Spin-up at 9 V / 8 Ω is 0.44 s. |
| `contactRadius`'s dot | about 500 tris | **728 tris** (UV 28 × 14) | — |
| Lead inner ends | AC ±0.031, resistor ±0.028, capacitor ±0.008, bulb ±0.031, LED −0.013 / +0.008, fuse ±0.024, switch −0.039 / +0.027 | **AC ±0.035, resistor ±0.0255, capacitor −0.007 / +0.0075, bulb ±0.0345, LED −0.012 / +0.007, fuse ±0.028, switch ±0.040** | Each is where the milled element's surface actually begins: a cap's face, a ring's outer edge. |
| Fuse | Ø 13 × 34 mm | **Ø 19 × 44 mm** | At 13 mm it was the smallest object on the bench. |
| Live-child names | `ac-bead`, `cap-plate-0`, `led-core`, `fuse-bridge`… | **`bead`, `plate0`, `plate1`, `filament`, `core`, `rotor`, `rotor_blur`, `fuse_glass`, `fuse_left`, `fuse_bridge`, `fuse_right`, `blade`** | USD prim names allow no hyphen. Each is a top-level prim with its origin where Swift turns or places it: the blade at (−0.032, 0, 0), the bead at the wave's start (−0.018, 0, 0.0069), the rest at the part's centre. |
| Electron | — | `core` (320 tris) and `halo` (80) in `CircuitElectron.usdz` | — |
| Ten elements, all together | — | **52,032 triangles**, every element inside its ceiling (the largest is the bulb at 11,700) | — |
| Capacitor plates | plain plates | **an ink rim with a champagne edge on each** | Seen nearly edge-on, bare metal mirrored a white wall and the "\| (" never read. |

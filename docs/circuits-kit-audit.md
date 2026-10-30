# Circuit Workshop: kit audit (Phase 1 baseline)

2026-10-30, branch `redesign/circuit-kit` at 445a081. This is the "before" picture for the revamp that is meant to make the bench fun. It covers what reads as clinical, what is simply wrong, and what the bench costs.

Every image is a render from `Tools/propsheet.py`. The renders are gitignored, so regenerate them with:

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --python Tools/propsheet.py -- all --label baseline
```

Two cameras:
- **Wearer:** 0.9 m away and 20° above the part, rendered at about the headset's 34 px per degree.
- **Close:** a lean-in to about 25 cm, at three-quarters.

Two lights:
- **Room:** a bright, neutral room, because passthrough is bright.
- **Studio:** Deep space's near-black.

The pieces Swift adds are stand-ins at their real mounts: the contacts, ceramic, blade, rotor, filament, gauge and needle. The headset has the last word on how they look.

## The bench as a whole

![The starter loop from the eye](../Tools/propsheets/baseline/loop-room.png)

**1. From where you stand, it reads as a wire diagram with brass balls at its corners.** The parts are the smallest things in the starter loop.
- The 12 mm wire jackets are the boldest strokes in it.
- The bulb is the only part you could name from here.
- The battery is a small grey can.
- The upright switch reads as a grey plank with a brass line on it.

**2. Ten parts share one silhouette.**
- Each is the same 17 × 6 cm graphite plate with a brass ball at each end.
- Its component sits in the middle third and stands 11–39 mm tall; only the bulb, at 54 mm, stands above that.
- Take the colour away and only the bulb and the capacitor's standing can tell the parts apart.

![Every part through one camera, from the wearer](../Tools/propsheets/baseline/sheet-wearer-room.png)

**3. The contacts are the loudest thing on every part.**
- At 0.9 m a 24 mm polished brass sphere spans 1.5°, about 52 px.
- That is as tall as most bodies, taller than the AC dial, the fuse and the switch, and brighter than any of them.
- The connection points out-shout the components they connect.

**4. The symbol is there, but faint.**
- Its strokes are a 1.1 mm tube, 0.07° or about 2.4 px from the wearer.
- It is champagne on a chamfer that, in a bright room, reads as mid-grey clear-coat.
- Its glyphs are about 0.6° tall, larger than the room's labels, so its *shape* is legible. Its *weight* is not.
- It is the bench's strongest bridge to the textbook, drawn as its quietest line.

**5. Graphite reads grey indoors, and colour is rare.**
- Clear-coated graphite reflects a bright room and comes out mid-grey.
- Colour appears only on the capacitor (blue), the motor's rotor (teal), the LED (red) and the resistor's bands.

**6. Nothing answers the hand.** From the code, not the renders:
- A pickup is a glow and a tick.
- A snap is a 0.12 s glide and a chime.
- The switch blade jumps between 0 and 0.6 rad.
- The bulb has six brightness steps and saturates at 3 W.
- Nothing lifts, seats, clicks or throws.

## Part by part

The turntables are in `turntable-<part>.png`. The close sheet is below.

![Every part, leaning in](../Tools/propsheets/baseline/sheet-close-room.png)

| Part | What reads as clinical |
|---|---|
| Battery | A graphite can on a graphite plate reads as one grey mass. The + is a 10 mm glyph on the can's top, unreadable at 0.9 m, so the polarity is legible only in the symbol. Its EMF is shown only by the number. |
| AC source | A 42 mm watch dial lying flat, 11 mm tall. From the wearer's 20° the face is foreshortened to a third of its height, so its needle, the only state it has, is a short dark tick. |
| Resistor | The one surface that says something: its live bands read from 0.9 m. |
| Capacitor | The blue can is the bench's one strong body colour. Its charge gauge is a 26 × 3 mm bar lying flat in front of the can, so from the eye it is a hairline. |
| Inductor | A bobbin whose nine copper turns render champagne (defect 1). |
| Bulb | The only silhouette you can name from across the room. The glass is clear in the room and milky against Deep space's fill. The filament is 10 × 1.8 mm. |
| LED | An 11 mm dome on legs, the smallest object on the bench and nearly gone at 0.9 m. Nothing on it says which way round it goes, though the solver's diode does. |
| Motor | A ribbed can with a 36 mm teal cross, the only thing on the bench that moves on its own, and it misreports its speed (defect 2). |
| Fuse | A 12 mm glass cartridge. Blown and whole differ by a 9 mm gap in a 1.2 mm wire. |
| Switch | A 5 mm block with a 5 mm blade riding a centimetre above it. Closed, it is a brass line, and open it lifts 34°. It is the weakest-reading part in the starter loop. |
| Contacts and carrier | See 2 and 3. They are identical under every part, so the carrier is the silhouette. |
| Wires | Straight lines, with the voltage colour showing inside the dark jacket. They read well, and at 12.4 mm they are the boldest thing in the loop. |
| Turntable | The knurled champagne rim says "this turns". Its champagne keyline is missing (defect 1). |
| Multimeter | A believable 1:1 meter. It is a dark case against Deep space, and two of its four dial detents float off its sides (defect 3). |
| Probe | Reads as a probe. |

## Defects (not taste)

**1. Every ring milled with `blenderprops.band()` is drawn in the wrong material, unless its material happens to be first.**
- **The cause.** The boolean cut leaves an empty material slot that every ring face points at. The USD exporter therefore writes those faces outside every material subset, so they take the mesh's first material: the symbol's champagne, or the deck's graphite.
- **The parts it gets wrong:**
  - the inductor's turns (900 faces, which should be copper);
  - the bulb's screw threads (which should be copper);
  - the turntable's keyline, drawn in graphite, so it is invisible.
- **The parts that are right only by luck:** the battery's band, the motor's ribs, the AC rim, and the stage's rim and foot.
- **Status.** `propsheet stats` now reports it per asset. The fix belongs in `band()`, in Phase 4.

**2. The motor misreports its speed.**
- **The rotor.** It is two crossed boxes, which make four arms, not the two blades its comment describes. The pattern repeats every 90°.
- **The sum.** In steady state, ω = kV / (k² + b(R + r)). At 90 Hz, the spin you see is the true spin folded into one 90° step per frame. The table below gives the true spin, the blade passes per second, and the apparent spin. Passes above 45 per second cannot be shown honestly at 90 Hz.

| Battery V | Motor R | True spin | Blade passes per s | What 90 Hz shows |
|---|---|---|---|---|
| 9 V | 8 Ω (default) | 8.6 rev/s | 34 | 8.6 rev/s, true |
| 12 V | 8 Ω | 11.4 rev/s | 46 | 11.1 rev/s **backwards** |
| 24 V | 8 Ω | 22.8 rev/s | 91 | 0.3 rev/s, **nearly still** |
| 9 V | 1 Ω | 19.4 rev/s | 77 | 3.1 rev/s **backwards** |
| 24 V | 1 Ω | 51.6 rev/s | 206 | 6.6 rev/s |

So the faster you drive it, the more the motor lies.

**3. Two of the multimeter's four dial detents float in the air beside the case.**
- The asset's bounds are ±53 mm, against a case of ±45 mm.
- The ticks come from the detent loop in `multimeter.py`. Why two of them land off the case is for Phase 4 to find.

**4. Small drifts:**
- ~~The meter's screen sits at y 0.044 in Swift but 0.040 in `multimeter.py`.~~ Withdrawn on 2026-10-30. Swift's 0.044 is the reading's line and 0.026 the note's, two lines laid out inside the LCD (21–59 mm). It is not a drift.
- `multimeter.py` says the meter "arrives standing", but it is milled face-up and `Multimeter.swift` stands it.
- `CircuitPropTests.swift:21` attributes the 0.059 clamp to `CircuitsSpaceView`. It is `CircuitsRenderer`'s, at 0.057.

## Budget, measured

**The milled assets** (`propsheet stats`):
- The ten bodies come to 31,216 triangles in all, from 1,340 for the switch to 6,636 for the inductor.
- The carrier is 436.
- The turntable is 12,908.
- None carries a texture.
- They take 2–7 draws each, one per material.

**RealityKit's own primitives** were counted on the visionOS 26.5 simulator's RealityKit, and macOS agrees:

| Primitive | Triangles |
|---|---|
| `generateSphere` | 8,064 (a 64 × 63 UV sphere, whatever the radius) |
| Rounded `generateBox` | 13,068 |
| `generateCylinder` | 256 |
| Plain box | 12 |

**The starter loop with the skyline on:**

| Piece | Triangles |
|---|---:|
| Three bodies and three carriers | 10,684 |
| Turntable | 12,908 |
| Six brass contacts, 8,064 each | 48,384 |
| Switch blade and grip, rounded boxes | 26,136 |
| Wires, filament, glow and skyline | ≈ 3,400 |
| **Static** | **≈ 101,000** |
| Electron dots at 1×: 18 of them, each a core and a halo of 16,128 | 290,304 |
| Electron dots in Electron View at 4×: 36 | 580,608 |
| **Total at 1× / at 4×** | **≈ 392,000 / ≈ 682,000** |

- **Where it goes.** Spheres and rounded boxes are 93% of the bench at 1× and 96% at 4×. A 3.4 mm electron dot, about 15 px across, costs 8,064 triangles for its core alone.
- **The worst case.** The 200-dot pool caps out at 3.2 million triangles.
- **The milled parts are cheap.** The cost is in the primitives, and that is the headroom the redesign can spend.

**Runtime in the simulator.** Each run used `-openModule circuits -skyline 1`, plus `-viewScale 4`, then plus `-trueSpeed 1`, from a cleared bench, with `-frameLog 1` and a 6 s `sample`:
- every run held 90 Hz with no long frames after settling;
- the main thread was 3–4% busy and never waited on the renderer;
- the props warmed in 0.76–0.93 s.

**What this means.** The main thread is not the constraint; on the device, the GPU's triangle load is. `RenderKit.Primitives` is shared by every lab, so changing its sphere is a cross-lab decision for Phase 3, not a Circuits one.

## The owner's three questions

**Which single part, if it became delightful, would carry the rest? The switch, with the bulb as its payoff.**
- Every wearer meets the starter loop first.
- Of its three parts, the bulb already reads, the battery reads as a can, and the switch reads as nothing.
- The switch is the one part whose job is to be *operated*, and the bulb lighting is its result. "Snap, don't place" and "throws with a click and an overshoot" both land on it.
- The motor would be the bigger "wow", but it is not on the bench until somebody goes to the shelf, and today it lies (defect 2).

**Does a direction need something the model lacks?**

| Part | The model has | It lacks (fund or cut) |
|---|---|---|
| Bulb | watts per part | A filament temperature: R is constant. A warm colour from P = εσAT⁴, through the Planck-to-sRGB code PhysicsCore already has for the stars, needs no change to the solver. |
| Motor | `motorSpeed` from k, b and J | A mechanical load. A steel flywheel 100 × 10 mm is 0.00077 kg·m² against the model's J of 0.0009, so a flywheel can *be* the inertia, honestly, with no new physics. A fan or a flag needs a drag torque c·ω². |
| Battery | EMF from 1 to 24 V, and a global 0.05 Ω | A state of charge, so draining would be a new capacity model, a Time Capsule field and a refill story. |
| Capacitor | V, so Q = CV | Nothing. |
| LED | A real one-way diode, and burnout | Nothing. Only a visible polarity mark is missing. |
| Fuse | It trips instantly | Heating. A slow-blow glow would need I²t. |

**What would I leave exactly as it is?**
- **The resistor's procedural body and bands.**
- **The wire's look:** straight lines, voltage colour, dark jacket.
- **The turntable's form and its knurled rim**, once its keyline is restored.
- **`makeModule` as the one builder** for the bench, the shelf and the home.
- **States shown on the part, never in words.**
- **The symbol on both chamfers, mirrored on the back.** This means its convention and placement, not its 1.1 mm stroke.
- **Terminal 0 as the battery's + at −X, and contacts that *are* the terminals.**

## What Phase 2 starts from

- The body has to own the silhouette.
- The contacts get quieter, or become part of the body.
- The symbol gains weight.
- The switch is designed first.
- Each direction mills the starter loop and is judged against points 1–6 above.

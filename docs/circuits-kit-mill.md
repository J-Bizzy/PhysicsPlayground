# Circuit Workshop: the Solid Schematic, milled (Phase 4)

2026-10-30, on branch `redesign/circuit-kit`. Every asset in `PhysicsPlayground/Models/Circuits/` is re-milled by the rewritten `Tools/circuitparts.py`, against the contract (`circuits-kit-contract.md`, including its "As milled" section). I reviewed every render against the Phase 1 audit before it was sent; the checklist follows.

**The Swift has not changed.** Until Phase 5, the app on this branch mounts the new assets with the old renderer's numbers, so it will look wrong and `CircuitPropTests` will fail. The renders here are the review, not the app.

To regenerate them:

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --python Tools/circuitparts.py
```

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --python Tools/propsheet.py -- all --label solid
```

![Every part from the wearer, in a bright room](../Tools/propsheets/solid/sheet-wearer-room.png)
![The same in Deep space](../Tools/propsheets/solid/sheet-wearer-studio.png)
![The starter loop from the eye](../Tools/propsheets/solid/loop-room.png)

## Against the Phase 1 audit

| Audit point | Now | Verdict |
|---|---|---|
| 1. From where you stand it read as a wire diagram, and the parts were the smallest things in it | The loop reads as its own schematic. From the eye, the lamp's circle-X, the battery's plates and +, and the switch's rings and knob are each nameable. | **Met** |
| 2. Ten parts, one silhouette | Ten different silhouettes: plates, a ringed sine, a banded body, two plates, a helix, a ringed globe, a red cone, a flywheel, a cartridge, a lever. No base anywhere. | **Met** |
| 3. Contacts louder than the components | A 17 mm brass dot, against 24 mm polished spheres before; every element is larger than its dots | **Met** |
| 4. The symbol faint (a 1.1 mm stroke) | The part *is* the symbol. Ink strokes are 5.2 mm, about 0.33° from the eye, keylined in champagne. | **Met** |
| 5. Grey indoors, colour rare | Copper, zinc, red epoxy, the resistor's bands, a steel flywheel, glass. The capacitor's plates got inked rims after the first render: seen nearly edge-on, bare metal mirrored the white wall. | **Met** |
| 6. Nothing answers the hand | Every live piece is a named child with its origin where Swift turns it. The feel itself is Phase 5. | **Ready for Phase 5** |
| Defect: `band()` rings in the wrong material | `band()` clears its empty slot. `propsheet stats` reports no face outside a material subset on any circuit asset; the stage's keyline is champagne again. | **Fixed** |
| Defect: the motor misreports its speed | One brass marker on a smooth ring: nothing repeats short of a full turn. Swift's blur above 20 rev/s is Phase 5. | **Fixed in the asset** |
| Defect: the meter's floating detents | The cause was the box helper. `transform_apply` defaults to baking location *and* rotation, so a later rotation swung each tick about the world's origin. It is fixed in both helpers; nothing on the meter now sits outside its case (x span ±45.2 mm). | **Fixed** |
| Deep space (C's weakness in Phase 2) | The keylined ink and the jacketed leads read in the studio light | **Met** |
| Budget | All ten elements total 52,032 triangles. The largest is the bulb at 11.7k (ceiling 14k); the AC source is 6.6k after trimming from 8.9k, and the capacitor 7.3k with its rims. At most 5 draws on each static element. | **Met** |

## Live children (what Phase 5 drives)

| Asset | Children (top-level prims) |
|---|---|
| `CircuitACSource` | `bead`, at (−0.018, 0, 0.0069), the wave's start |
| `CircuitCapacitor` | `plate0`, `plate1` |
| `CircuitBulb` | `filament` |
| `CircuitLED` | `core`, the epoxy cone |
| `CircuitMotor` | `rotor` (one brass marker, turns about +z through the hub) and `rotor_blur` (shown only at speed) |
| `CircuitFuse` | `fuse_glass`, `fuse_left`, `fuse_bridge`, `fuse_right` |
| `CircuitSwitch` | `blade`, with its origin at the pivot (−0.032, 0, 0) |
| `CircuitElectron` | `core` (320 tris) and `halo` (80), for the instanced flow |
| `CircuitDot` | the terminal dot, 728 tris |

`CircuitCarrier.usdz` is gone, as the contract retires it.

## For you to judge

- **The resistor.** Its ANSI zigzag is keylined across the banded body. Both symbols read, but the zigzag covers the middle third of the bands. The alternative is the zigzag floating just above the body.
- **The switch, closed.** Its blade lies along the line, so closed it reads as part of the line, with its knob on a stem. That is the symbol's own logic. The throw (Phase 5) is what makes it the part that carries the rest.
- **Glass in Deep space.** The bulb's globe goes milky under the studio light's fill. It is the same glass recipe as the shipping bulb (opacity from transmission). The headset is the judge.

## Outside this lab, found on the way

The `band()` flaw is fixed in the helper, but two other labs' assets keep it until they are re-milled. I did not touch them:
- `Models/Magnetism/PickupCoil.usdz`: 4,956 faces draw in its graphite.
- `Models/Shell/TimeReel.usdz`: 2,380 faces draw in the reel's stock.

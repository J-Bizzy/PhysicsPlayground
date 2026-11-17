# Physics Playground

Room-scale physics labs for Apple Vision Pro. Seven labs, each one
fully volumetric and grabbable in your actual room — you throw the
pendulum bob, you carry the magnet, you reshape the orbit by pulling on
it.

The physics is real: SI units, real constants, and exact closed-form
solutions wherever they exist. No physics engine, no library — every
solver is written from scratch in Swift and tested.

**visionOS 26.0+ · Swift 5 · RealityKit**

---

## The seven labs

| | |
|---|---|
| **Electric Fields** | Pull charges out of a well and watch the field redraw. A capacitor whose plates you carry, a uniform **B** you can switch on, and a charged test ball that circles in it — the cyclotron, drawn live in your room. |
| **Circuit Workshop** | Build circuits from racks of real parts you pull out of the air — a resistor that scorches past its rating, an AC source you tune by hand, a coil whose field the bench draws. Nodal analysis every frame, a multimeter you probe with, and a true-speed view you can zoom into the copper to watch — the drift velocity is millimetres per second, and that is the misconception the lab exists to kill. |
| **Magnetism** | Bar magnets that attract, repel and align. Field lines that close on themselves, and a compass you carry. |
| **Light & Optics** | A laser, a torch of white light, and mirrors, a prism, a lens and a glass bar you place anywhere and turn by hand. The light is traced exactly — Snell, Fresnel, each colour through the glass's real Sellmeier index — and lands on your actual walls: a spectrum from the prism, a beam trapped in the bar by total internal reflection. |
| **Projectile Motion** | Throw anything. Real drag, real restitution, and bounces off *your* walls, floor, ceiling and table. Stand a hoop in the room and the launcher solves for it — both arcs, exactly — or arm it to drop as you fire, and the ball meets it in the air on every world. |
| **Pendulums** | Full nonlinear swings, a Newton's cradle to break apart, a chaotic double pendulum, and a true 3-D orbit you throw a bob into above your own floor. |
| **Orbital Mechanics** | An orrery you can walk into, under the real sky — it opens in deep space. Tap a planet and its orbit becomes a ring with beads at each end — pull one and the orbit reshapes under your hand. |

## What is unusual about it

**You handle the physics, not a panel.** A value an object can carry is
changed on the object: pull a charge's handle out and the charge grows,
draw a pendulum's cable down, pull the launcher's aim bead further out to
throw harder. New objects come out of wells, and a tap unfolds a ring
around whatever you touched. Everything secondary — layers, modes, the
lab's live numbers — waits behind one More beside the lab's name, drawn
in one control language (`RenderKit/Controls`). Tests hold both lines:
`PanelControlCriterionTests` keeps panels out of the labs themselves, and
`ControlLanguageCriterionTests` fails the build on a second control
style.

**Your room, or deep space.** Every lab stands in your own room — or, at
one switch in More, in the real sky: the 9,096 naked-eye stars of the
Yale Bright Star Catalogue at their true places, colours and brightness,
the bright ones in the eye's own glare, over the Milky Way itself from
NASA's map of Gaia's 1.7 billion stars, and a glass platform at your
feet. The physics
carries on unchanged, and the room is out of reach there: a ball you throw
flies on instead of bouncing off a wall you cannot see.

**Pause is a place you can walk into.** Every lab records its last
thirty seconds. Pause, pinch the reel that appears, and drag the tape
back: the whole room runs backwards onto recorded frames, the ball
retraces its arc with its velocity and force arrows sculpted on it, and
you resume from any instant you choose. Snapshots, never reverse
integration — a restored moment is one that genuinely happened.

**The fictions are disclosed where they are read.** Some numbers have to
be unphysical for anything to be visible: the field that bends a 0.5 g
ball is about a thousand times the strongest magnet ever built. The app
says so, on screen, beside the number rather than in a footnote.

**It collects nothing.** No accounts, no analytics, no network code at
all. See [docs/PRIVACY.md](docs/PRIVACY.md).

## Building

```bash
# Physics only — native on the Mac, no simulator, ~3 seconds:
cd Packages/PhysicsCore && swift test

# The whole app:
xcodebuild test -project PhysicsPlayground.xcodeproj -scheme PhysicsPlayground \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro 4K'
```

## Layout

```
Packages/PhysicsCore    Pure Swift physics. No RealityKit, no SwiftUI.
Packages/RenderKit      Spatial primitives. Depends on PhysicsCore.
PhysicsPlayground/      The app: Shell, Hub, DesignSystem, Modules.
Archive/                Cut modules, kept with their tested physics.
docs/                   Architecture, decisions, and the manual test script.
```

The dependency arrow points one way only, and `PhysicsCore` never imports
RealityKit or SwiftUI — which is what keeps `swift test` fast enough to
run on every save.

Start with [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). The reasoning
behind anything that looks strange is almost certainly in
[docs/DECISIONS.md](docs/DECISIONS.md), including the things that were
tried and undone.

## Testing

**Nothing automated can touch a RealityKit entity.** `simctl` has no tap
verb and XCUITest has no entity API, so every spatial gesture is verified
by hand against [docs/ON_DEVICE_TESTS.md](docs/ON_DEVICE_TESTS.md). A
screenshot proves something rendered; it never proves it works. What *is*
automated: the physics, the models and clamps, the layout arithmetic, and
tap handlers called directly against real entities.

## License

See [LICENSE](LICENSE). Currently all rights reserved — this is a
portfolio project, and the restrictive default is the one that keeps
every other option open.

The sky is other people's work, credited in the app's About screen: the
stars are the Yale Bright Star Catalogue, 5th ed. (Hoffleit & Warren
1991), via CDS; the Milky Way is Deep Star Maps 2020 (NASA/Goddard Space
Flight Center Scientific Visualization Studio), drawn from Gaia DR2
(ESA/Gaia/DPAC). Gaia's data is licensed CC BY-NC 3.0 IGO, so the app
stays free while it carries that map. The map is adapted: turned to the
dome's layout, smoothed over 6′ and dimmed (`Tools/galaxymap.swift`).

---

Built by Jackson Bizzell.

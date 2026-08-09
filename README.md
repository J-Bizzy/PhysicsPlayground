# Physics Playground

Room-scale physics labs for Apple Vision Pro. Six labs, each one
fully volumetric and grabbable in your actual room — you throw the
pendulum bob, you carry the magnet, you reshape the orbit by pulling on
it.

The physics is real: SI units, real constants, and exact closed-form
solutions wherever they exist. No physics engine, no library — every
solver is written from scratch in Swift and tested.

**visionOS 26.0+ · Swift 5 · RealityKit**

---

## The six labs

| | |
|---|---|
| **Electric Fields** | Pull charges out of a well and watch the field redraw. A capacitor whose plates you carry, a uniform **B** you can switch on, and a charged test ball that circles in it — the cyclotron, drawn live in your room. |
| **Circuit Workshop** | Build circuits from racks of real parts you pull out of the air. Nodal analysis every frame, a multimeter you probe with, and an Electron View that shrinks you into the copper so you can watch the drift velocity — which is millimetres per second, and that is the misconception the lab exists to kill. |
| **Magnetism** | Bar magnets that attract, repel and align. Field lines that close on themselves, and a compass you carry. |
| **Projectile Motion** | Throw anything. Real drag, real restitution, and bounces off *your* walls, floor and ceiling. |
| **Pendulums** | Full nonlinear swings, a Newton's cradle to break apart, a chaotic double pendulum, and a true 3-D orbit you throw a bob into above your own floor. |
| **Gravity Lab** | An orrery you can walk into. Tap a planet and its orbit becomes a ring with beads at each end — pull one and the orbit reshapes under your hand. |

## What is unusual about it

**There are no control panels.** The module window is a title bar. Every
control and every readout is an object in the room: plates you press,
rails with beads you drag, wells you pull new objects out of, and rings
that unfold around whatever you tapped. That boundary is enforced by a
test — `PanelControlCriterionTests` fails the build if a panel comes
back — because the project crossed it in the wrong direction once and it
took 212 commits to get back.

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

---

Built by Jackson Bizzell.

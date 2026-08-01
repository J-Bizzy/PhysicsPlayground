# CLAUDE.md

**Physics Playground** — visionOS app. Room-scale physics labs, each fully volumetric and grabbable in the user's actual room. Portfolio project for college applications, so the physics must be genuinely correct: SI units, real constants, exact closed-form solutions where they exist, pure Swift with no physics libraries, tests written alongside the feature.

Deeper structure lives in `docs/ARCHITECTURE.md` — read it before adding a module or moving code between layers.

## Git safety

The parent directory (`Desktop/VisionPro`) holds sibling projects and a stray embedded repo (`cool/`). **Never `git add -A` or bare `git commit -m` from outside this project** — the index can carry pre-staged sibling files. Always commit with an explicit pathspec scoped to this project.

## Build & test

```bash
# Fast loop — pure physics, native on the Mac, no simulator:
cd Packages/PhysicsCore && swift test
cd Packages/PhysicsCore && swift test --filter MagneticFieldTests

# Full app build + app-level tests (needs the simulator):
xcodebuild test -project PhysicsPlayground.xcodeproj -scheme PhysicsPlayground \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro 4K'
```

Three suites, and the split is about what each CAN reach:
- `PhysicsCoreTests` — pure math, fast, no simulator.
- `PhysicsPlaygroundTests` — models, clamps, layout, and **tap handlers called directly** (`StationTapTests` builds entities and invokes `handleTap`, because no automation can synthesise a pinch).
- `PhysicsPlaygroundUITests` — real XCUITest taps on the **window** surfaces. Launch with `-uiTesting 1`, which holds back the immersive gallery so the flat catalog stays up; XCUITest cannot see anything in an immersive space.

**Nothing automated can touch a RealityKit entity.** `simctl` has no tap verb and XCUITest has no entity API, so every spatial gesture — drag to the podium, pinch a magnet, two-hand zoom — is verified by hand against `docs/ON_DEVICE_TESTS.md`. A screenshot proves something rendered; it never proves it works.

The simulator can't be gaze-pinched, so debug launch args drive a module into a given state for CLI screenshots: `-openModule <id>`, `-studioMode 1`, `-startPaused 1`, `-pauseAfter <seconds>`, `-paletteOpen 1`, plus per-module ones. Full list in `AppModel.init`.

The home's display type is no longer a setting: the machined plaque ships, pinned in code as `HubTitleStyle.shipping` (2026-07-31). The specimen wall and the Settings picker that hung it are both gone — the other three voices stay in `HubTitleStyle` as the alternatives the choice was made against. `-electronView 1` shrinks the bench into the copper (its switch is a plate on the in-room layers bank, which the simulator cannot press). `-openModule circuits -emLink 1` stages the app's one wired pair — a driven coil with the cable running to it — since the simulator has no hands to wire an inductor with. The coil annex reads `-viewScale.field`; single-apparatus scenes read the bare `-viewScale`.

**Gravity Lab's orbit ring is its centrepiece and cannot be pinched from the CLI**: `-selectBody <name>` picks the planet whose ring is drawn, and `-apsisDrag near|far,<factor>` actually RESHAPES that orbit — `-apsisDrag far,2.2` pulls apoapsis out to 2.2× its radius. Its panel now holds no slider, picker or toggle: the display layers are a switch bank, G is a rail, and the star's mass is a bead on the star, so all three need `-openModule gravitylab` plus a hand or an argument. `-gravRing 1` opens a body's control ring; `-predict 1` arms the ghost.

**Electric Fields is fully spatial** — every control is an object in the room, so nothing in it can be reached from the CLI without an argument: `-emCap 1`, `-emGauss disc|bubble`, `-emLines 0`, `-emParticle plus|minus|electron|positron`, `-emVolts <V>`, `-emTesla <T>`, `-emRadius <m>`, `-emTilt <degrees>`, `-emProbeCharge <C>`, `-emRing charge|probe`, plus the older `-emMagnetic`/`-emProbe`/`-emFree`. The VALUE arguments matter as much as the on/off ones: a rail whose bead sits at its default in every screenshot proves nothing about the mapping behind it.

## Working agreement

- Plan before any change touching more than one file.
- Don't refactor outside the scope I gave you.
- Ask before adding a dependency or changing the layer boundaries.
- You can't see the app running — after a visual change, stop and ask me for a screenshot.

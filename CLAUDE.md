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
- `PhysicsPlaygroundTests` — models, clamps, layout, and **tap handlers called directly**: build real entities, invoke `handleTap`, because no automation can synthesise a pinch. Four suites carry that pattern — `SpatialTapTests` (the layer bank and the picker), `SpatialActionBankTests`, `BloomPetalTests`, `MultimeterTests`. (Docs cited a `StationTapTests` here until 2026-08-02; no such file ever existed — the name is from the merged-worlds era, undone on 2026-07-30. The pattern outlived the name.)
- `PhysicsPlaygroundUITests` — real XCUITest taps on the **window** surfaces. Launch with `-uiTesting 1`, which holds back the immersive gallery so the flat catalog stays up; XCUITest cannot see anything in an immersive space.

**Nothing automated can touch a RealityKit entity.** `simctl` has no tap verb and XCUITest has no entity API, so every spatial gesture — drag to the podium, pinch a magnet, two-hand zoom — is verified by hand against `docs/ON_DEVICE_TESTS.md`. A screenshot proves something rendered; it never proves it works.

The simulator can't be gaze-pinched, so debug launch args drive a module into a given state for CLI screenshots. Shell-wide: `-openModule <id>`, `-studioMode 1`, `-startPaused 1`, `-pauseAfter <seconds>`, `-resetHints 1` (all in `AppModel.init`); `-paletteOpen 1` (`Palette.swift`); `-uiTesting 1` (holds the gallery back so XCUITest can see the flat catalog); `-settingsOpen 1`, `-notebookOpen 1`, `-notebookSeed 1`, `-seedCircuits 1`, `-seedMotor 1`, `-circuitVoltageHeights 1` (`MainWindowView.swift`); `-roomSensing denied|unsupported|failed` (`RoomModel.swift`); `-hubDock <module id>`, `-hubFocus <module id>` (`HubSpaceView.swift`). Per-module ones are listed below. **There is no single file holding them all — `AppModel.init` reads five of fifty-seven — so `grep -rho 'forKey: "[a-zA-Z]*"' --include='*.swift' PhysicsPlayground | sort -u` is the only honest index.**

The home's display type is no longer a setting: the machined plaque ships, and as of 2026-08-02 it is the only thing `HubTitleStyle` can draw. The specimen wall, the Settings picker, and the three losing voices are all gone, and so is the enum itself — a four-case taxonomy with one reachable case, a `shipping` constant, a `current` global and a `switch` in every method is a choice mechanism with nothing to choose. `HubTitleStyle` is a namespace now, not a type you pick from. The argument lives in DECISIONS.md and the git history. `-electronView 1` shrinks the bench into the copper (its switch is a plate on the in-room layers bank, which the simulator cannot press). Scenes read the bare `-viewScale`.

**Gravity Lab's orbit ring is its centrepiece and cannot be pinched from the CLI**: `-selectBody <name>` picks the planet whose ring is drawn, and `-apsisDrag near|far,<factor>` actually RESHAPES that orbit — `-apsisDrag far,2.2` pulls apoapsis out to 2.2× its radius. It has no panel at all: the display layers are a switch bank, G is a rail, and the star's mass is a bead on the star, so all three need `-openModule gravitylab` plus a hand or an argument. `-gravRing 1` opens a body's control ring; `-predict 1` arms the ghost.

**Electric Fields is fully spatial** — every control is an object in the room, so nothing in it can be reached from the CLI without an argument: `-emCap 1`, `-emLines 0`, `-emParticle plus|minus`, `-emVolts <V>`, `-emTesla <T>`, `-emProbeCharge <C>`, `-emRing charge|probe`, plus the older `-emMagnetic`/`-emProbe`/`-emFree`. (The flux meter, its `-emGauss`/`-emRadius`/`-emTilt` args, the particle bank and electron mode were removed 2026-08-03.) The VALUE arguments matter as much as the on/off ones: a rail whose bead sits at its default in every screenshot proves nothing about the mapping behind it.

**THERE ARE NO MODULE PANELS (2026-08-01).** `makeControls` is deleted from `ModuleDescriptor` and the six `*ControlsPanel.swift` are gone. A module's window is a title bar, plus "Show in room" while the immersive space is closed and the first-run hint until it is dismissed — nothing else. Every control and every readout stands on the apparatus, `PanelControlCriterionTests` fails the build if a panel comes back, and a new test fails any experiment step that says "in this window". So every module needs an argument to reach its controls from the CLI:
- **Pendulums** — `-penLayers 1` (lights all four of the bank's plates; the Foucault rig and its fifth plate were removed 2026-08-03), `-penRing 1` (the bob's ring, and the only way to see the floating readout card), `-penPivotRing 1` (the collar's ring: cable bead and trash). **`-penGravity <m/s²>` and `-penTime <×>` are different in kind from every other argument here:** the rest reach a control a hand could also reach, and these two reach a capability that was RETIRED on 2026-08-02 along with its rail. A wearer cannot change g or the clock in this module. Use them to photograph the bench somewhere other than Earth at 1×, not to stand in for a missing finger.
- **Magnetism** — `-magInertia 1` swaps the overdamped glide for magnets with real mass and rotational inertia (a needle overshoots and rings); the glide is still the default, and DECISIONS.md 2026-08-03 records why both ship. `-magLayers 0` darkens three of the bank's four plates (the compass grid and its plate were removed 2026-08-03; the scene opens with several lit, and there is no finger to flick them with); `earthFieldOn` is the fourth and the argument does not reach it. `-magRing 1`, `-magFrozen 1`.
- **Projectiles** — `-kinGravity <m/s²>` (also lights the matching world disc), `-kinWind <m/s>` (switches the air on, since the wind rail does not exist without it), `-kinBalls 1`, `-kinWalls 1`.
- **Circuits** — `-electronView 1`, `-trueSpeed 1`, `-circRing 1`, `-circClear 1`, `-skyline 1` (the voltage skyline), `-circField 1` (the wire's own magnetic field).

**A destructive plate is screenshot ARMED, never fired.** `-emClear 1`, `-circClear 1` put the plate into its armed state (lit lamp, nameplate swapped to "Tap again") and hold it there past the four-second timer, because firing photographs an empty room — which looks the same as a room nobody filled. Gravity Lab's two verbs are `-gravBinary 1` and `-gravWorlds 1` (the ten-preset fan). **Pendulums has no verb plate at all** — "Resonance ×5" came off the wall on 2026-08-02, so three modules carry one, not four.

**When a toggle becomes a switch plate, check `reset()` restores the flag behind it.** **SIX** modules have had that defect — four found on 2026-07-31, and Gravity Lab's `keplerSweepOn` and Electric Fields' `chargesRespond` on 2026-08-03, behind lit plates, after this paragraph already existed. A flag with no visible control drifts out of `reset()` and stays wrong because nothing in the room contradicts it; the moment it gets a lamp, the lamp makes the claim every frame. **Reading `reset()` is no longer the check** — every previous fix was a test that LISTED the flags somebody had thought of, which is the same act of attention that missed them. `ResetCoverageTests` reflects over each model, finds every `Bool`, and asserts a mutated-then-reset model matches a fresh one. Add a flag and it is covered; you will be told to add a `flip` case rather than trusted to remember.

## Working agreement

- Plan before any change touching more than one file.
- Don't refactor outside the scope I gave you.
- Ask before adding a dependency or changing the layer boundaries.
- You can't see the app running — after a visual change, stop and ask me for a screenshot.

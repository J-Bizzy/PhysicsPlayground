# The 180-second demo — shot list

The script the release is planned backwards from (2026-09-01): a feature
that cannot hold five seconds of these 180 is broken, undiscoverable or
buried, and this list says which. It is also the acceptance order for
the on-device pass (`ON_DEVICE_TESTS.md` › *Release 1.0 gate*) and the
source the App Store preview is cut from.

Every beat names the code that produces it and the launch arguments that
stage it in the simulator, so the state can be checked between headset
passes. Beats marked **[F]**, **[G]**, **[H]** and **[C]** exist once
Batches F (Projectiles), G (Circuits), H (circuit models) and C (the
launcher ring fold) have landed — see `DECISIONS.md` 2026-09-01.

## Before recording — device prep

- Delete and reinstall the app (an empty bench, the default gallery
  placement, the palette bead at home).
- Grant World Sensing and Hand Tracking on the first prompt; let the room
  scan land (enter Projectiles once and watch the welcome shot bounce off
  a real wall) before the take.
- Time Capsule ships ON; confirm in Settings anyway.
- A 20-second test recording via Control Center, played back with sound:
  app audio (chimes, the mains hum, the orbital chord) must be on it.
- Head still, slow turns: in 2D, small head movements read as large.
- One take. If a beat fails, stop and fix; do not cut around it.

## The shot list

| # | Time | On screen | Your hands | Produced by | Simulator staging |
|---|---|---|---|---|---|
| 0 | 0:00–0:12 | Cold launch: a beat of passthrough (the prop cache warming), then the wordmark fades in and flies to the wall with the bell at 2.65 s; terraces, six live miniatures and the two door signs cascade in over ~3.5 s. Head sweeps the crescent: the exhibit you face lifts off its mount, its accent pools on the mount, and its name brightens on the bench edge beneath it. | None. A slow head turn. | `PhysicsPlaygroundApp.swift`, `Shell/PlaygroundSpaceView.swift` (`ready`), `Hub/HubIntro.swift`, `Hub/HubSpaceView.swift`, `Hub/HubDomains.swift` (`promise`) | `-hubIntro 2.4`; `-hubFocus kinematics` |
| 1 | 0:12–0:22 | Pinch the Projectiles miniature: it flies to the cradle (0.5 s), the three latch fingers close, **Load Projectile Motion** hangs over it. Pinch Load: 0.42 s swell and pop, the hairline flares, dissolve through passthrough, the lab fades up as the room ramps to 0.35 — a welcome shot already in the air. | Pinch, pinch. | `HubSpaceView.sendToPad / dock / enter`, `AppModel.go(to:)`, `RenderKit/Fade`, `Shell/RoomDimmer.swift` | `-hubDock kinematics`; then `-openModule kinematics` |
| 2 | 0:22–0:52 | **Projectile Motion.** (a) Pull a basketball from the well, throw it overhand at a real wall — it bounces AT the wall; **[F]** bounce one off your coffee table (7 s). (b) **[F]** Pull a **hoop** from its well and stand it across the room; tap it → Aim → "Low arc": two ghost arcs through the rim and the callout "low 32° · high 74°", the bead swings to the low one, Fire — chime, the plate counts (10 s). (c) Tap Jupiter: the arc collapses; Zero-g: dead straight (5 s). (d) **[F]** "Drop when fired": the hoop falls as you fire and the ball meets it in mid-air (5 s). (e) Air on: **[F]** the vacuum ghost stands beside the real arc; **[F]** swat the next ball out of the air (3 s). | Pull, throw, pull, place, tap, tap, pinch, tap, tap, tap, tap, swat. | `Modules/Kinematics/KinematicsSpaceView.swift`, `KinematicsModel.swift`, `KinematicsRenderer.swift`, `PhysicsCore/Kinematics/{ProjectileMotion,RoomWalls,SphereStrike,ThrowSampler}.swift`, `Shell/RoomModel.swift` | `-openModule kinematics -kinBalls 1 -kinWalls 2`; **[F]** `-kinHoops 1 -kinSolve 1`; `-kinHunter 1 -pauseAfter 0.6`; `-kinAir 1`; `-roomTable 0.75`; `-kinGravity 24.79` |
| 3 | 0:52–1:07 | **Time Capsule**, still in Projectiles. Pinch the pause petal: the room holds; a reel arrives still coasting, under "Time capsule" (3 s). Pinch the reel: the tape draws out, the reel turns ~1.5 turns (2 s). Drag the bead back: the ball retraces its arc and the bounce un-happens; walk around the frozen ball with its velocity and force arrows sculpted on it and the path hanging as a tube (6 s). "Back a frame" ×3 through the wall contact (2 s). "Resume here": the room runs forward from that instant (2 s). | Pinch the bead → pause → pinch the reel → drag → walk → tap ×3 → tap. | `Shell/TimeRail.swift`, `Shell/TimeCapsuleSupport.swift`, `PhysicsCore/Math/TimeCapsule.swift`, `Shell/Palette.swift`, `RenderKit/FrozenVectors` | `-openModule kinematics -kinBalls 1 -pauseAfter 4` (reel closed; the capsule is on by default); add `-scrubBack 1.5 -scrubStep -3` |
| 4 | 1:07–1:37 | **Circuit Workshop.** Open the palette bead and pinch the Circuits vignette — the lab-to-lab door — dissolve (3 s). The loop is live; pinch the switch: bulb out, beads stop (3 s). Pull a resistor from the rack, born at your fingertips, click it nose-to-tail onto the loop; **[G]** pull its bead to 10 Ω: it glows with I²R, then scorches and the loop goes dark; Replace (7 s). Presets → "RC charger"; **[G]** wire in the coil; Views → Magnetic field: the coil's field loops over the bench; reverse the battery, it flips (8 s). **[G]** Tap the AC source: its frequency rail hangs under it; slide to 3 Hz, the bulb flickers, the capacitor lags (4 s). Electron View: into the copper, beads at mm/s while the field front laps the loop (5 s). **[H]** Every part reads as one milled family. | Pinch, pinch, pull-drop, pinch-drag, tap, tap, tap, pull-drop, tap, pinch, tap, drag, tap. | `Modules/Circuits/CircuitsSpaceView.swift`, `CircuitsModel.swift`, `CircuitsRenderer.swift`, `PhysicsCore/Circuits/CircuitSolver.swift`, `PhysicsCore/Magnetism/{CurrentLoop,MagneticField,WireField}.swift` | `-openModule circuits -circPreset parallel -circPresetsOpen 1`; `-circAlign 1`; `-electronView 1`; **[G]** `-circHeat 1`; `-circCoil 1 -circField 1`; `-circAC 3 -circRing 1` |
| 5 | 1:37–2:07 | **Orbital Mechanics.** Bead → Orbital Mechanics; the room goes to 0.85 — entering space (3 s). Quiet sky. Tap Earth: orbit ring, data card, v/a/F arrows arrive together (4 s). Pull the far apsis bead out: the ellipse stretches; let go: Earth stays on the orbit you drew (7 s). Clock tab → 20×: the beads creep — precession (4 s). Two-hand pinch to ~4× and walk in among the outer planets; the orbital chord (5 s). Twin suns: every orbit answers (4 s). Show → Lagrange; drop a world on L4: it holds and the capture paragraph appears (3 s). | Pinch, tap, drag, release, pinch, tap, two-hand pinch, walk, pinch, pinch, pull-drop. | `Modules/OrbitalMechanics/OrbitalMechanicsSpaceView.swift`, `OrbitalMechanicsModel.swift`, `OrbitRing.swift`, `OrbitalMechanicsRenderer.swift`, `DesignSystem/SummonHandle.swift`, `PhysicsCore/Gravitation/{NBody,OrbitalElements,Lagrange}.swift` | `-openModule gravitylab -selectBody Earth -gravRing 1 -apsisDrag far,2.2`; `-gravBinary 1`; `-gravLagrange 1`; `-viewScale 4` |
| 6 | 2:07–2:15 | **Electric Fields.** Pull a + charge from a well: the field redraws around your hand (3 s). Uniform B on; pull a test probe and throw it sideways: it circles and closes on its own tail; the card reads a non-zero qv×B (5 s). | Pull, tap, pull, throw. | `Modules/Electromagnetism/FieldSpaceView.swift`, `FieldModel.swift`, `FieldRenderer.swift`, `PhysicsCore/Electromagnetism/*` | `-openModule electrostatics -emMagnetic 1 -emTesla 0.6 -emLaunch 1 -pauseAfter 2`; `-emCap 1 -emVolts 90` |
| 7 | 2:15–2:23 | **Magnetism.** Carry one bar toward the other: it swings and snaps head-to-tail; the loops re-trace around you; the hand compass follows. | Pinch-carry, release. | `Modules/Magnetism/MagnetismSpaceView.swift`, `MagnetismModel.swift`, `MagnetismRenderer.swift`, `PhysicsCore/Magnetism/*` | `-openModule magnetism`; `-magRing 1` |
| 8 | 2:23–2:31 | **Pendulums.** Let the cradle's drawn ball go: click-click. Pull "Double" from the well and flick it: the lower bob's chaotic trail, and no period tag. Throw a bob sideways into a true 3-D orbit above your floor. | Release, pull, flick, throw. | `Modules/Pendulums/PendulumsSpaceView.swift`, `PendulumsModel.swift`, `PendulumsRenderer.swift`, `PhysicsCore/Oscillations/{Oscillations,DoublePendulum,BobCollision}.swift` | `-openModule pendulums -penLayers 1 -penRing 1` |
| 9 | 2:31–2:41 | **The Physics box.** Tap a bob: its card (L, T, θ, v). The title bar's ƒ: the lab's live numbers on a card in the room, beside the apparatus they describe. | Tap, pinch. | `Shell/PhysicsBoard.swift`, `Modules/Pendulums/PendulumsModule.swift` (`readings`) | `-openModule pendulums -physicsOpen 1` |
| 10 | 2:41–2:50 | **Close.** Home petal: dissolve, the gallery fades back up under its wordmark; a slow look along the crescent; end on the wordmark. | Pinch, pinch. | `Palette.onHome → go(to: nil)`, `HubSpaceView.fadePresence` | none |

170 s of action; the dissolves and breaths make 180. The Time Capsule sits
inside Projectiles because a rewound bounce is where a scrub is most
legible, and lab-to-lab cuts go through the palette bead, which is the
door a demo uses most.

## The App Store preview (15–30 s)

Cut from a **Developer Capture** (Reality Composer Pro › File › Developer
Capture), not from the Control Center recording. The strongest 30 s:
beat 5 (tap Earth, pull the apsis bead, two-hand walk-in) into beat 3
(pause, reel, scrub the ball back through its bounce). Specs are in
`APP_STORE.md`.

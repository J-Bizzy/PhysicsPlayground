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
launcher ring fold) have landed — see `DECISIONS.md` 2026-09-01. Beats
marked **[T]** are the 2026-10-17/18 passes: throwing as Projectiles'
main act with its layers off until asked for, and Circuit Workshop's
lab-kit parts on a turntable.

## Before recording — device prep

- Delete and reinstall the app (an empty bench, every lab at its default
  placement).
- Grant World Sensing and Hand Tracking on the first prompt; let the room
  scan land (enter Projectiles once and throw a ball at a real wall: it
  bounces off it) before the take.
- Time Capsule ships ON; confirm in Settings anyway.
- A 20-second test recording via Control Center, played back with sound:
  app audio (chimes, the mains hum, the orbital chord) must be on it.
- Head still, slow turns: in 2D, small head movements read as large.
- One take. If a beat fails, stop and fix; do not cut around it.

## The shot list

| # | Time | On screen | Your hands | Produced by | Simulator staging |
|---|---|---|---|---|---|
| 0 | 0:00–0:12 | Cold launch: a beat of passthrough (the props and the sky warming), then the home arrives (~1.5 s): the seven labs in miniature rise into place around you one after another, left to right, each fading up as it comes; their names come up under them and one soft tone sounds as the last settles, while the wordmark's letters drop and swing into place. Then the home: each lab floating, looping its own physics and swinging slowly, the wordmark, seven short names, More. | None. A slow head turn along the labs. | `PhysicsPlaygroundApp.swift`, `Shell/PlaygroundSpaceView.swift` (`ready`), `Hub/Opening.swift`, `Hub/HubSpaceView.swift`, `Hub/HubDioramas.swift` | `-hubIntro 0.3`, `-hubIntro 0.6`, `-hubIntro 0.9` (the arrival), `-hubIntro 99` (home); each with `-surroundings space` for Deep space |
| 1 | 0:12–0:22 | Pinch Projectiles: dissolve through passthrough, the lab fades up as the room ramps to 0.35 — **[T]** quiet: a ball waits at your left hand. | Pinch. | `HubSpaceView` (portal enter), `AppModel.go(to:)`, `RenderKit/Fade`, `Shell/RoomDimmer.swift` | `-openModule kinematics` |
| 2 | 0:22–0:52 | **Projectile Motion.** (a) **[T]** Take the ball waiting in the well at your left hand and throw it overhand at a real wall — it bounces AT the wall; **[F]** bounce one off your coffee table (7 s). (b) **[T]** More → Trajectory, then pull the aim bead out from the launcher: its shaft lengthens, "45° · 6.0 m/s" rides the bead while you hold it, and the arc stretches across the room (4 s). (c) **[F]** Pull a **hoop** from its well and stand it across the room; tap it → Aim → "Low arc": two ghost arcs through the rim and the callout "low 32° · high 74°", the bead swings to the low one, Fire — chime, the hoop flashes (8 s). (d) More → Gravity onto Jupiter: the readout names it and the arc collapses; to 0, dead straight (5 s). (e) **[F]** "Drop when fired": the hoop falls as you fire and the ball meets it in mid-air (4 s). (f) More → Air resistance: **[F]** the vacuum ghost stands beside the real arc; **[F]** swat the next ball out of the air (2 s). | Pull, throw, pull the bead, pull, place, tap, tap, pinch, tap, slide, tap, tap, swat. | `Modules/Kinematics/KinematicsSpaceView.swift`, `KinematicsModel.swift`, `KinematicsRenderer.swift` (`beadDistance(forSpeed:)`), `KinematicsModule.swift` (`more`), `PhysicsCore/Kinematics/{ProjectileMotion,RoomWalls,SphereStrike,ThrowSampler}.swift`, `Shell/RoomModel.swift` | `-openModule kinematics -kinThrow 6`; `-kinWalls 2`; `-kinArc 1 -kinSpeed 9`; **[F]** `-kinHoops 1 -kinSolve 1`; `-kinHunter 1 -pauseAfter 0.6`; `-kinAir 1`; `-roomTable 0.75`; `-moreOpen 1 -kinGravity 24.79` |
| 3 | 0:52–1:07 | **Time Capsule**, still in Projectiles. Pinch Pause in the title bar: the room holds; a reel arrives still coasting, under "Time capsule" (3 s). Pinch the reel: the tape draws out, the reel turns ~1.5 turns (2 s). Drag the bead back: the ball retraces its arc and the bounce un-happens; walk around the frozen ball with its velocity and force arrows sculpted on it and the path hanging as a tube (6 s). "Back a frame" ×3 through the wall contact (2 s). "Resume here": the room runs forward from that instant (2 s). | Pinch Pause → pinch the reel → drag → walk → tap ×3 → tap. | `Shell/TimeRail.swift`, `Shell/TimeCapsuleSupport.swift`, `PhysicsCore/Math/TimeCapsule.swift`, `Shell/ModuleHostView.swift`, `RenderKit/FrozenVectors` | `-openModule kinematics -kinBalls 1 -pauseAfter 4` (reel closed; the capsule is on by default); add `-scrubBack 1.5 -scrubStep -3` |
| 4 | 1:07–1:37 | **Circuit Workshop.** Home, then the Circuits portal (3 s). The loop is live; pinch the switch: bulb out, beads stop (3 s). Pull a resistor from the shelf, born at your fingertips, and set it down by the loop: it leans in, glides nose-to-tail onto a lead and seats, the two brass dots made one junction; **[T]** pinch the turntable's rim and turn the whole circuit to face you, letting it coast (2 s); **[G]** tap it and pull its value handle out from under it to 10 Ω: it glows with I²R, then scorches and the loop goes dark; Replace (7 s). More → Load RC charger; **[G]** wire in the coil; More → Magnetic field: the coil's field loops over the bench; reverse the battery, it flips (8 s). **[G]** Tap the AC source: its frequency slider hangs under it; slide to 3 Hz, the bulb flickers, the capacitor lags (4 s). More → True drift speed, and two-hand zoom into the copper: beads at mm/s while the field front laps the loop (5 s). **[H]** **[T]** Every part reads as its own symbol made solid, floating on its brass dots, its state on the part. (The beat runs about 32 s with the turn; trim on the take.) | Pinch, pinch, pull-drop, tap, drag, tap, tap, pull-drop, tap, tap, drag, tap, two-hand pinch. | `Modules/Circuits/CircuitsSpaceView.swift`, `CircuitsModel.swift`, `CircuitsRenderer.swift`, `CircuitsModule.swift` (`more`), `PhysicsCore/Circuits/CircuitSolver.swift`, `PhysicsCore/Magnetism/{CurrentLoop,MagneticField,WireField}.swift` | `-openModule circuits -circPreset parallel -moreOpen 1`; `-circAlign 1`; **[T]** `-circPreset rcCharger -circStageShift 0,-0.2,-1.7 -circStageYaw 60` (from a cleared saved bench — see CLAUDE.md's turntable paragraph); `-circKit 1`; `-trueSpeed 1`; **[G]** `-circHeat 1 -circRing 1`; `-circCoil 1 -circField 1`; `-circAC 3 -circRing 1` |
| 5 | 1:37–2:07 | **Orbital Mechanics.** Home → Orbits: it opens in deep space by itself — the real sky, the platform under you (3 s). Quiet sky. Tap Earth: orbit ring, data card, v and F arrows arrive together (4 s). Pull the far apsis bead out: the ellipse stretches; let go: Earth stays on the orbit you drew (7 s). More → Clock 20×: the beads creep — precession (4 s). Two-hand pinch to ~4× and walk in among the outer planets; the orbital chord (5 s). More → Twin suns: every orbit answers (4 s). More → Lagrange points; drop a world on L4: it holds and the capture paragraph appears (3 s). | Pinch, tap, drag, release, tap, two-hand pinch, walk, tap, tap, pull-drop. | `Modules/OrbitalMechanics/OrbitalMechanicsSpaceView.swift`, `OrbitalMechanicsModel.swift`, `OrbitRing.swift`, `OrbitalMechanicsRenderer.swift`, `OrbitalMechanicsModule.swift` (`more`), `PhysicsCore/Gravitation/{NBody,OrbitalElements,Lagrange}.swift` | `-openModule gravitylab -selectBody Earth -gravRing 1 -apsisDrag far,2.2`; `-gravClock 20 -moreOpen 1`; `-gravBinary 1`; `-gravLagrange 1`; `-viewScale 4` |
| 6 | 2:07–2:15 | **Electric Fields.** Pull a charge from the Charge well: the field redraws around your hand; tap it, Flip: the lines reverse; pull its handle out: the sphere swells and the field strengthens (4 s). More → Uniform B; pull a test charge and throw it sideways: it circles and closes on its own tail (4 s). | Pull, tap, tap, pull, tap, pull, throw. | `Modules/Electromagnetism/FieldSpaceView.swift`, `FieldModel.swift`, `FieldRenderer.swift` (`chargeScale`), `PhysicsCore/Electromagnetism/*` | `-openModule electrostatics -emRing charge -emStrength 4`; `-emMagnetic 1 -emTesla 0.6 -emLaunch 1 -pauseAfter 2`; `-emCap 1 -emVolts 90` |
| 7 | 2:15–2:23 | **Magnetism.** Carry one bar toward the other: it swings and snaps head-to-tail; the loops re-trace around you; the hand compass follows. Tap a magnet and draw its strength handle out from under it: the loops multiply. | Pinch-carry, release, tap, pull. | `Modules/Magnetism/MagnetismSpaceView.swift`, `MagnetismModel.swift`, `MagnetismRenderer.swift`, `PhysicsCore/Magnetism/*` | `-openModule magnetism`; `-magRing 1` |
| 8 | 2:23–2:31 | **Pendulums.** Let the cradle's drawn ball go: click-click. Tap a bob and draw its length handle down: the cable pays out and the period tag climbs as √L. Pull "Double" from the well and flick it: the lower bob's chaotic trail, and no period tag. | Release, tap, pull, pull, flick. | `Modules/Pendulums/PendulumsSpaceView.swift` (`lengthStretch`), `PendulumsModel.swift`, `PendulumsRenderer.swift`, `PhysicsCore/Oscillations/{Oscillations,DoublePendulum,BobCollision}.swift` | `-openModule pendulums -penLayers 1 -penRing 1` |
| 9 | 2:31–2:41 | **More and Deep space.** Pinch More in the title bar: the lab's switches, its live numbers, the room. Deep space: your room gives way to the real night sky — Orion ahead — and a glass platform under your feet, and the pendulums swing on. | Pinch, tap. | `Shell/LabMorePanel.swift`, `Shell/DeepSpace.swift`, `Shell/Sky.swift`, `Modules/Pendulums/PendulumsModule.swift` (`more`, `readings`) | `-openModule pendulums -moreOpen 1`; `-openModule pendulums -surroundings space` |
| 10 | 2:41–2:50 | **Close.** Home: dissolve, and the seven labs float around you again under the wordmark; a slow look along them; end on the wordmark. | Pinch. | `ModuleHostView` (Home) → `AppModel.go(to: nil)`, `HubSpaceView` | `-hubIntro 99` |

170 s of action; the dissolves and breaths make 180. The Time Capsule sits
inside Projectiles because a rewound bounce is where a scrub is most
legible, and lab-to-lab cuts go through Home: one pinch, and the labs
are the doors.

## The App Store preview (15–30 s)

Cut from a **Developer Capture** (Reality Composer Pro › File › Developer
Capture), not from the Control Center recording. The strongest 30 s:
beat 5 (tap Earth, pull the apsis bead, two-hand walk-in) into beat 3
(pause, reel, scrub the ball back through its bounce). Specs are in
`APP_STORE.md`.

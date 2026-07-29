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

Two separate suites: pure-math tests go in `PhysicsCoreTests` (fast, no sim); model/integration tests go in `PhysicsPlaygroundTests` in the app target.

The simulator can't be gaze-pinched, so debug launch args drive a module into a given state for CLI screenshots: `-openModule <id>`, `-studioMode 1`, `-startPaused 1`, `-pauseAfter <seconds>`, `-paletteOpen 1`, plus per-module ones. Full list in `AppModel.init`.

## Working agreement

- Plan before any change touching more than one file.
- Don't refactor outside the scope I gave you.
- Ask before adding a dependency or changing the layer boundaries.
- You can't see the app running — after a visual change, stop and ask me for a screenshot.

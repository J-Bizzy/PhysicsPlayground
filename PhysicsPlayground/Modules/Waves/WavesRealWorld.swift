//
//  WavesRealWorld.swift
//  Physics Playground — Waves module
//
//  The module's real-world story, rendered by the shell's RealWorldPanel.
//  Every claim should survive a physics teacher reading it.
//

import Foundation

enum WavesRealWorld {
    static let story = RealWorldStory(
        tagline: "Silence engineered from sound, dead spots in your living room, and the experiment that proved light is a wave — all the same picture in this pool.",
        applications: [
            RealWorldStory.Application(
                title: "Noise-cancelling headphones",
                icon: "headphones",
                body: "Flip one source's phase and the loud midline goes silent — that's the entire trick. Your headphones' microphones sample the incoming noise and the speakers play it back inverted, so at your eardrum crest meets trough and they cancel. It works best on steady low rumble (engines, cabin noise) because the electronics need the wave to be predictable a few milliseconds ahead."
            ),
            RealWorldStory.Application(
                title: "Dead spots in rooms",
                icon: "speaker.wave.3",
                body: "Two speakers playing the same note make exactly this pattern in your living room: lanes where the bass booms and silent lines where it vanishes. Step sideways half a wavelength and the music changes. It's also why wiring one speaker backwards ruins the bass — you've built the inverted-source experiment by accident — and why Wi-Fi (also waves) has dead zones that move when the router does."
            ),
            RealWorldStory.Application(
                title: "Young's double slit",
                icon: "lightbulb",
                body: "In 1801 Thomas Young let sunlight through two narrow slits — two synchronized sources, exactly like your two pucks — and saw bright and dark fringes on the wall. Particles can't cancel each other; only waves can. Those stripes settled a century-old argument and measured light's wavelength at half a millionth of a meter. The fringe spacing follows the same d/λ arithmetic on your stats panel."
            ),
        ]
    )
}

//
//  ElectromagnetismRealWorld.swift
//  Physics Playground — Electromagnetism module
//
//  The module's real-world story, rendered by the shell's RealWorldPanel.
//  Physics accuracy matters here as much as in the simulation: every claim
//  below should survive a physics teacher reading it.
//

import Foundation

enum ElectromagnetismRealWorld {
    static let story = RealWorldStory(
        tagline: "The field you're standing in isn't an abstraction — it stores camera-flash energy, images your brain, and decides where lightning strikes.",
        applications: [
            RealWorldStory.Application(
                title: "Capacitors",
                icon: "bolt.batteryblock.fill",
                body: "Put a red and a blue charge close together and look at the dense, nearly parallel field between them — that's a capacitor: two oppositely charged plates storing energy in the field itself. Camera flashes charge one slowly and dump it in a millisecond; defibrillators do the same at life-saving scale; your phone's touchscreen senses your finger by how it disturbs thousands of tiny capacitor fields."
            ),
            RealWorldStory.Application(
                title: "MRI machines",
                icon: "brain.head.profile",
                body: "Magnetic fields are the other face of the electromagnetic field you're playing with — they appear whenever charges move. An MRI circulates current through superconducting coils to fill the bore with a magnetic field about 60,000 times Earth's, then uses precisely timed radio waves (oscillating electric and magnetic fields) to make the hydrogen nuclei in your body signal back their location."
            ),
            RealWorldStory.Application(
                title: "Lightning",
                icon: "cloud.bolt.fill",
                body: "A thundercloud and the ground below form a giant version of the dipole in front of you. When the field anywhere exceeds about 3 million volts per meter, air itself is torn into charged fragments and conducts — that's the strike. Notice how your field lines crowd together at strong charges: fields concentrate at sharp points, which is exactly why lightning rods end in one."
            ),
        ]
    )
}

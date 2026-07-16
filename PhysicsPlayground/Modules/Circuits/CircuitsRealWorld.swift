//
//  CircuitsRealWorld.swift
//  Physics Playground — Circuits module
//
//  The module's real-world story, rendered by the shell's RealWorldPanel.
//  Every claim should survive an electrical engineer reading it.
//

import Foundation

enum CircuitsRealWorld {
    static let story = RealWorldStory(
        tagline: "Your house, your phone charger, and your camera flash are all in this lab — wired exactly the way you're wiring them.",
        applications: [
            RealWorldStory.Application(
                title: "Why your house is wired in parallel",
                icon: "lightbulb.2",
                body: "Wire two bulbs in series here and watch both dim — they share the voltage. Wire them in parallel and each gets the full supply, and unplugging one leaves the other lit. That second picture is every home circuit: outlets in parallel across 120 or 230 V, each appliance getting full voltage, each removable without blacking out the rest. Christmas lights used to be the sad exception — one dead bulb in series killed the string."
            ),
            RealWorldStory.Application(
                title: "Capacitors are everywhere timing happens",
                icon: "camera.aperture",
                body: "Charge a capacitor through a resistor here and it fills on the τ = RC curve you can watch. That same curve times intermittent wipers, debounces every button you press, and smooths a charger's rippling output flat. A camera flash is the drama version: charge a big capacitor slowly for seconds, dump it through the tube in a millisecond — the whole reason a flash whines before it's ready."
            ),
            RealWorldStory.Application(
                title: "I²R: fuses, breakers, and thick wires",
                icon: "flame",
                body: "Power dissipated is I²R — current squared. Short your battery here (one wire, + to −) and its honest internal 0.05 Ω becomes the only brake: the readout shows a huge current cooking the battery itself. That's why real wiring has fuses and breakers — sacrificial links that die before the wall does — and why jumper cables are thick: halve the resistance and a given current wastes half the power heating the cable."
            ),
        ]
    )
}

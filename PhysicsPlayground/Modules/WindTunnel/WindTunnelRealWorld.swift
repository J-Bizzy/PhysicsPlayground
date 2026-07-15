//
//  WindTunnelRealWorld.swift
//  Physics Playground — Wind Tunnel module
//
//  The module's real-world story, rendered by the shell's RealWorldPanel.
//  Every claim should survive a physics teacher reading it.
//

import Foundation

enum WindTunnelRealWorld {
    static let story = RealWorldStory(
        tagline: "Wings, curveballs, and why every fast thing is teardrop-shaped — all hiding in the flow around one spinning cylinder.",
        applications: [
            RealWorldStory.Application(
                title: "How wings lift",
                icon: "airplane",
                body: "Your spinning cylinder generates lift by making air move faster on one side than the other — faster air, lower pressure (Bernoulli), net upward push. A wing does exactly the same thing with shape instead of spin: its profile establishes circulation around itself, and the lift is ρUΓ — the Kutta–Joukowski theorem your panel is computing live. Double the airspeed and lift quadruples, which is why takeoff speed matters so much."
            ),
            RealWorldStory.Application(
                title: "Curveballs & banana kicks",
                icon: "figure.baseball",
                body: "Spin the cylinder and the stagnation points slide around; the flow leaves it asymmetrically and the ball — sorry, cylinder — gets pushed sideways. That's the Magnus effect: a curveball's topspin, a banana free kick, the vicious dip on a topspin forehand. (The projectile module deliberately left spin out of its drag model — this is the missing force, isolated so you can see it work.)"
            ),
            RealWorldStory.Application(
                title: "Why streamlining works",
                icon: "car.side",
                body: "This ideal flow predicts zero drag — d'Alembert's 1752 paradox, and the panel says so honestly. Real air has viscosity: it can't follow the cylinder's back side, tears away, and leaves a churning low-pressure wake that sucks the object backwards. Streamlined shapes — teardrops, car bodies, radiator ducts that guide cooling air smoothly through the engine — exist to keep the flow attached so reality stays close to this drag-free ideal."
            ),
        ]
    )
}

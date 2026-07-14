//
//  GravityLabRealWorld.swift
//  Physics Playground — Gravity Lab module
//
//  The module's real-world story, rendered by the shell's RealWorldPanel.
//  Every claim should survive a physics teacher reading it.
//

import Foundation

enum GravityLabRealWorld {
    static let story = RealWorldStory(
        tagline: "Every satellite, GPS fix, and interplanetary probe is somebody doing exactly what you're doing — choosing a velocity and letting gravity drive.",
        applications: [
            RealWorldStory.Application(
                title: "Geostationary satellites",
                icon: "antenna.radiowaves.left.and.right",
                body: "Kepler's third law — which your trails are drawing right now — says orbital period depends only on distance. There is exactly one altitude, 35,786 km, where the period is 24 hours, so a satellite there hangs motionless over one spot on the equator. That's why TV dishes never move, and why that single ring of orbit is some of the most contested real estate off Earth."
            ),
            RealWorldStory.Application(
                title: "Getting to Mars",
                icon: "location.north.line.fill",
                body: "You can't fly straight at a planet — you throw your spacecraft into an ellipse whose far end touches Mars's orbit, exactly like the ellipses you make by releasing a planet a bit faster than circular speed. That's a Hohmann transfer. It's also why launch windows exist: Mars has to be at the ellipse's far end when you arrive, which lines up only every 26 months."
            ),
            RealWorldStory.Application(
                title: "Escape velocity & Voyager",
                icon: "airplane.departure",
                body: "Throw a planet at √2 times its circular speed — about 42 km/s near Earth's orbit — and the Sun never gets it back: total energy crosses zero and the panel flips to 'escaping'. Voyager 1 reached solar escape velocity by stealing a little orbital energy from Jupiter and Saturn in slingshot flybys — momentum-conserving encounters, the same conservation law your collisions obey."
            ),
        ]
    )
}

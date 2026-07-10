//
//  KinematicsRealWorld.swift
//  Physics Playground — Kinematics module
//
//  The module's real-world story, rendered by the shell's RealWorldPanel.
//  Every claim should survive a physics teacher reading it.
//

import Foundation

enum KinematicsRealWorld {
    static let story = RealWorldStory(
        tagline: "Every jump shot, artillery table, and crumple zone is this same math wearing different clothes.",
        applications: [
            RealWorldStory.Application(
                title: "Sports",
                icon: "figure.basketball",
                body: "In a vacuum 45° maximizes range — try it here. Turn air resistance on and the best angle drops, because hang time now costs speed; a basketball's optimum is around 40°, a golf drive's much lower. And golf dimples? They trip the airflow into a thin turbulent layer that hugs the ball, roughly halving drag (Cd ≈ 0.25 vs ≈ 0.47 for a smooth sphere) — a dimpled ball flies almost twice as far. That's why the golf preset barely feels the air toggle."
            ),
            RealWorldStory.Application(
                title: "Ballistics",
                icon: "scope",
                body: "Galileo proved in 1638 that a projectile's path is a parabola — with air, though, there's no formula, only integration, which is exactly what this module does numerically. Armies once employed rooms of human 'computers' to integrate artillery trajectories step by step into range tables; producing those tables faster was the first job ever given to ENIAC, the first general-purpose electronic computer."
            ),
            RealWorldStory.Application(
                title: "Vehicle safety",
                icon: "car.fill",
                body: "A landing projectile and a crashing car obey the same rule: the momentum change is fixed, so force depends on how long the stop takes (F·Δt = Δp). A crumple zone stretches a crash from centimeters to about a meter — cutting the peak force on passengers by an order of magnitude. It's the same physics as bending your knees to catch a ball instead of catching it stiff-armed."
            ),
        ]
    )
}

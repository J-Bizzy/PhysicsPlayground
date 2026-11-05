//
//  ControlMetrics.swift
//  RenderKit — Controls
//
//  The one control family: `ControlButton`, `ControlToggle`,
//  `ControlSlider`, `ControlSegments`, `ControlMenu` and `MoreButton`
//  (the segments and the menu joined on 2026-11-04, for More's tabs, its
//  clock and its lists of things to add), used for every control the app
//  draws, in a window or standing in the room. Stock visionOS glass,
//  system hover, SF Symbols, targets of at least 60 pt. In the room the
//  same SwiftUI views ride an entity (`ControlAttachment`), so a plate
//  beside the apparatus and a button in the title bar are one object.
//  The only glow is `LiveGlow`, and it means "this is live".
//

import SwiftUI

public enum ControlMetrics {
    /// The smallest thing a wearer is asked to aim at, in points. Apple's
    /// visionOS minimum for an interactive target.
    public static let minimumTarget: CGFloat = 60

    /// How many SwiftUI points make a metre when a view rides an entity in
    /// the room — RealityKit's attachment scale. Used only to lay
    /// attachments out against geometry measured in metres.
    public static let pointsPerMeter: Float = 1360

    /// A length in points, as metres in the room.
    public static func meters(_ points: CGFloat) -> Float {
        Float(points) / pointsPerMeter
    }

    /// Between neighbouring controls in a row or column.
    public static let spacing: CGFloat = 10
    /// Inside a glass panel, around its controls.
    public static let panelPadding: CGFloat = 18
    /// A glass panel's corner radius.
    public static let panelRadius: CGFloat = 32
    /// A tile's corner radius: rounder than a card, squarer than a capsule,
    /// so a grid of them reads as a grid rather than a stack of pills.
    public static let tileRadius: CGFloat = 18
    /// How long a confirming control stays armed: long enough to read
    /// "Tap again" and decide, short enough that walking away disarms it.
    public static let armWindow: Double = 4.0
    /// What an armed control says instead of its name.
    public static let armedTitle = "Tap again"
}

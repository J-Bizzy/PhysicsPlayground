//
//  DesignTokens.swift
//  Physics Playground — Design system
//
//  Single source of truth for color, type, and panel metrics. Renderers
//  use the UIColor originals; controls/legends use the SwiftUI twins, so
//  in-space entities and the legend cannot drift apart.
//
//  Physics color conventions are project-locked:
//    red = positive charge, blue = negative charge,
//    green/purple = ± test charge, cyan = field lines,
//    white halo = selection.
//

import RenderKit
import RealityKit
import SwiftUI

enum DesignTokens {
    // MARK: Colors

    enum Palette {
        // UIColor originals — used by RealityKit renderers for entity materials.
        static let positiveUI: UIColor = .systemRed
        static let negativeUI: UIColor = .systemBlue
        static let probePositiveUI: UIColor = .systemGreen
        static let probeNegativeUI: UIColor = .systemPurple
        /// Electric Fields' lines, derived from `electrostaticsAccent` (not
        /// hand-mixed near it) so the accent and the field move together.
        /// Yellow also clears both `positiveUI` red and `negativeUI` blue.
        static let fieldLineUI = UIColor(electrostaticsAccent)
        /// Magnetism's lines, derived the same way and for the same reason:
        /// the lines and the plates are one colour, and the accent clears the
        /// S pole's blue better than the old lavender did.
        static let magnetismLineUI = UIColor(magnetismAccent)
        static let selectionHaloUI: UIColor = .white

        // MARK: The two petal tints
        // A petal is coloured by what it does, not which lab it is in.

        /// Delete, clear, remove — the petal you cannot undo.
        static let destructiveUI = UIColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1)
        /// A petal that acts without destroying. Deliberately colourless, so
        /// destructive red is the only tinted petal on a ring.
        static let neutralActionUI = UIColor(white: 0.45, alpha: 1)
        static let projectileUI: UIColor = .systemOrange
        static let predictedArcUI: UIColor = .white
        static let launcherUI: UIColor = .systemGray
        static let targetUI: UIColor = .systemMint

        // SwiftUI twins — used by controls, legends, and hub cards.
        static let positive = Color(uiColor: positiveUI)
        static let negative = Color(uiColor: negativeUI)
        static let probePositive = Color(uiColor: probePositiveUI)
        static let probeNegative = Color(uiColor: probeNegativeUI)
        static let fieldLine = Color(uiColor: fieldLineUI)
        static let selectionHalo = Color(uiColor: selectionHaloUI)
        static let projectile = Color(uiColor: projectileUI)
        static let predictedArc = Color(uiColor: predictedArcUI)
        static let target = Color(uiColor: targetUI)

        // Orbital Mechanics
        // Aliases of RenderKit's VectorPalette — the one canon for the
        // vector trio, shared with the frozen-time arrows.
        static let velocityVectorUI: UIColor = VectorPalette.velocity
        static let accelerationVectorUI: UIColor = VectorPalette.acceleration
        static let forceVectorUI: UIColor = VectorPalette.force
        static let gravityVectorUI: UIColor = VectorPalette.gravity
        static let velocityVector = Color(uiColor: velocityVectorUI)
        static let sunColor = Color(uiColor: celestialUI("Sun"))

        /// The one colour authority for a body, keyed by its name: the texture's
        /// base fill, the trail and the hub miniature all read it, so a path is
        /// always its planet's colour. Every named body clears every other, the
        /// ring's accent and the vector trio by ΔE ≥ 12 (`AccentAuthorityTests`).
        /// "Sun", "Sun A", "Sun B" all read as suns; a world from the well is
        /// "World n" and takes a hue from the golden angle, so no two match.
        static func celestialUI(_ name: String) -> UIColor {
            if name.hasPrefix("Sun") {
                return UIColor(red: 1.0, green: 0.85, blue: 0.45, alpha: 1)
            }
            if name.hasPrefix("World "), let n = Int(name.dropFirst(6)) {
                let hue = (0.11 + Double(n) * 0.618034).truncatingRemainder(dividingBy: 1)
                return UIColor(hue: CGFloat(hue), saturation: 0.55, brightness: 0.95, alpha: 1)
            }
            return switch name {
            case "Mercury": UIColor(red: 0.58, green: 0.56, blue: 0.53, alpha: 1)
            case "Venus": UIColor(red: 0.88, green: 0.74, blue: 0.52, alpha: 1)
            case "Earth": UIColor(red: 0.24, green: 0.52, blue: 0.86, alpha: 1)
            case "Moon": UIColor(red: 0.78, green: 0.78, blue: 0.76, alpha: 1)
            case "Mars": UIColor(red: 0.85, green: 0.42, blue: 0.25, alpha: 1)
            case "Jupiter": UIColor(red: 0.78, green: 0.58, blue: 0.38, alpha: 1)
            case "Saturn": UIColor(red: 0.95, green: 0.88, blue: 0.60, alpha: 1)
            case "Uranus": UIColor(red: 0.60, green: 0.88, blue: 0.90, alpha: 1)
            case "Neptune": UIColor(red: 0.20, green: 0.35, blue: 0.90, alpha: 1)
            case "Asteroid": UIColor(red: 0.42, green: 0.40, blue: 0.38, alpha: 1)
            case "Comet": UIColor(red: 0.86, green: 0.93, blue: 1.0, alpha: 1)
            default: .systemTeal
            }
        }

        // Circuits
        static let copperUI = UIColor(red: 0.75, green: 0.48, blue: 0.25, alpha: 1)
        static let electronUI: UIColor = .systemCyan
        /// The motor's propeller — its own owned entry, not a borrowed hue.
        static let motorAccentUI = UIColor(red: 0.2, green: 0.85, blue: 0.75, alpha: 1)

        // Module accent colours, one per catalog entry, and the one authority
        // for the two domain hues (`HubDomain.color` reads the door values from
        // here). `HubTitleStyle`'s ivory and champagne stay outside: signage.
        /// Named for the module id, not the domain. #FFEA05 clears ΔE 20 from
        /// every `VectorPalette` entry, a live constraint.
        static let electrostaticsAccent = Color(red: 1.0, green: 0.92, blue: 0.02) // #FFEA05
        static let kinematicsAccent = Color(red: 1.00, green: 0.62, blue: 0.04)    // #FF9F0A, the Mechanics door
        /// Stock indigo/purple, measured on visionOS (indigo resolves to
        /// #6D7CFF here, not iOS's #5856D6) and owned as literals so the
        /// app knows what colour they are.
        static let gravityAccent = Color(red: 0.427, green: 0.486, blue: 1.0)      // #6D7CFF
        static let pendulumsAccent = Color(red: 0.859, green: 0.204, blue: 0.949)  // #DB34F2
        static let pendulumsAccentUI = UIColor(pendulumsAccent)
        static let circuitsAccent = Color(red: 0.19, green: 0.82, blue: 0.35)      // #30D158, the E&M door
        static let magnetismAccent = Color(red: 0.85, green: 0.3, blue: 0.62)
    }

    // MARK: Panel metrics

    enum Panel {
        // The corner radii are a scale: window, section, card, chip — radius
        // tracks the size of the thing it rounds.

        /// A whole flat window's container.
        static let windowRadius: CGFloat = 28
        /// A titled section inside a window.
        static let cornerRadius: CGFloat = 20
        /// A floating card: readouts, catalog entries, the first-run hint.
        static let cardRadius: CGFloat = 14
        /// A chip, badge or icon tile.
        static let chipRadius: CGFloat = 9
        static let padding: CGFloat = 20
        static let outerPadding: CGFloat = 22
        static let sectionSpacing: CGFloat = 20
    }

    // MARK: Type scale
    // Semantic fonts only, so Dynamic Type scales every module identically.

    enum TypeScale {
        static let cardTitle: Font = .title3.bold()
        static let sectionHeader: Font = .headline
        static let control: Font = .body
        static let label: Font = .callout
        static let footnote: Font = .footnote

        /// The flat-window wordmark voice: rounded and heavy. One function
        /// so the home window and the About card cannot drift apart. The
        /// In-Space wordmark is a separate voice (`HubTitleStyle`, geometry).
        static func wordmark(_ style: Font.TextStyle = .largeTitle) -> Font {
            .system(style, design: .rounded).weight(.heavy)
        }
    }
}

/// Strips input from an attachment entity and everything under it.
/// `.allowsHitTesting(false)` governs hit testing inside the SwiftUI
/// view, not the hosting entity, which can still intercept a pinch meant
/// for the object the card floats over.
@MainActor
func stripInput(from entity: Entity) {
    entity.components.remove(InputTargetComponent.self)
    entity.components.remove(CollisionComponent.self)
    for child in entity.children { stripInput(from: child) }
}

/// The house treatment for a floating readout card: padding, radius and
/// `.allowsHitTesting(false)` (the entity still needs `stripInput`). The
/// material is a parameter because Electric Fields' bright filaments
/// wash a regular panel out.
struct ReadoutCard: ViewModifier {
    let material: SwiftUI.Material

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(material,
                        in: RoundedRectangle(cornerRadius: DesignTokens.Panel.cardRadius,
                                             style: .continuous))
            .allowsHitTesting(false)
    }
}

extension View {
    /// A floating readout card, in the one treatment they all share. Pass a
    /// heavier material only where the room behind it demands one.
    func readoutCard(material: SwiftUI.Material = .regularMaterial) -> some View {
        modifier(ReadoutCard(material: material))
    }
}

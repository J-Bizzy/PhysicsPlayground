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
        /// Electric Fields' lines, derived FROM `electrostaticsAccent` (not
        /// hand-mixed near it) so the accent and the field move together.
        /// Yellow also clears both `positiveUI` red and `negativeUI` blue.
        static let fieldLineUI = UIColor(electrostaticsAccent)
        /// Magnetism's lines, derived the same way and for the same reason.
        ///
        /// It was a hardcoded lavender in `MagnetismRenderer` — ΔE 46 from
        /// the pink accent every plate and label in that lab wears, so the
        /// module's furniture and its centrepiece were two different
        /// colours. It was also the CLOSEST thing in the room to the S
        /// pole's blue (ΔE 31, against 58 for the accent), so following
        /// the house rule here separates the poles from the lines better
        /// than the exception did.
        static let magnetismLineUI = UIColor(magnetismAccent)
        static let selectionHaloUI: UIColor = .white

        // MARK: The two petal tints
        //
        // A petal is coloured by WHAT IT DOES, not which lab it is in.

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

        // Gravity Lab
        // Aliases of RenderKit's VectorPalette — the one canon for the
        // vector trio, shared with the frozen-time arrows.
        static let velocityVectorUI: UIColor = VectorPalette.velocity
        static let accelerationVectorUI: UIColor = VectorPalette.acceleration
        static let forceVectorUI: UIColor = VectorPalette.force
        static let gravityVectorUI: UIColor = VectorPalette.gravity
        static let velocityVector = Color(uiColor: velocityVectorUI)
        static let sunColor = Color(uiColor: celestialUI("Sun"))

        /// Celestial body colors, keyed by preset name (custom = teal).
        /// "Sun", "Sun A", "Sun B" all read as suns.
        static func celestialUI(_ name: String) -> UIColor {
            if name.hasPrefix("Sun") {
                return UIColor(red: 1.0, green: 0.85, blue: 0.45, alpha: 1)
            }
            return switch name {
            case "Mercury": .systemGray
            case "Venus": UIColor(red: 0.85, green: 0.72, blue: 0.52, alpha: 1)
            case "Earth": .systemBlue
            case "Moon": UIColor(white: 0.75, alpha: 1)
            case "Mars": UIColor(red: 0.83, green: 0.4, blue: 0.26, alpha: 1)
            case "Jupiter": UIColor(red: 0.82, green: 0.64, blue: 0.46, alpha: 1)
            case "Asteroid": UIColor(white: 0.55, alpha: 1)
            default: .systemTeal
            }
        }

        // Circuits
        static let copperUI = UIColor(red: 0.75, green: 0.48, blue: 0.25, alpha: 1)
        static let electronUI: UIColor = .systemCyan
        /// The motor's propeller — its own owned entry, not a borrowed hue.
        static let motorAccentUI = UIColor(red: 0.2, green: 0.85, blue: 0.75, alpha: 1)

        // Module accent colors, one per catalog entry — and the ONE
        // authority for the two domain hues. `HubDomain.color` reads the
        // door values (#30D158/#FF9F0A) from here. (`HubTitleStyle`'s
        // ivory/champagne stay OUTSIDE this accent system — signage.)
        /// Named for the module id, not the domain. #FFEA05 — searched to
        /// clear ΔE 20 from every `VectorPalette` entry (a live constraint).
        static let electrostaticsAccent = Color(red: 1.0, green: 0.92, blue: 0.02) // #FFEA05
        static let kinematicsAccent = Color(red: 1.00, green: 0.62, blue: 0.04)    // #FF9F0A, the Mechanics door
        /// Stock indigo/purple, MEASURED on visionOS (indigo resolves to
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
        // THE CORNER RADII ARE A SCALE, NOT A CONSTANT: 28/20/14/9 are four
        // different surfaces — window, section, card, chip — and radius
        // tracks the size of the thing it rounds.

        /// A whole flat window's container.
        static let windowRadius: CGFloat = 28
        /// A titled section inside a window (`PanelSection`).
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
        /// IN-SPACE wordmark is a separate voice (`HubTitleStyle`, geometry).
        static func wordmark(_ style: Font.TextStyle = .largeTitle) -> Font {
            .system(style, design: .rounded).weight(.heavy)
        }
    }
}

/// Strips input from an attachment entity and everything under it.
///
/// `.allowsHitTesting(false)` governs hit testing INSIDE the SwiftUI view;
/// it is not a promise about the hosting RealityKit entity, which can
/// still carry an InputTargetComponent/CollisionComponent and intercept a
/// pinch meant for the bob/part/planet the card floats over.
@MainActor
func stripInput(from entity: Entity) {
    entity.components.remove(InputTargetComponent.self)
    entity.components.remove(CollisionComponent.self)
    for child in entity.children { stripInput(from: child) }
}

/// The house treatment for a floating readout card.
///
/// THE MATERIAL IS A PARAMETER AND THE RADIUS IS NOT. It carries
/// `.allowsHitTesting(false)` (the entity still needs `stripInput` — SwiftUI
/// hit testing is not the entity's). Pass a heavier material only where the
/// room behind it demands one; Electric Fields uses `.thickMaterial` because
/// its bright translucent filaments wash a regular-material panel out.
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
    /// A floating readout card, in the one treatment they all share.
    ///
    /// Pass a heavier material only where the room behind it demands one,
    /// and say why at the call site.
    func readoutCard(material: SwiftUI.Material = .regularMaterial) -> some View {
        modifier(ReadoutCard(material: material))
    }
}

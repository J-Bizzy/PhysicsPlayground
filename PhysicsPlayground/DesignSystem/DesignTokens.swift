//
//  DesignTokens.swift
//  Physics Playground — Design system
//
//  The single source of truth for color, type, and panel metrics across the
//  hub and every module. Nothing else in the app hardcodes a color or a
//  corner radius: panels reference these tokens, and renderers reference
//  the UIColor twins so the in-space entities and the legend can never
//  drift apart.
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
        static let fieldLineUI = UIColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 1)
        static let selectionHaloUI: UIColor = .white
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
        // `arrowStrong` (Color.yellow) was deleted 2026-08-06: zero call
        // sites — VectorFieldArrows owns its own ramp and never read
        // this. A token nobody reads is unreachable choice, and this
        // project deletes unreachable choice (hintCornerRadius went the
        // same way).

        /// Completion gold — the colour of DONE, everywhere it is said:
        /// the in-space progress ring's full band and the flat catalog's
        /// "N of N experiments" line. One value, two surfaces, so the
        /// two claims of completeness cannot drift apart.
        static let completionGoldUI = UIColor(red: 1.0, green: 0.84, blue: 0.25, alpha: 1)
        static let completionGold = Color(uiColor: completionGoldUI)

        // Gravity Lab
        // Aliases of RenderKit's VectorPalette — the one canon for the
        // vector trio, shared with the frozen-time arrows.
        static let velocityVectorUI: UIColor = VectorPalette.velocity
        static let accelerationVectorUI: UIColor = VectorPalette.acceleration
        static let forceVectorUI: UIColor = VectorPalette.force
        static let velocityVector = Color(uiColor: velocityVectorUI)
        static let accelerationVector = Color(uiColor: accelerationVectorUI)
        static let forceVector = Color(uiColor: forceVectorUI)
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
        /// The motor's propeller. Its own entry rather than a borrowed
        /// one: this teal was hand-typed at the call site and happened
        /// to match nothing, which is the state a palette exists to
        /// prevent — an unowned hue on a physics object.
        static let motorAccentUI = UIColor(red: 0.2, green: 0.85, blue: 0.75, alpha: 1)

        // Module accent colors, one per catalog entry — and the ONE
        // authority for the two domain hues (2026-08-06). Circuits and
        // Projectiles used to wear stock `Color.green`/`.orange` while
        // their domain doors wore #30D158/#FF9F0A — two greens and two
        // oranges defined independently, near enough to read as the
        // same colour badly printed. The accents adopted the richer
        // door values and `HubDomain.color` reads them from here.
        // (`HubTitleStyle.ivory`/`.champagne` stay where they are: the
        // in-space brand voice is deliberately OUTSIDE this accent
        // system — signage, not wayfinding.)
        /// Named for the module id ("electrostatics"), not the domain —
        /// it was `electromagnetismAccent = .yellow`, a stock colour
        /// wearing its neighbour module's subject as a name.
        static let electrostaticsAccent = Color(red: 1.0, green: 0.84, blue: 0.04) // #FFD60A
        static let kinematicsAccent = Color(red: 1.00, green: 0.62, blue: 0.04)    // #FF9F0A, the Mechanics door
        static let gravityAccent = Color.indigo
        static let pendulumsAccentUI = UIColor(Color.purple)
        static let circuitsAccent = Color(red: 0.19, green: 0.82, blue: 0.35)      // #30D158, the E&M door
        static let pendulumsAccent = Color.purple
        static let magnetismAccent = Color(red: 0.85, green: 0.3, blue: 0.62)
    }

    // MARK: Panel metrics

    enum Panel {
        static let cornerRadius: CGFloat = 20
        // `hintCornerRadius` (16) was deleted 2026-08-05: minted for a
        // hint card that never adopted it, read by nothing. A token with
        // no callers is unreachable choice, and this project deletes
        // unreachable choice (the HubTitleStyle enum went the same way).
        static let padding: CGFloat = 20
        // Tightened for a more condensed window/pod rhythm (card interiors
        // keep their padding; only the gaps between blocks shrink).
        static let outerPadding: CGFloat = 22
        static let sectionSpacing: CGFloat = 20
        static let rowSpacing: CGFloat = 12
    }

    // MARK: Type scale
    // Semantic fonts only, so Dynamic Type scales every module identically.

    enum TypeScale {
        static let screenTitle: Font = .largeTitle.bold()
        static let cardTitle: Font = .title3.bold()
        static let sectionHeader: Font = .headline
        static let control: Font = .body
        static let label: Font = .callout
        static let footnote: Font = .footnote

        /// The flat-window wordmark voice: rounded and heavy, at
        /// whatever text style the surface calls for. One function so
        /// the home window and the About card cannot drift apart —
        /// they had (largeTitle vs title2 was fine; the design could
        /// have diverged silently). The IN-SPACE wordmark is a separate,
        /// ratified voice: the machined plaque (`HubTitleStyle`), which
        /// is geometry, not a Font.
        static func wordmark(_ style: Font.TextStyle = .largeTitle) -> Font {
            .system(style, design: .rounded).weight(.heavy)
        }
    }
}

/// Strips input from an attachment entity and everything under it.
///
/// `.allowsHitTesting(false)` governs hit testing INSIDE the SwiftUI
/// view; it is not a promise about the RealityKit entity the attachment
/// is hosted in, which can still carry an `InputTargetComponent` and a
/// `CollisionComponent` sized to the card. A readout that intercepts a
/// pinch is the `SpatialScaleHandle` failure (DECISIONS.md, 2026-07-29)
/// — and these cards float directly over bobs, parts and planets that
/// are all meant to be grabbed. Belt and braces, because the failure
/// mode is invisible: the card looks right and the thing behind it
/// silently stops responding.
@MainActor
func stripInput(from entity: Entity) {
    entity.components.remove(InputTargetComponent.self)
    entity.components.remove(CollisionComponent.self)
    for child in entity.children { stripInput(from: child) }
}

/// The house treatment for a floating readout card.
///
/// Four cards, four not-quite-matching treatments: `.regularMaterial` at
/// radius 14 in Circuits and Gravity Lab, `.thickMaterial` at 14 in
/// Electric Fields, `.regularMaterial` at 12 in Pendulums. Nobody chose
/// three different cards; they were written on different days.
///
/// It carries `.allowsHitTesting(false)` too, because that is not a
/// per-card decision either — a readout that intercepts a pinch is the
/// `SpatialScaleHandle` failure, and these cards float directly over the
/// bobs, parts and planets they describe. (The entity still needs
/// `stripInput`; see above for why one is not the other.)
/// THE MATERIAL IS A PARAMETER AND THE RADIUS IS NOT, which is the whole
/// judgement in this type. Three of the four cards drifted apart by
/// accident and are unified. The fourth — Electric Fields' — is
/// `.thickMaterial` for a REASON that is recorded at its call site: it
/// stands in a room whose physics is drawn as bright translucent
/// filaments, and a screenshot showed a regular-material panel washing
/// out until the 50 kT disclosure was the least legible text on screen.
/// Flattening that would have undone a fix somebody found by looking.
struct ReadoutCard: ViewModifier {
    let material: SwiftUI.Material

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(material,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

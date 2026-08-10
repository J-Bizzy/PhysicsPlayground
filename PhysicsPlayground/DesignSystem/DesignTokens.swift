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
        /// ELECTRIC FIELDS' LINES, IN ELECTRIC FIELDS' COLOUR.
        ///
        /// Pale cyan (0.45, 0.85, 1.0) until 2026-08-09, which was a hue
        /// this module owned nowhere else: the door sign, the nameplate,
        /// the switch labels and the plates all wear
        /// `electrostaticsAccent`, and the one thing the lab is actually
        /// ABOUT wore something unrelated. Owner's call — the lines
        /// match the theme.
        ///
        /// Taken FROM the accent rather than hand-mixed near it. A
        /// hand-mixed warm yellow would land a few ΔE from #FFEA05,
        /// which is the "two shades of the same yellow" failure the
        /// accent's own doc comment below was written about; and derived
        /// this way, a future move of the accent takes the field with it
        /// instead of leaving them a little apart.
        ///
        /// It also un-collides the charges. Cyan lines ran through blue
        /// negative charges — the field and one of its two sources in
        /// the same corner of the wheel — and yellow is clear of both
        /// `positiveUI` red and `negativeUI` blue.
        static let fieldLineUI = UIColor(electrostaticsAccent)
        static let selectionHaloUI: UIColor = .white

        // MARK: The two petal tints
        //
        // A ring's petals are the only place in the app where a control
        // is coloured by WHAT IT DOES rather than by which lab it is in,
        // and both tints were hand-typed at every call site: this red
        // seven times across six modules, the grey below six times
        // across four. Nobody chose seven reds; they were copied.
        //
        // The values are exactly what was already there, so nothing
        // moves today. The point is tomorrow: a hue that lives in seven
        // files drifts one file at a time, and two shades of red on
        // adjacent rings is the failure this palette's own accent notes
        // were written about.

        /// Delete, clear, remove — the petal you cannot undo.
        static let destructiveUI = UIColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1)
        /// A petal that acts without destroying: reset a value, cycle a
        /// choice, open a picker. Deliberately colourless, so the
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
        // `arrowStrong` (Color.yellow) was deleted 2026-08-06: zero call
        // sites — VectorFieldArrows owns its own ramp and never read
        // this. A token nobody reads is unreachable choice, and this
        // project deletes unreachable choice (hintCornerRadius went the
        // same way).

        // `completionGold` (#FFD640) was deleted 2026-08-09 with the
        // experiments system, under the rule stated six lines above: a
        // token nobody reads is unreachable choice. It was the colour of
        // DONE — the progress ring's full band and the catalog's
        // "N of N experiments" line — and both surfaces went the same
        // day, leaving one live reader, a test asserting that no module
        // accent collided with it. A reservation protecting nothing is
        // not a guardrail. Its number survives in `electrostaticsAccent`
        // below, which was moved to clear it and should not drift back.

        // Gravity Lab
        // Aliases of RenderKit's VectorPalette — the one canon for the
        // vector trio, shared with the frozen-time arrows.
        static let velocityVectorUI: UIColor = VectorPalette.velocity
        static let accelerationVectorUI: UIColor = VectorPalette.acceleration
        static let forceVectorUI: UIColor = VectorPalette.force
        static let gravityVectorUI: UIColor = VectorPalette.gravity
        static let velocityVector = Color(uiColor: velocityVectorUI)
        // The `accelerationVector` and `forceVector` SwiftUI twins were
        // deleted 2026-08-09, unread. The vector trio is drawn in the
        // ROOM, by renderers that take the `…UI` originals; the twins
        // exist for legends and cards, and only velocity ever appeared
        // in one. Same rule as `arrowStrong` above — a token nobody
        // reads is unreachable choice. Both `…UI` forms stay: they are
        // live, and `AccentAuthorityTests` measures accents against
        // them.
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
        /// #FFEA05, and it was #FFD60A until 2026-08-08.
        ///
        /// (1.0, 0.84, 0.04) against the completion gold of the day
        /// (1.0, 0.84, 0.25) was the same red, the same green, and 0.21
        /// of blue between them — ΔE 11.6, which is two shades of the
        /// same yellow. Gold was RESERVED for "you have finished
        /// something", so a module whose every plate and well wore
        /// near-gold quietly congratulated the user for standing in the
        /// room.
        ///
        /// The shift was the SMALLEST one clearing ΔE 20 from gold and
        /// from every `VectorPalette` entry — searched rather than
        /// picked, because any yellow clearly distinct from a gold is
        /// necessarily a hue change and the honest move is the least of
        /// them. It travels ΔE 12.2 from the old value and stays
        /// unmistakably electric yellow.
        ///
        /// THE GOLD ITSELF WENT WITH THE EXPERIMENTS on 2026-08-09, so
        /// half this argument is now archaeology. The value stays where
        /// the search put it: the `VectorPalette` half of the constraint
        /// is still live, and moving back toward #FFD60A to reclaim a
        /// vacated reservation would be re-deciding a settled hue for
        /// the sake of a colour nothing draws.
        static let electrostaticsAccent = Color(red: 1.0, green: 0.92, blue: 0.02) // #FFEA05
        static let kinematicsAccent = Color(red: 1.00, green: 0.62, blue: 0.04)    // #FF9F0A, the Mechanics door
        /// THE LAST TWO STOCK ACCENTS, OWNED — 2026-08-09.
        ///
        /// These were `Color.indigo` and `Color.purple` while the four
        /// above were owned literals, in the file whose own argument is
        /// that an unowned hue is the drift the unification removed.
        /// `testThePaletteOwnsItsAccentHues` missed them because it
        /// grepped for three specific spellings — `Color.yellow`,
        /// `.green`, `.orange` — which are the three that happened to
        /// be wrong the day it was written. It reflects now.
        ///
        /// THE VALUES ARE THE STOCK ONES, MEASURED, not replacements
        /// chosen for them. Nothing about these two doors was wrong on
        /// screen; what was wrong is that the app did not know what
        /// colour they were. Owning a hue and redesigning it are
        /// different jobs and this is the first — if the indigo should
        /// move, that is a decision to make on a photograph.
        ///
        /// Measured on visionOS rather than assumed: `Color.indigo`
        /// resolves to #6D7CFF here, not the #5856D6 that iOS
        /// documentation would have you type. A "system colour" is a
        /// promise about semantics, not about a number, which is the
        /// second reason not to build a palette out of them.
        static let gravityAccent = Color(red: 0.427, green: 0.486, blue: 1.0)      // #6D7CFF
        static let pendulumsAccent = Color(red: 0.859, green: 0.204, blue: 0.949)  // #DB34F2
        static let pendulumsAccentUI = UIColor(pendulumsAccent)
        static let circuitsAccent = Color(red: 0.19, green: 0.82, blue: 0.35)      // #30D158, the E&M door
        static let magnetismAccent = Color(red: 0.85, green: 0.3, blue: 0.62)
    }

    // MARK: Panel metrics

    enum Panel {
        // THE CORNER RADII ARE A SCALE, NOT A CONSTANT — resolved
        // 2026-08-09, after an audit reported "six radii for one token"
        // and the honest answer turned out to be neither "adopt the
        // token everywhere" nor "delete it".
        //
        // 28 / 20 / 14 / 9 are four different SURFACES: a whole window,
        // a section inside one, a floating card, a chip or icon tile.
        // Forcing them to one number would make a chip look like a
        // window; radius tracks the size of the thing it is rounding,
        // which is why every UI that has more than one panel size has
        // more than one radius.
        //
        // What WAS drift is the near-duplicates. A hint card at 12 beside
        // readout cards at 14, and a chip at 8 beside an icon tile at 9 —
        // nobody chose those pairs, they were written on different days,
        // and each pair is one concept at two values. Naming the four
        // steps is what makes the difference between the steps legible
        // and the difference within a step impossible.

        /// A whole flat window's container.
        static let windowRadius: CGFloat = 28
        /// A titled section inside a window (`PanelSection`) — Settings
        /// and the Notebook.
        static let cornerRadius: CGFloat = 20
        /// A floating card: readouts, catalog entries, the first-run hint.
        static let cardRadius: CGFloat = 14
        /// A chip, badge or icon tile.
        static let chipRadius: CGFloat = 9
        // `hintCornerRadius` (16) was deleted 2026-08-05: minted for a
        // hint card that never adopted it, read by nothing. A token with
        // no callers is unreachable choice, and this project deletes
        // unreachable choice (the HubTitleStyle enum went the same way).
        static let padding: CGFloat = 20
        // Tightened for a more condensed window/pod rhythm (card interiors
        // keep their padding; only the gaps between blocks shrink).
        static let outerPadding: CGFloat = 22
        static let sectionSpacing: CGFloat = 20
        // `rowSpacing` (12) was deleted 2026-08-09: zero readers, and it
        // measured the gap between rows of a MODULE PANEL, which is a
        // surface this app stopped having on 2026-08-01.
    }

    // MARK: Type scale
    // Semantic fonts only, so Dynamic Type scales every module identically.

    enum TypeScale {
        // `screenTitle` (.largeTitle.bold()) was deleted 2026-08-09,
        // unread: the app's two remaining flat windows title themselves
        // with `wordmark(_:)` below, which is the ratified voice.
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

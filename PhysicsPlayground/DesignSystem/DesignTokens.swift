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
//    orange/indigo = ± equipotential shells, white halo = selection.
//

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
        static let positiveShellUI: UIColor = .systemOrange
        static let negativeShellUI: UIColor = .systemIndigo
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
        static let positiveShell = Color(uiColor: positiveShellUI)
        static let negativeShell = Color(uiColor: negativeShellUI)
        static let selectionHalo = Color(uiColor: selectionHaloUI)
        static let projectile = Color(uiColor: projectileUI)
        static let predictedArc = Color(uiColor: predictedArcUI)
        static let target = Color(uiColor: targetUI)
        /// The bright end of the arrow-strength ramp (see VectorFieldArrows).
        static let arrowStrong = Color.yellow

        // Gravity Lab
        static let velocityVectorUI: UIColor = .systemBlue
        static let accelerationVectorUI: UIColor = .systemOrange
        static let forceVectorUI: UIColor = .systemRed
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

        // Waves
        static let waveSourceUI: UIColor = .systemTeal
        static let waveInvertedUI: UIColor = .systemOrange
        static let waveSource = Color(uiColor: waveSourceUI)
        static let waveInverted = Color(uiColor: waveInvertedUI)

        // Wind tunnel
        static let streamlineUI: UIColor = .systemMint

        // Module accent colors, one per catalog entry.
        static let electromagnetismAccent = Color.yellow
        static let kinematicsAccent = Color.orange
        static let gravityAccent = Color.indigo
        static let wavesAccent = Color.cyan
        static let windAccent = Color.mint
    }

    // MARK: Panel metrics

    enum Panel {
        static let cornerRadius: CGFloat = 20
        static let hintCornerRadius: CGFloat = 16
        static let padding: CGFloat = 20
        static let outerPadding: CGFloat = 28
        static let sectionSpacing: CGFloat = 24
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
    }
}

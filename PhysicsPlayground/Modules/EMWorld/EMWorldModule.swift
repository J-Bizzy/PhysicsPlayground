//
//  EMWorldModule.swift
//  Physics Playground — Electricity & Magnetism
//
//  Catalog registration for the merged E&M world.
//
//  Circuit Workshop and Magnetism were two entries on the shelf that
//  already shared a physical law and a variable: a coil carrying a
//  current is a magnet, m = N·I·A, and the magnet bench had been
//  reading the circuit bench's inductor current the whole time. What
//  it could not do was let you SEE it, because the two benches were in
//  different rooms and getting from one to the other meant leaving.
//
//  One world, two stations, one cable. Build a loop on the left, wire
//  an inductor into it, and a coil on the right becomes a magnet that
//  moves the bar magnets around it. Open the switch and watch the
//  whole right-hand side go slack.
//
//  The two modules keep their own files, models, renderers, panels and
//  legends; this composes them. Reset resets both, pause freezes both,
//  and the notebook writes down both benches plus the number that
//  joins them.
//

import SwiftUI
import PhysicsCore

@MainActor
enum EMWorldModule {
    static let id = "em"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Electricity & Magnetism",
            shortTitle: "E&M",
            blurb: "Charges, circuits and magnets in one room: place the charges that make a field, build the circuit that moves them, and watch its current turn a coil into a magnet across the room.",
            icon: "bolt.circle.fill",
            accent: DesignTokens.Palette.circuitsAccent,
            firstRunHint: "Three benches, one room. STRAIGHT AHEAD are the charges — drag one and its field follows. On your LEFT the circuit is already live: pinch the switch lever to break it, or drag parts off the tray. On your RIGHT, carry the bar magnets and watch their field reorganise. Whichever bench you touch comes forward and the others stand back. To join the left and right: drop an inductor into the circuit and switch the electromagnet on in this window — a cable appears, and the coil becomes a magnet powered by your loop.",
            // Both halves need contrast: the magnetic field lines and
            // the electron beads are thin bright things, and a sunlit
            // wall eats them.
            preferredDimming: 0.35,
            legend: legend,
            // Freeze-everything means everything: the orb reads as
            // paused only when both benches are, and pressing it
            // commits both to whichever state that isn't.
            isPaused: {
                appModel.circuitsModel.isPaused
                    && appModel.magnetismModel.isPaused
                    && appModel.electromagnetismModel.isPaused
            },
            togglePause: {
                let paused = appModel.circuitsModel.isPaused
                    && appModel.magnetismModel.isPaused
                    && appModel.electromagnetismModel.isPaused
                appModel.circuitsModel.isPaused = !paused
                appModel.magnetismModel.isPaused = !paused
                appModel.electromagnetismModel.isPaused = !paused
            },
            makeScene: {
                AnyView(
                    EMWorldSpaceView()
                        .environment(appModel.circuitsModel)
                        .environment(appModel.magnetismModel)
                        .environment(appModel.electromagnetismModel)
                )
            },
            makeControls: {
                AnyView(
                    EMWorldControlsPanel()
                        .environment(appModel.circuitsModel)
                        .environment(appModel.magnetismModel)
                        .environment(appModel.electromagnetismModel)
                )
            },
            captureReadings: { readings(appModel: appModel) },
            reset: {
                appModel.circuitsModel.reset()
                appModel.magnetismModel.reset()
                appModel.electromagnetismModel.reset()
            }
        )
    }

    /// Both benches' readings, plus the one number that belongs to
    /// neither of them alone.
    static func readings(appModel: AppModel) -> [NotebookEntry.Reading] {
        var rows = ElectromagnetismModule.readings(appModel: appModel)
        rows.append(contentsOf: CircuitsModule.readings(appModel: appModel))
        rows.append(contentsOf: MagnetismModule.readings(appModel: appModel))
        let current = appModel.circuitsModel.inductorCurrent
        if appModel.magnetismModel.electromagnetOn {
            rows.append(.init("Coil feed current",
                              String(format: "%.4f", current), "A"))
        }
        return rows
    }

    /// Curated rather than concatenated. Both benches have a full
    /// legend of their own and stacking them makes a wall of eleven
    /// rows; these are the ones a reader needs to decode what is
    /// actually moving in front of them, ordered left bench, cable,
    /// right bench.
    private static let legend: [LegendItem] = [
        LegendItem(
            swatch: .fill(DesignTokens.Palette.positive),
            text: "Positive charge (and a magnet's N pole) — red is + throughout"),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.negative),
            text: "Negative charge (and a magnet's S pole) — blue is − throughout"),
        LegendItem(
            swatch: .line(DesignTokens.Palette.fieldLine),
            text: "Electric field lines run from positive to negative"),
        LegendItem(
            swatch: .fill(Color(uiColor: DesignTokens.Palette.copperUI)),
            text: "Copper terminals — pinch one, then another, to wire them; pinch a wire to remove it"),
        LegendItem(
            swatch: .fill(Color(uiColor: DesignTokens.Palette.electronUI)),
            text: "Electrons — they drift − to +, opposite the conventional current arrow, faster where the current is larger"),
        LegendItem(
            swatch: .fill(.yellow),
            text: "Bulb glow = true power dissipated (P = I²R) — dim it by adding resistance"),
        LegendItem(
            swatch: .line(Color(uiColor: DesignTokens.Palette.copperUI)),
            text: "The cable across the room carries the bench's inductor current to the coil — the same electrons, the same speed"),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.positive),
            text: "North pole (red)"),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.negative),
            text: "South pole (blue)"),
        LegendItem(
            swatch: .line(Color(uiColor: MagnetismRenderer.lineColor)),
            text: "Field lines — closed loops running N to S outside the magnet"),
        LegendItem(
            swatch: .symbol("location.north.fill",
                            Color(uiColor: MagnetismRenderer.lineColor)),
            text: "Compass needles point along the local field"),
    ]
}

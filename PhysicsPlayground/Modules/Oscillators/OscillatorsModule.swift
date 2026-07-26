//
//  OscillatorsModule.swift
//  Physics Playground — Oscillators
//
//  PENDULUMS and SPRINGS, in one module.
//
//  They were two catalog entries teaching one chapter. A pendulum and a
//  mass on a spring are the same idea twice — a restoring force
//  proportional to displacement, a period that ignores amplitude, energy
//  trading between kinetic and potential — and the whole point of
//  putting them side by side is that T = 2π√(L/g) and T = 2π√(m/k) are
//  the SAME formula wearing different clothes. Split across two menu
//  entries, that comparison never happens.
//
//  Both benches keep their own model, renderer and space view; this is
//  the catalog entry that hosts them, plus the switch between them.
//

import PhysicsCore
import SwiftUI
import simd

/// Which oscillator bench is showing.
enum OscillatorBench: String, CaseIterable, Identifiable {
    case pendulum, spring
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pendulum: "Pendulum"
        case .spring: "Spring"
        }
    }

    var icon: String {
        switch self {
        case .pendulum: "pendulum"
        case .spring: "waveform.path"
        }
    }

    var accent: Color {
        switch self {
        case .pendulum: DesignTokens.Palette.pendulumsAccent
        case .spring: DesignTokens.Palette.springsAccent
        }
    }
}

@MainActor
enum OscillatorsModule {
    /// Keeps the pendulums id so saved layouts and completed experiments
    /// survive the merge.
    static let id = "pendulums"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        let bench = appModel.oscillatorBench
        return ModuleDescriptor(
            id: id,
            title: "Oscillators",
            blurb: "One bench, two ways to swing: steel bobs on a beam and a block on a spring. Both obey the same law — and their periods, 2π√(L/g) and 2π√(m/k), are the same formula in different clothes.",
            icon: "metronome.fill",
            accent: bench.accent,
            firstRunHint: bench == .pendulum
                ? "Five pendulums are already running, their lengths 4% apart: they leave together, drift into a travelling wave, scramble, and re-align. Grab any bob and throw it sideways for a true 3-D orbit."
                : "Two blocks, three springs. Pull one along its rail and let go — watch its energy drain into the other and slosh back, a beat set by the difference of the two normal-mode frequencies.",
            legend: bench == .pendulum
                ? PendulumsModule.legendItems
                : SpringsModule.legendItems,
            isPaused: {
                bench == .pendulum
                    ? appModel.pendulumsModel.isPaused
                    : appModel.springsModel.isPaused
            },
            togglePause: {
                switch bench {
                case .pendulum: appModel.pendulumsModel.isPaused.toggle()
                case .spring: appModel.springsModel.isPaused.toggle()
                }
            },
            makeControls: {
                AnyView(
                    VStack(alignment: .leading, spacing: DesignTokens.Panel.rowSpacing) {
                        OscillatorBenchPicker()
                        PeriodComparison()
                        switch bench {
                        case .pendulum:
                            PendulumsControlsView()
                                .environment(appModel.pendulumsModel)
                        case .spring:
                            SpringsControlsView()
                                .environment(appModel.springsModel)
                        }
                    }
                )
            },
            makeScene: {
                switch bench {
                case .pendulum:
                    AnyView(PendulumsSpaceView().environment(appModel.pendulumsModel))
                case .spring:
                    AnyView(SpringsSpaceView().environment(appModel.springsModel))
                }
            },
            captureReadings: {
                switch bench {
                case .pendulum: PendulumsModule.readings(appModel: appModel)
                case .spring: SpringsModule.readings(appModel: appModel)
                }
            },
            reset: {
                switch bench {
                case .pendulum: appModel.pendulumsModel.reset()
                case .spring: appModel.springsModel.reset()
                }
            }
        )
    }
}

struct OscillatorBenchPicker: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel
        Picker("Bench", selection: $appModel.oscillatorBench) {
            ForEach(OscillatorBench.allCases) { bench in
                Text(bench.displayName).tag(bench)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Oscillator bench")
    }
}

/// Both periods, side by side, always.
///
/// This is the reason the two benches share a module: whichever one you
/// are looking at, the other's period is right there, so the parallel is
/// impossible to miss. Change the pendulum's length and its number
/// moves while the spring's sits still; change the mass and it is the
/// spring's that moves — mass is in one formula and not the other, which
/// is exactly the thing students get wrong.
struct PeriodComparison: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let pendulums = appModel.pendulumsModel
        let springs = appModel.springsModel
        let pendulumPeriod = pendulums.selected?.period(gravity: pendulums.gravity)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("T = 2π√(L/g)")
                Spacer(minLength: 8)
                Text(pendulumPeriod.map { String(format: "%.3f s", $0) } ?? "—")
                    .monospacedDigit()
            }
            .foregroundStyle(appModel.oscillatorBench == .pendulum
                             ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            HStack {
                Text("T = 2π√(m/k)")
                Spacer(minLength: 8)
                Text(String(format: "%.3f s", springs.period))
                    .monospacedDigit()
            }
            .foregroundStyle(appModel.oscillatorBench == .spring
                             ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            Text("Neither period contains the mass swinging on the string. Only one contains the mass on the spring.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        }
        .font(DesignTokens.TypeScale.control)
    }
}

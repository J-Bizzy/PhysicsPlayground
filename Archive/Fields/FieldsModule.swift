//
//  FieldsModule.swift
//  Physics Playground — Fields
//
//  ELECTRIC and MAGNETIC, in one module.
//
//  They were two catalog entries, and they were the same experience:
//  place sources in a room-scale volume, drag them, and watch a global
//  field of glowing lines reorganise live. Same verb, same shape of
//  scene, same controls — only the math behind the line differs, and
//  differing math is not a reason to make someone leave one room and
//  walk into another. Worse, keeping them apart hid the thing that
//  makes electromagnetism interesting: that E and B are two halves of
//  ONE field, coupled by F = q(E + v × B).
//
//  So: one module, two benches, one switch. The Electric bench keeps
//  its charges, equipotential shells, capacitor, Gauss surface and its
//  uniform-B mode with the Boris pusher — which is where the coupling
//  actually lives, and which is now one tap from the magnets rather
//  than buried in a different module's pod.
//
//  Both benches keep their own model, renderer and space view
//  untouched; this file is purely the catalog entry that hosts them.
//

import PhysicsCore
import SwiftUI
import simd

/// Which bench the Fields module is showing.
enum FieldsBench: String, CaseIterable, Identifiable {
    case electric, magnetic
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .electric: "Electric"
        case .magnetic: "Magnetic"
        }
    }

    var icon: String {
        switch self {
        case .electric: "bolt.fill"
        case .magnetic: "cylinder.fill"
        }
    }

    var accent: Color {
        switch self {
        case .electric: DesignTokens.Palette.electromagnetismAccent
        case .magnetic: DesignTokens.Palette.magnetismAccent
        }
    }
}

@MainActor
enum FieldsModule {
    /// Keeps the old electrostatics id, so saved pod layouts, dismissed
    /// hints and completed experiments all survive the merge.
    static let id = "electrostatics"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        let bench = appModel.fieldsBench
        return ModuleDescriptor(
            id: id,
            title: "Fields",
            blurb: "Two benches, one field. Place charges and trace their lines, or carry bar magnets and watch their loops thread the room — then put a charge in a magnetic field and watch F = q(v × B) curl it into a circle.",
            icon: "bolt.horizontal.circle.fill",
            accent: bench.accent,
            podsCoverControls: bench == .magnetic,
            firstRunHint: bench == .electric
                ? "A dipole is already here. Look at a charge and pinch to carry it — the field follows your hand. Switch to the Magnetic bench any time; the same room, the other half of the field."
                : "Look at a magnet and pinch to carry it. Bring two close and watch them pull together head-to-tail and swing into line. Carry the brass compass around and its needle follows the field.",
            preferredDimming: 0.35,
            legend: bench == .electric
                ? ElectromagnetismModule.legendItems
                : MagnetismModule.legendItems,
            isPaused: {
                bench == .electric
                    ? appModel.electromagnetismModel.isPaused
                    : appModel.magnetismModel.isPaused
            },
            togglePause: {
                switch bench {
                case .electric: appModel.electromagnetismModel.isPaused.toggle()
                case .magnetic: appModel.magnetismModel.isPaused.toggle()
                }
            },
            makeControls: {
                AnyView(
                    VStack(alignment: .leading, spacing: DesignTokens.Panel.rowSpacing) {
                        FieldsBenchPicker()
                        switch bench {
                        case .electric:
                            ChargeControlsView()
                                .environment(appModel.electromagnetismModel)
                        case .magnetic:
                            MagnetismControlsView()
                                .environment(appModel.magnetismModel)
                        }
                    }
                )
            },
            makeScene: {
                switch bench {
                case .electric:
                    AnyView(FieldSpaceView().environment(appModel.electromagnetismModel))
                case .magnetic:
                    AnyView(MagnetismSpaceView().environment(appModel.magnetismModel))
                }
            },
            captureReadings: {
                switch bench {
                case .electric: ElectromagnetismModule.readings(appModel: appModel)
                case .magnetic: MagnetismModule.readings(appModel: appModel)
                }
            },
            reset: {
                switch bench {
                case .electric: appModel.electromagnetismModel.reset()
                case .magnetic: appModel.magnetismModel.reset()
                }
            }
        )
    }
}

/// The bench switch, at the top of the Fields controls pod.
struct FieldsBenchPicker: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel
        VStack(alignment: .leading, spacing: 6) {
            Picker("Bench", selection: $appModel.fieldsBench) {
                ForEach(FieldsBench.allCases) { bench in
                    Label(bench.displayName, systemImage: bench.icon).tag(bench)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Field bench")

            Text(appModel.fieldsBench == .electric
                 ? "Charges, their lines and equipotential shells — plus the uniform B that curls a moving charge into a cyclotron circle."
                 : "Bar magnets as ideal dipoles: exact forces, torques and closed looping lines.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

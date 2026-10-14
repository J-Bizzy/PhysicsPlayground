//
//  PhysicsBoard.swift
//  Physics Playground — Shell
//
//  The Physics box: every lab's live numbers on one card standing in the
//  room, with a rail beside it for each quantity the lab lets you set.
//  Opened by the title bar's ƒ button, folded by it again. One
//  implementation serves all six modules through `ModuleDescriptor`:
//  `readings` are the numbers, `adjustables` the
//  rails. Stands high on the left, clear of every flank instrument, and
//  follows the lab placement.
//

import RealityKit
import RenderKit
import SwiftUI

@MainActor
final class PhysicsBoard {
    /// Where the card's anchor stands, in the space's coordinates: high on
    /// the left, above every module's flank instrument and above Electric
    /// Fields' station, in reach. `PhysicsBoardTests` measures both.
    static let home = SIMD3<Float>(-0.62, 1.93, -0.95)
    /// The rails stand in a column beside the card, toward the room's
    /// centre, so the numbers read on the left and the dials on the right;
    /// 0.34 keeps the column's right end left of the title bar's default
    /// place (at 0.42 the second bubble touched the bar).
    static let railColumn = SIMD3<Float>(0.34, 0.04, 0)
    /// Room for a rail's value bubble above it and its name under it,
    /// with air between: at 0.115 the second bubble sat on the first name.
    static let railPitch: Float = 0.16
    /// A rail's length, shorter than the apparatus rails: the card is the
    /// reading, the rail only has to be grabbable.
    static let railLength: Double = 0.20

    let root = Entity()
    /// The card and the rails hang off this, which is what the fold
    /// scales — never `root`, whose scale would stretch the rails' map.
    let unfold = Entity()
    /// The attachment's seat; the view parents the SwiftUI card here.
    let cardSeat = Entity()
    private(set) var rails: [SpatialTrackControl] = []
    var subscription: EventSubscription?

    /// 0 folded, 1 open; eased toward `isOpen` every frame.
    private(set) var openness: Float = 0
    var isOpen = false

    init(module: ModuleDescriptor) {
        root.name = "physics-board"
        root.addChild(unfold)
        unfold.addChild(cardSeat)
        cardSeat.components.set(BillboardComponent())

        let accent = UIColor(module.accent)
        for (index, item) in module.adjustables.enumerated() {
            let center = Self.railColumn - SIMD3<Float>(0, Float(index) * Self.railPitch, 0)
            let rail = SpatialTrackControl(
                name: "physics-\(item.id)",
                center: center,
                normal: [0, 0, 1],
                accent: accent,
                range: item.range,
                layout: TrackLayout(length: Self.railLength),
                read: item.read,
                write: item.write,
                format: { PhysicsFormat.measurement($0, item.unit, decimals: item.decimals) },
                spokenName: item.label)
            unfold.addChild(rail.root)
            rails.append(rail)

            // The quantity's name under its rail, as a well's or a world
            // disc's name sits under it; the rail's own bubble above is the
            // value.
            let plate = HubScene.namePlate(item.label, accent: UIColor(white: 0.95, alpha: 1),
                                           size: PlateStyle.labelSize)
            plate.position = center + SIMD3(0, -0.040, 0.004)
            unfold.addChild(plate)
        }

        unfold.scale = SIMD3(repeating: 0.001)
        root.isEnabled = false
    }

    /// Per frame: place, face the reader, fold or unfold, and keep every
    /// rail's bead on the model's value.
    func update(dt: Double, viewer: SIMD3<Float>?, placement: SIMD3<Float>) {
        root.position = Self.home + placement
        if let viewer, let facing = yaw(facing: viewer, from: root.position) {
            root.orientation = facing
        }
        let target: Float = isOpen ? 1 : 0
        openness = Motion.ease(openness, toward: target, dt: dt, rate: 10)
        let shown = openness > 0.02
        root.isEnabled = shown
        unfold.scale = SIMD3(repeating: max(openness, 0.001))
        guard shown else { return }
        for rail in rails { rail.refresh() }
    }

    // MARK: Rails

    private var activeRail: SpatialTrackControl?

    /// Routes a drag to the rail it started on. True while a rail owns it.
    func handleDrag(entity: Entity, handWorld: SIMD3<Double>) -> Bool {
        if activeRail == nil {
            activeRail = rails.first { $0.owns(entity) }
        }
        guard let activeRail else { return false }
        // Hands arrive in the rail's parent space, which is `unfold`.
        let local = unfold.convert(position: SIMD3<Float>(handWorld), from: nil)
        activeRail.adjust(hand: SIMD3<Double>(local))
        return true
    }

    func endDrag() {
        activeRail?.endAdjust()
        activeRail = nil
    }
}

/// Mounts the Physics box in whatever lab is on screen.
struct PhysicsBoardView: View {
    let module: ModuleDescriptor
    @Environment(AppModel.self) private var appModel
    @State private var board: PhysicsBoard?

    private static let cardID = "physics-card"

    var body: some View {
        RealityView { content, attachments in
            let made = PhysicsBoard(module: module)
            if let card = attachments.entity(for: Self.cardID) {
                // A readout, never an instrument: no hit testing, so it never
                // contends for a pinch aimed at the apparatus behind it.
                stripInput(from: card)
                made.cardSeat.addChild(card)
            }
            content.add(made.root)
            made.isOpen = appModel.physicsBoardOpen
            board = made
            made.subscription = content.subscribe(
                to: SceneEvents.Update.self
            ) { [weak made] event in
                made?.update(
                    dt: event.deltaTime,
                    viewer: appModel.room.headPosition.map { SIMD3<Float>($0) },
                    placement: appModel.labPlacement.offset)
            }
        } update: { _, _ in
            board?.isOpen = appModel.physicsBoardOpen
        } attachments: {
            Attachment(id: Self.cardID) {
                PhysicsCard(module: module)
                    .environment(appModel)
            }
        }
        .onDisappear {
            board?.subscription?.cancel()
            board?.subscription = nil
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    let world = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    _ = board?.handleDrag(entity: value.entity, handWorld: world)
                }
                .onEnded { _ in board?.endDrag() }
        )
    }
}

/// The card: the lab's live numbers, refreshed eight times a second.
struct PhysicsCard: View {
    let module: ModuleDescriptor
    @Environment(AppModel.self) private var appModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 8)) { _ in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "function")
                        .font(.headline)
                        .foregroundStyle(module.accent)
                        .accessibilityHidden(true)
                    Text("Physics")
                        .font(.headline)
                    Spacer(minLength: 12)
                    Text(module.shortTitle ?? module.title)
                        .font(.caption.smallCaps())
                        .foregroundStyle(.secondary)
                }

                let rows = module.readings()
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            Text(row.name)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(row.value)
                                .font(.body.monospacedDigit())
                                .gridColumnAlignment(.trailing)
                                .lineLimit(1)
                            Text(row.unit)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(row.name): \(row.value) \(row.unit)")
                    }
                }

                if let note = module.physicsNote() {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !module.adjustables.isEmpty {
                    Divider().opacity(0.4)
                    Text("On the rails: "
                         + module.adjustables.map(\.label).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minWidth: 240, maxWidth: 340, alignment: .leading)
            .readoutCard(material: .thickMaterial)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Physics box")
    }
}

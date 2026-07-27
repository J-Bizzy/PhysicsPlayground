//
//  SettingsView.swift
//  Physics Playground — Shell
//
//  The settings window, opened from the dock's gear. Every row here is
//  wired: reduce motion actually stills the hub, the volume slider
//  actually scales the sounds, the arc sliders actually move the arc.
//  Anything the app cannot honour yet is absent rather than decorative.
//

import SwiftUI

struct SettingsView: View {
    static let windowID = "settings"

    @Environment(AppModel.self) private var appModel
    @State private var confirmingReset = false
    @State private var exporting: (title: String, text: String)?

    var body: some View {
        @Bindable var settings = appModel.settings

        NavigationStack {
            Form {
                Section("Comfort") {
                    Toggle("Reduce motion", isOn: $settings.reduceMotion)
                    Text("Stills the home screen's idle animation. The system-wide Reduce Motion setting does this automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Audio") {
                    HStack {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.masterVolume, in: 0...1)
                            .onChange(of: settings.masterVolume) {
                                SoundPalette.masterVolume = settings.masterVolume
                            }
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Master volume")
                    Toggle("Ambient lab sound", isOn: $settings.ambientAudio)
                }

                Section("Space") {
                    LabeledContent("Arc distance") {
                        Slider(value: $settings.arcDistance, in: 1.6...2.8) { editing in
                            if !editing { settings.layoutVersion += 1 }
                        }
                        .frame(width: 180)
                    }
                    LabeledContent("Arc height") {
                        Slider(value: $settings.arcHeight, in: 1.1...1.8) { editing in
                            if !editing { settings.layoutVersion += 1 }
                        }
                        .frame(width: 180)
                    }
                    Button("Recenter on where I\u{2019}m facing") {
                        if let ray = appModel.room.lookRay {
                            settings.hubYaw = Float(atan2(-ray.direction.x, -ray.direction.z))
                            settings.layoutVersion += 1
                        }
                    }
                    .disabled(appModel.room.lookRay == nil)
                    Text("Sliders apply when released. Recenter needs the exhibits in your room and head tracking (device only).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Onboarding") {
                    Button("Reset tips") { settings.coachStage = 0 }
                        .disabled(settings.coachStage == 0)
                }

                Section("Data") {
                    Button("Export notebook as CSV") {
                        exporting = ("Notebook — CSV", appModel.notebook.csv)
                    }
                    .disabled(appModel.notebook.entries.isEmpty)
                    Button("Export notebook as Markdown") {
                        exporting = ("Notebook — Markdown", appModel.notebook.markdown)
                    }
                    .disabled(appModel.notebook.entries.isEmpty)
                    Button("Reset all progress", role: .destructive) {
                        confirmingReset = true
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .frame(minWidth: 420, minHeight: 480)
        .confirmationDialog("Reset all progress?",
                            isPresented: $confirmingReset,
                            titleVisibility: .visible) {
            Button("Reset everything", role: .destructive) {
                appModel.experiments.resetAll()
                appModel.notebook.clear()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Every completed experiment, the streak, and the lab notebook. This cannot be undone.")
        }
        .sheet(item: Binding(
            get: { exporting.map { NotebookExport(title: $0.title, text: $0.text) } },
            set: { _ in exporting = nil })) { export in
            NotebookExportView(title: export.title, text: export.text)
        }
        .onAppear { SoundPalette.masterVolume = settings.masterVolume }
    }
}

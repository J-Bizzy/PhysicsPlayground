//
//  OpenSettingsButton.swift
//  Physics Playground — Shell
//
//  The remedy beside a refused permission's sentence: the app's own page
//  in Settings, where World Sensing is. A warning with no remedy is a
//  complaint (`RoomModel.Sensing.detail`), and a remedy that is a path to
//  find by hand is half of one (2026-11-07).
//

import RenderKit
import SwiftUI
import UIKit

struct OpenSettingsButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let settings = URL(string: UIApplication.openSettingsURLString) {
            ControlButton("Open Settings", systemImage: "gear") {
                openURL(settings)
            }
            .accessibilityHint("Opens Physics Playground's page in Settings, where World Sensing is")
        }
    }
}

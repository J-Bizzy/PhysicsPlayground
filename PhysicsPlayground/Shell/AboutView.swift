//
//  AboutView.swift
//  Physics Playground — Shell
//
//  The About window: placeholder copy behind the home's info button.
//  Deliberately small and finished-looking — a stub that reads as a
//  broken feature would cost more than it saves.
//

import SwiftUI

struct AboutView: View {
    static let windowID = "about"

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "atom")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Physics Playground")
                .font(.system(.title2, design: .rounded).weight(.heavy))

            Text("Room-scale physics labs, in your actual room. Real constants, exact solutions, no shortcuts.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider().frame(maxWidth: 220)

            VStack(spacing: 4) {
                Text("Built by Jackson Bizzell")
                    .font(.footnote.weight(.semibold))
                Text(appVersion)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(32)
        .frame(minWidth: 340, minHeight: 300)
    }

    private var appVersion: String {
        let short = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return "Version \(short ?? "1.0") (\(build ?? "1"))"
    }
}

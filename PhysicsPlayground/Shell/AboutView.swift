//
//  AboutView.swift
//  Physics Playground — Shell
//
//  The About window behind the home's info button.
//  `.windowResizability(.contentSize)` pins the window to its content,
//  so the copy stays short and scrolls rather than clips.
//

import SwiftUI

struct AboutView: View {
    static let windowID = "about"

    var body: some View {
        // Wrapped so accessibility text sizes scroll instead of clipping.
        ScrollView {
            VStack(spacing: 14) {
            // The hero wears the two domain accents that name the doors.
            Image(systemName: "atom")
                .font(.system(size: 40))
                .foregroundStyle(LinearGradient(
                    colors: [HubDomain.electricity.color,
                             HubDomain.mechanics.color],
                    startPoint: .topLeading, endPoint: .bottomTrailing))

            Text("Physics Playground")
                .font(DesignTokens.TypeScale.wordmark(.title2))

            Text("Room-scale physics labs. Real constants, exact solutions.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Divider().frame(maxWidth: 220)

            VStack(spacing: 4) {
                Text("Built by Jackson Bizzell")
                    .font(.footnote.weight(.semibold))
                Text(appVersion)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersion: String {
        let short = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return "Version \(short ?? "1.0") (\(build ?? "1"))"
    }
}

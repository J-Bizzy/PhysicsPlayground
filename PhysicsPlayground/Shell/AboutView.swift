//
//  AboutView.swift
//  Physics Playground — Shell
//
//  The About window: the credits behind the home's info button.
//  Deliberately small and finished-looking — a stub that reads as a
//  broken feature would cost more than it saves.
//
//  The copy is SHORT on purpose, and it got shorter on 2026-07-31.
//  `.windowResizability(.contentSize)` pins this window to exactly what
//  the content asks for, so a sentence that wraps one line further does
//  not scroll and does not grow the window — it clips. Which is what it
//  did: 300 pt of declared minimum height plus 64 pt of padding inside
//  a 340 pt window, with a description long enough to wrap to four
//  lines at .callout. Every number here now has slack in it, and the
//  view no longer declares a minimum that fights the window's size.
//

import SwiftUI

struct AboutView: View {
    static let windowID = "about"

    var body: some View {
        // WRAPPED, after the same lesson twice. `.contentSize` pins this
        // window to exactly what the content asks for, so at an
        // accessibility text size the copy does not scroll and does not
        // grow the window — it clips, which is precisely what happened
        // once already and is recorded above. Trimming the copy fixed it
        // for DEFAULT type and left AX sizes broken; Settings and the
        // Notebook are both wrapped for this reason and this was the one
        // window that was not.
        ScrollView {
            VStack(spacing: 14) {
            Image(systemName: "atom")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Physics Playground")
                .font(.system(.title2, design: .rounded).weight(.heavy))

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

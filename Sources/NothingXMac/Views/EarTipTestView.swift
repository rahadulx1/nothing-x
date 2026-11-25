// Ear tip fit test: instructions, a short listening state, then a result per bud.
// Command and result codes from nikiomori/nothing-x-macos.

import NothingKit
import SwiftUI

struct EarTipTestView: View {
    @EnvironmentObject var device: EarbudsController
    @EnvironmentObject var nav: PanelNavigation
    @StateObject private var startedAt = Local(Date())

    /// About how long the buds take to report (they play a ~5 s tone).
    private static let expected: TimeInterval = 5

    var body: some View {
        VStack(spacing: 0) {
            SubpageHeader(title: "Ear Tip Fit Test")

            switch device.state.earTip {
            case .idle:
                intro
            case .running:
                listening
            case .finished(let left, let right):
                results(left, right)
            case .failed:
                PageStack {
                    PanelCard(spacing: 0) {
                        VStack(spacing: 0) {
                            hero(.disconnected).padding(.top, 6)
                            Text("No result").font(.panelTitle).padding(.top, 14)
                            Text("The earbuds didn't report a seal. Make sure both are in your ears and try again.")
                                .font(.callout12).foregroundStyle(Theme.secondaryLabel)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 6)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    buttons(primary: "Try Again")
                }
            }
        }
        .onChange(of: device.state.earTip) { state in
            if state == .running { startedAt.value = Date() }
        }
        .onDisappear { device.resetEarTipTest() }
    }

    private func hero(_ look: Earbud.Look) -> some View {
        GlassGroup(spacing: 16) {
            HStack(spacing: 16) {
                EarbudGlyph(part: .left, look: look, size: 32)
                    .frame(width: 72, height: 72).glassSurface(Circle())
                EarbudGlyph(part: .right, look: look, size: 32)
                    .frame(width: 72, height: 72).glassSurface(Circle())
            }
        }
    }

    private var intro: some View {
        PageStack {
            PanelCard(spacing: 0) {
                VStack(spacing: 0) {
                    hero(.connected).padding(.top, 6)
                    Text("Check your seal").font(.panelTitle).padding(.top, 14)
                    VStack(alignment: .leading, spacing: 8) {
                        step(1, "Put both earbuds in your ears.")
                        step(2, "Stay still and quiet.")
                        step(3, "A short tone plays for about 5 seconds.")
                    }
                    .padding(.top, 14)
                }
                .frame(maxWidth: .infinity)
            }
            Button { device.startEarTipTest() } label: { Label("Start Test", systemImage: "play.fill") }
                .buttonStyle(PanelButtonStyle(primary: true, fullWidth: true))
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(n)").font(.caption11Medium.monospacedDigit()).foregroundStyle(Theme.secondaryLabel)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.controlFill))
            Text(text).font(.callout12)
            Spacer(minLength: 0)
        }
    }

    private var listening: some View {
        PageStack {
            PanelCard(spacing: 0) {
                VStack(spacing: 0) {
                    hero(.connecting).padding(.top, 6)
                    Text("Listening…").font(.panelTitle).padding(.top, 14)
                    TimelineView(.periodic(from: startedAt.value, by: 0.1)) { context in
                        let elapsed = context.date.timeIntervalSince(startedAt.value)
                        let left = Int((Self.expected - elapsed).rounded(.up))
                        VStack(spacing: 12) {
                            // Past the tone's length the buds are working out the result.
                            Text(left > 0 ? "Keep still. About \(left) second\(left == 1 ? "" : "s") left."
                                          : "Checking the seal…")
                                .font(.callout12).foregroundStyle(Theme.secondaryLabel)
                            AccentProgress(fraction: min(1, elapsed / Self.expected))
                        }
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
            }
            Button("Cancel") { device.cancelEarTipTest() }
                .buttonStyle(PanelButtonStyle(fullWidth: true))
        }
    }

    private func results(_ left: EarTipFit, _ right: EarTipFit) -> some View {
        PageStack {
            GlassGroup(spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    ResultCard(side: "Left", mirrored: true, fit: left)
                    ResultCard(side: "Right", mirrored: false, fit: right)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            buttons(primary: "Done")
        }
    }

    /// Test Again (secondary) and a primary button; Done goes back to Quick Settings.
    private func buttons(primary: String) -> some View {
        HStack(spacing: 8) {
            if primary == "Done" {
                Button("Test Again") { device.startEarTipTest() }.buttonStyle(PanelButtonStyle(fullWidth: true))
                Button("Done") { nav.page = .quickSettings }.buttonStyle(PanelButtonStyle(primary: true, fullWidth: true))
            } else {
                Button(primary) { device.startEarTipTest() }.buttonStyle(PanelButtonStyle(primary: true, fullWidth: true))
            }
        }
    }
}

/// Capsule progress bar in the accent color.
private struct AccentProgress: View {
    let fraction: Double
    @Environment(\.accent) private var accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.trackOff)
                Capsule().fill(accent).frame(width: max(6, geo.size.width * fraction))
            }
        }
        .frame(width: 180, height: 6)
        .animation(.linear(duration: 0.1), value: fraction)
        .accessibilityHidden(true)
    }
}

private struct ResultCard: View {
    let side: String
    let mirrored: Bool
    let fit: EarTipFit
    @Environment(\.accent) private var accent

    var body: some View {
        let (title, detail, symbol, look): (String, String, String, Earbud.Look) = {
            switch fit {
            case .good: return ("Good seal", "Nothing to change.", "checkmark.circle.fill", .connected)
            case .poor: return ("Try a different tip", "Sound is leaking. Try one size up.",
                                "exclamationmark.triangle.fill", .low)
            case .notInEar: return ("Not in ear", "Put the earbud in and test again.", "xmark.circle.fill", .disconnected)
            }
        }()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                EarbudGlyph(part: mirrored ? .left : .right, look: look, size: 12, color: Theme.secondaryLabel)
                Text(side).font(.caption11Medium).foregroundStyle(Theme.secondaryLabel)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(fit == .poor ? accent : fit == .good ? Theme.positive : Theme.secondaryLabel)
                Text(title).font(.body13Medium)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(detail).font(.caption11).foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(radius: Theme.tileRadius)
        .accessibilityElement(children: .combine)
    }
}

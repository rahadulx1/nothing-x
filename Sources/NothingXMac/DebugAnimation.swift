// Debug builds only: `NXM_ANIMATE=<dir> swift run NothingXMac` renders a short
// walkthrough of the panel with sample data and writes demo-light.gif and
// demo-dark.gif (used at the top of the README).

#if DEBUG
import AppKit
import ImageIO
import NothingKit
import SwiftUI
import UniformTypeIdentifiers

enum DemoAnimation {
    /// One step of the walkthrough: a page, a tweak to the sample state, how long to hold it.
    struct Step {
        var page: PanelPage
        var hold: Double
        var change: (inout DeviceState) -> Void = { _ in }
    }

    static let steps: [Step] = [
        Step(page: .main, hold: 1.8),
        Step(page: .main, hold: 1.2) { $0.noiseMode = .transparency; $0.ancStrength = nil },
        Step(page: .main, hold: 1.2) { $0.noiseMode = .anc; $0.ancStrength = .adaptive },
        Step(page: .main, hold: 1.2) { $0.bass = BassValue(enabled: true, level: 5) },
        Step(page: .quickSettings, hold: 1.6),
        Step(page: .quickSettings, hold: 1.2) { $0.quick.lowLatency = true },
        Step(page: .dual, hold: 1.6),
        Step(page: .equalizer, hold: 1.4),
        Step(page: .equalizer, hold: 1.4) { $0.eq.custom = CustomEq(bass: 6, mid: 1, treble: -2) },
        Step(page: .controls(.left), hold: 1.6),
        Step(page: .earTip, hold: 1.8),
    ]

    /// Frames blended between steps, and their duration.
    static let fadeFrames = 2
    static let fadeDelay = 0.06

    @MainActor static func run(dir: String) {
        let scratch = UserDefaults(suiteName: "nxm-snapshots")!
        scratch.removePersistentDomain(forName: "nxm-snapshots")
        let settings = AppSettings(defaults: scratch)
        settings.saveEq(name: "Commute", bands: CustomEq(bass: 4, mid: 0, treble: 2))
        settings.saveEq(name: "Late Night", bands: CustomEq(bass: -2, mid: 1, treble: -3))
        settings.menuBarBattery = .both

        for dark in [false, true] {
            let device = EarbudsController()
            device.loadSample()
            var state = device.state
            var frames: [(CGImage, Double)] = []
            var previous: CGImage?

            for step in steps {
                step.change(&state)
                device.setSampleState(state)
                let nav = PanelNavigation()
                nav.page = step.page
                guard let image = DebugSnapshots.bitmap(stage(device, settings, nav, state, dark: dark),
                                                        dark: dark)?.cgImage else { continue }
                if let previous {
                    for i in 1...fadeFrames {
                        let t = CGFloat(i) / CGFloat(fadeFrames + 1)
                        if let blended = blend(previous, image, t) { frames.append((blended, fadeDelay)) }
                    }
                }
                frames.append((image, step.hold))
                previous = image
            }
            let path = "\(dir)/demo-\(dark ? "dark" : "light").gif"
            writeGIF(frames, to: URL(fileURLWithPath: path))
            print("Wrote \(path) (\(frames.count) frames)")
        }
    }

    /// A fixed-size stage: a menu bar strip with the status item, the panel hanging below it.
    @MainActor private static func stage(_ device: EarbudsController, _ settings: AppSettings,
                                         _ nav: PanelNavigation, _ state: DeviceState, dark: Bool) -> some View {
        let text = settings.menuBarBattery.text(for: state.battery) ?? ""
        return VStack(spacing: 10) {
            HStack(spacing: 14) {
                Spacer()
                HStack(spacing: 4) {
                    Image(nsImage: Earbud.templateImage(.connected)).renderingMode(.template)
                    Text(text).font(.system(size: 12, weight: .medium).monospacedDigit())
                }
                .padding(.horizontal, 6)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.12)))
                Image(systemName: "wifi").font(.system(size: 13, weight: .medium))
                Image(systemName: "switch.2").font(.system(size: 13, weight: .medium))
                Text("Thu 9:41").font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background(Color.primary.opacity(dark ? 0.25 : 0.06))

            HStack {
                Spacer()
                PanelView()
                    .environmentObject(device)
                    .environmentObject(settings)
                    .environmentObject(nav)
                    .fixedSize()
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    // No soft shadow or gradients: GIF's 256 colours would band them.
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.18)))
                    .padding(.trailing, 40)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 440, height: 660, alignment: .top)
        .background(dark ? Color(white: 0.13) : Color(white: 0.93))
    }

    private static func blend(_ a: CGImage, _ b: CGImage, _ t: CGFloat) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: a.width, height: a.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: a.width, height: a.height)
        ctx.draw(a, in: rect)
        ctx.setAlpha(t)
        ctx.draw(b, in: rect)
        return ctx.makeImage()
    }

    private static func writeGIF(_ frames: [(CGImage, Double)], to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString,
                                                         frames.count, nil) else { return }
        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        for (image, delay) in frames {
            CGImageDestinationAddImage(dest, image, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay,
                                                kCGImagePropertyGIFUnclampedDelayTime: delay],
            ] as CFDictionary)
        }
        CGImageDestinationFinalize(dest)
    }
}
#endif

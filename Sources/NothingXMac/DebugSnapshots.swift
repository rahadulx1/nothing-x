// Debug builds only: `NXM_SNAPSHOT=<dir> swift run NothingXMac` renders each
// panel page with sample data to PNGs and exits. Handy for checking layout
// without earbuds or screen-recording permission.

#if DEBUG
import AppKit
import NothingKit
import SwiftUI

extension EarbudsController {
    func loadSample() {
        var s = DeviceState()
        s.connected = true
        s.name = "CMF Buds 2 Plus"
        s.address = "aa-bb-cc-dd-ee-ff"
        s.capabilities = Capabilities.forDeviceName("CMF Buds 2 Plus")
        s.battery.left = BatteryLevel(level: 82, charging: false)
        s.battery.right = BatteryLevel(level: 79, charging: true)
        s.battery.case = BatteryLevel(level: 54, charging: false)
        s.noiseMode = .anc
        s.ancStrength = .mid
        s.bass = BassValue(enabled: true, level: 3)
        s.quick.inEar = true
        s.quick.lowLatency = false
        s.quick.personalSound = false
        s.quick.spatial = .fixed
        s.quick.firmware = "1.0.3.124"
        s.quick.serial = "SH10000000000000"
        s.eq.preset = 6
        s.eq.custom = CustomEq(bass: 4, mid: -2, treble: 3)
        s.dual.enabled = true
        s.dual.devices = [
            DualDevice(mac: "AA", name: "MacBook Pro", isSelf: true, isConnected: true),
            DualDevice(mac: "BB", name: "iPhone", isSelf: false, isConnected: true),
            DualDevice(mac: "CC", name: "iPad", isSelf: false, isConnected: false),
            DualDevice(mac: "DD", name: "Work PC", isSelf: false, isConnected: false),
        ]
        s.gestures.values = [.left: ["doubleTap": 2, "tripleTap": 9, "tapHold": 22, "doubleTapHold": 18],
                             .right: ["doubleTap": 2, "tripleTap": 8, "tapHold": 11, "doubleTapHold": 19]]
        s.earTip = .finished(left: .good, right: .poor)
        setSampleState(s)
    }

    func loadConnectingSample() {
        var s = DeviceState()
        s.connecting = "CMF Buds 2 Plus"
        setSampleState(s)
    }

    func loadUnrecognisedSample() {
        var s = DeviceState()
        s.connected = true
        s.name = "Nothing earbuds"
        s.recognized = false
        s.capabilities = Capabilities.forDeviceName("Nothing earbuds")
        s.battery.left = BatteryLevel(level: 64, charging: false)
        s.battery.right = BatteryLevel(level: 61, charging: false)
        s.battery.case = BatteryLevel(level: 40, charging: false)
        s.noiseMode = .off
        s.bass = BassValue(enabled: false, level: 1)
        setSampleState(s)
    }
}

enum DebugSnapshots {
    @MainActor static func runIfRequested() {
        // NXM_LOGIN=off: drop this bundle's Open at Login registration (dev builds).
        if ProcessInfo.processInfo.environment["NXM_LOGIN"] == "off" {
            LoginItem.setEnabled(false)
            print("Open at Login now: \(LoginItem.isEnabled ? "on" : "off")")
            exit(0)
        }
        if let dir = ProcessInfo.processInfo.environment["NXM_ANIMATE"] {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            LiquidGlass.nativeAllowed = false
            DemoAnimation.run(dir: dir)
            exit(0)
        }
        guard let dir = ProcessInfo.processInfo.environment["NXM_SNAPSHOT"] else { return }
        LiquidGlass.nativeAllowed = false
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        let device = EarbudsController()
        device.loadSample()
        let offline = EarbudsController()
        offline.setSamplePaired([.init(name: "CMF Buds 2 Plus", address: "aa-bb-cc-dd-ee-ff")])
        let connecting = EarbudsController()
        connecting.loadConnectingSample()
        let unrecognised = EarbudsController()
        unrecognised.loadUnrecognisedSample()
        // Throwaway defaults so sample presets never reach the real settings.
        let scratch = UserDefaults(suiteName: "nxm-snapshots")!
        scratch.removePersistentDomain(forName: "nxm-snapshots")
        let settings = AppSettings(defaults: scratch)
        do {
            settings.saveEq(name: "Commute", bands: CustomEq(bass: 4, mid: 0, treble: 2))
            settings.saveEq(name: "Late Night", bands: CustomEq(bass: -2, mid: 1, treble: -3))
        }
        let pages: [(String, PanelPage)] = [
            ("main", .main), ("quick", .quickSettings), ("spatial", .spatial), ("dual", .dual),
            ("eq", .equalizer), ("controls", .controls(.left)), ("eartip", .earTip), ("settings", .settings),
        ]

        func panel(_ page: PanelPage, _ controller: EarbudsController) -> some View {
            let nav = PanelNavigation()
            nav.page = page
            return PanelView()
                .environmentObject(controller)
                .environmentObject(settings)
                .environmentObject(nav)
                .fixedSize()
        }

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            for (name, page) in pages {
                render(panel(page, device).background(Color(nsColor: .windowBackgroundColor)),
                       dark: dark, to: "\(dir)/\(name)-\(suffix).png")
            }
            render(panel(.main, offline).background(Color(nsColor: .windowBackgroundColor)),
                   dark: dark, to: "\(dir)/disconnected-\(suffix).png")
            render(panel(.main, connecting).background(Color(nsColor: .windowBackgroundColor)),
                   dark: dark, to: "\(dir)/connecting-\(suffix).png")
            render(panel(.main, unrecognised).background(Color(nsColor: .windowBackgroundColor)),
                   dark: dark, to: "\(dir)/unrecognised-\(suffix).png")

            // README hero: four pages side by side, each as a floating panel.
            let hero = HStack(alignment: .top, spacing: 28) {
                ForEach(Array([PanelPage.main, .quickSettings, .equalizer, .controls(.left)].enumerated()), id: \.offset) { _, page in
                    panel(page, device)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
                        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
                }
            }
            .padding(40)
            .background(LinearGradient(
                colors: dark ? [Color(white: 0.10), Color(white: 0.20)] : [Color(white: 0.86), Color(white: 0.97)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            render(hero, dark: dark, to: "\(dir)/overview-\(suffix).png")
        }
        exit(0)
    }

    /// Draws a view through a real (offscreen) window so native AppKit controls render too.
    @MainActor private static func render<V: View>(_ view: V, dark: Bool, to path: String) {
        if let rep = bitmap(view, dark: dark), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    @MainActor static func bitmap<V: View>(_ view: V, dark: Bool) -> NSBitmapImageRep? {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = hosting.appearance
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        return rep
    }
}

#endif

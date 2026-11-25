// Quick Settings page: Control Center style glass tiles for in-ear detection,
// low latency, Personal Sound, spatial audio, dual connection and Find Buds,
// then the ear tip test and device info. Spatial Audio and Dual Connection
// have their own sub-pages.

import NothingKit
import SwiftUI

struct QuickSettingsView: View {
    @EnvironmentObject var device: EarbudsController
    @EnvironmentObject var nav: PanelNavigation
    @StateObject private var findOpen = Local(false)

    private var state: DeviceState { device.state }
    private var caps: Capabilities { state.capabilities }

    var body: some View {
        VStack(spacing: 0) {
            SubpageHeader(title: "Quick Settings", back: .main)

            PageStack {
                GlassGroup(spacing: 8) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                              spacing: 8) {
                        if caps.inEar { toggleTile(.inEar, "In-Ear Detection", "ear", state.quick.inEar) }
                        if caps.lowLatency {
                            toggleTile(.lowLatency, "Low Latency", "gamecontroller.fill", state.quick.lowLatency)
                        }
                        if caps.personalSound != nil {
                            toggleTile(.personalSound, "Personal Sound", "person.wave.2.fill", state.quick.personalSound)
                        }
                        if !caps.spatialModes.isEmpty { spatialTile }
                        if caps.dualConnection { dualTile }
                        findTile
                    }
                }

                if caps.ring == .buds && (findOpen.value || state.quick.ringing != nil) {
                    findPanel.transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }

                if caps.earTipTest {
                    PanelCard(padding: 6, spacing: 0) {
                        NavigationRow(symbol: "smallcircle.filled.circle", title: "Ear Tip Fit Test",
                                      detail: "Check your seal") { nav.page = .earTip }
                    }
                }

                DeviceInfo()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: findOpen.value)
    }

    // MARK: Tiles

    private func toggleTile(_ setting: QuickSetting, _ name: String, _ symbol: String, _ value: Bool?) -> some View {
        QuickTile(symbol: symbol, name: name,
                  detail: value.map { $0 ? "On" : "Off" } ?? "—",
                  on: value == true, pending: state.quick.pending.contains(setting)) {
            guard let value, !state.quick.pending.contains(setting) else { return }
            device.setToggle(setting, !value)
        }
    }

    /// The body switches Off ↔ the last mode; the chevron opens the mode list.
    private var spatialTile: some View {
        let current = state.quick.spatial
        let modes = caps.spatialModes.filter { $0 != .off }
        return QuickTile(symbol: "dot.radiowaves.left.and.right", name: "Spatial Audio",
                         detail: current?.label ?? "—",
                         on: current != nil && current != .off,
                         pending: state.quick.pending.contains(.spatial),
                         onChevron: modes.count > 1 ? { nav.page = .spatial } : nil) {
            guard let current, !state.quick.pending.contains(.spatial), let first = modes.first else { return }
            device.setSpatialAudio(current == .off ? (SpatialAudioView.lastMode ?? first) : .off)
        }
    }

    private var dualTile: some View {
        let dual = state.dual
        let detail: String = {
            guard let enabled = dual.enabled else { return "—" }
            if dual.pending && caps.dualRestarts { return "Restarting buds…" }
            return enabled ? "\(dual.connectedCount) connected" : "Off"
        }()
        return QuickTile(symbol: "laptopcomputer.and.iphone", name: "Dual Connection", detail: detail,
                         on: dual.enabled == true, pending: dual.pending,
                         onChevron: dual.enabled == true ? { nav.page = .dual } : nil) {
            guard let enabled = dual.enabled, !dual.pending else { return }
            device.setDualConnection(!enabled)
        }
    }

    private var findTile: some View {
        let ringing = state.quick.ringing
        let detail: String = {
            guard let ringing else { return "Play sound" }
            return ringing == .all ? "Playing… tap to stop" : "Playing \(ringing.rawValue)"
        }()
        return QuickTile(symbol: ringing != nil ? "speaker.wave.3.fill" : "magnifyingglass",
                         name: "Find Buds", detail: detail, on: ringing != nil) {
            if caps.ring == .buds {
                findOpen.value.toggle()
            } else {
                device.ring(.all, on: ringing == nil)
            }
        }
    }

    private var findPanel: some View {
        PanelCard(spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.orange)
                Text("The sound is loud. Take the earbuds out first.")
                    .font(.caption11).foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                ForEach([RingTarget.left, .right], id: \.self) { side in
                    let active = state.quick.ringing == side
                    Button { device.ring(side, on: !active) } label: {
                        Label(active ? "Stop" : side == .left ? "Play Left" : "Play Right",
                              systemImage: active ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(PanelButtonStyle(primary: active, fullWidth: true))
                }
            }
        }
    }
}

/// Control Center style glass tile: icon disc, name and state. Tiles with a
/// sub-page show a chevron in the corner that opens it; the body toggles.
struct QuickTile: View {
    let symbol: String
    let name: String
    let detail: String
    var on = false
    var pending = false
    var onChevron: (() -> Void)?
    let action: () -> Void
    @Environment(\.accentFill) private var accentFill
    @StateObject private var hovering = Local(false)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
        ZStack(alignment: .topTrailing) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack {
                        Circle().fill(on ? accentFill : Theme.controlFillStrong)
                            .shadow(color: on ? accentFill.opacity(0.45) : .clear, radius: 5, y: 2)
                        Image(systemName: symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(on ? Color.white : Theme.label)
                    }
                    .frame(width: 30, height: 30)
                    Spacer(minLength: 8)
                    Text(name).font(.system(size: 12, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(detail).font(.caption11).foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 84, maxHeight: 84, alignment: .leading)
                .background(shape.fill(hovering.value ? Theme.controlFill : .clear))
                .contentShape(shape)
                .glassSurface(shape, interactive: true)
                .opacity(pending ? 0.55 : 1)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("\(name), \(detail)")
            .animation(.easeOut(duration: 0.2), value: on)

            if pending {
                PendingSpinner(size: 12).padding(12)
            } else if let onChevron {
                Button(action: onChevron) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.secondaryLabel)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Theme.controlFill))
                        .contentShape(Circle())
                }
                .buttonStyle(PressScaleStyle())
                .padding(8)
                .help("More \(name) options")
                .accessibilityLabel("\(name) options")
            }
        }
        .onHover { hovering.value = $0 }
    }
}

// MARK: - Spatial Audio

struct SpatialAudioView: View {
    /// The last non-Off mode, so the tile can switch back to it.
    static var lastMode: SpatialMode?

    @EnvironmentObject var device: EarbudsController

    var body: some View {
        let current = device.state.quick.spatial
        let pending = device.state.quick.pending.contains(.spatial)
        let modes = device.state.capabilities.spatialModes
        VStack(spacing: 0) {
            SubpageHeader(title: "Spatial Audio") {
                Toggle("Spatial Audio", isOn: Binding(
                    get: { current != nil && current != .off },
                    set: { on in
                        let fallback = Self.lastMode ?? modes.first { $0 != .off }
                        if let target = on ? fallback : .off { device.setSpatialAudio(target) }
                    }))
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    .disabled(pending || current == nil)
            }
            PageStack {
                PanelCard(padding: 6, spacing: 2) {
                    ForEach(modes) { mode in
                        SelectRow(label: mode.label, selected: current == mode,
                                  pending: pending && current == mode) {
                            guard !pending else { return }
                            device.setSpatialAudio(mode)
                        }
                    }
                }
                FooterNote("Spatial Audio places sound around you for a wider, more immersive stage.")
                    .padding(.horizontal, 4)
            }
        }
        .onChange(of: current) { mode in
            if let mode, mode != .off { Self.lastMode = mode }
        }
    }
}

// MARK: - Dual Connection

struct DualConnectionView: View {
    @EnvironmentObject var device: EarbudsController

    var body: some View {
        let dual = device.state.dual
        let full = dual.connectedCount >= dual.maxConnected
        VStack(spacing: 0) {
            SubpageHeader(title: "Dual Connection") {
                if dual.pending { PendingSpinner(size: 12) }
                Toggle("Dual Connection", isOn: Binding(get: { dual.enabled == true },
                                                        set: { device.setDualConnection($0) }))
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    .disabled(dual.pending || dual.enabled == nil)
            }

            PageStack {
                if dual.enabled == true {
                    PanelCard(padding: 6, spacing: 0) {
                        SectionCaption("Devices", trailing: "\(dual.connectedCount) of \(dual.maxConnected) connected",
                                       symbol: "laptopcomputer.and.iphone")
                            .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 4)
                        ForEach(dual.devices) { d in
                            DualDeviceRow(device: d, full: full)
                        }
                        if dual.devices.isEmpty {
                            HStack(spacing: 8) {
                                PendingSpinner(size: 11)
                                Text("Loading remembered devices…").font(.caption11)
                                    .foregroundStyle(Theme.secondaryLabel)
                            }
                            .padding(10)
                        }
                    }
                    TipBox(text: "Up to two devices at once. Disconnect one to connect another.")
                } else {
                    TipBox(symbol: "laptopcomputer.and.iphone",
                           text: "Turn on Dual Connection to keep the earbuds connected to two devices at once.")
                }
            }
        }
    }
}

private struct DualDeviceRow: View {
    let device: DualDevice
    let full: Bool
    @EnvironmentObject var controller: EarbudsController

    var body: some View {
        let dual = controller.state.dual
        let busy = dual.busyMac == device.mac
        let otherBusy = dual.busyMac != nil && !busy
        HStack(spacing: 10) {
            RowIcon(symbol: Self.symbol(for: device), color: Theme.label)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.isSelf ? "This Mac" : device.name.isEmpty ? "Unknown device" : device.name)
                    .font(.body13).lineLimit(1)
                HStack(spacing: 4) {
                    if device.isConnected && !busy { Circle().fill(Theme.positive).frame(width: 6, height: 6) }
                    Text(status(busy: busy)).font(.caption11).foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if busy {
                PendingSpinner(size: 12)
            } else if !device.isSelf {
                // This Mac can't drop itself: that would cut the control channel too.
                Button(device.isConnected ? "Disconnect" : "Connect") {
                    controller.setDualDevice(device.mac, connect: !device.isConnected)
                }
                .buttonStyle(PanelButtonStyle())
                .disabled(otherBusy || (!device.isConnected && full))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 46)
    }

    private func status(busy: Bool) -> String {
        if busy { return device.isConnected ? "Disconnecting…" : "Connecting…" }
        if device.isSelf { return device.name.isEmpty ? "Connected" : device.name }
        return device.isConnected ? "Connected" : "Remembered"
    }

    /// The earbuds only report names, so guess an icon from the name.
    static func symbol(for d: DualDevice) -> String {
        if d.isSelf { return "laptopcomputer" }
        let rules: [(String, String)] = [
            (#"iphone|phone|pixel|galaxy|oneplus|redmi|xiaomi|android"#, "iphone"),
            (#"ipad|tablet|\btab\b"#, "ipad"),
            (#"watch"#, "applewatch"),
            (#"\btv\b|television|bravia"#, "tv"),
            (#"imac|desktop|\bpc\b|studio"#, "desktopcomputer"),
            (#"mac|book|laptop|thinkpad|surface|notebook"#, "laptopcomputer"),
        ]
        for (pattern, symbol) in rules
        where d.name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return symbol
        }
        return "antenna.radiowaves.left.and.right"
    }
}

// MARK: - Device info

private struct DeviceInfo: View {
    @EnvironmentObject var device: EarbudsController
    @StateObject private var copied = Local<String?>(nil)

    var body: some View {
        let state = device.state
        PanelCard(spacing: 8) {
            SectionCaption("Device", symbol: "info.circle")
            row("Firmware", state.quick.firmware)
            if let serial = state.quick.serial { row("Serial", serial) }
            if let address = state.address, !address.isEmpty {
                row("Bluetooth", address.uppercased().replacingOccurrences(of: "-", with: ":"))
            }
        }
    }

    /// Click a value to copy it.
    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).font(.caption11).foregroundStyle(Theme.secondaryLabel)
            Spacer()
            if copied.value == label {
                Text("Copied").font(.caption11Medium).foregroundStyle(Theme.positive)
                    .transition(.opacity)
            }
            Text(value ?? "—")
                .font(.caption11Medium.monospacedDigit())
                .textSelection(.enabled)
                .onTapGesture {
                    guard let value else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    withAnimation { copied.value = label }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { if copied.value == label { copied.value = nil } }
                    }
                }
                .help(value == nil ? "" : "Click to copy")
        }
    }
}

// Main page: header, battery ring gauges, noise control (with intensity),
// Bass Enhance and shortcuts to the other pages. Before a connection it shows
// the "not connected" guide, or a skeleton while the control channel is opening.

import NothingKit
import SwiftUI

struct MainView: View {
    @EnvironmentObject var device: EarbudsController
    @EnvironmentObject var nav: PanelNavigation

    private var state: DeviceState { device.state }

    var body: some View {
        VStack(spacing: 0) {
            MainHeader()
            VStack(spacing: Theme.spacing) {
                if state.connected {
                    if !state.recognized {
                        TipBox(symbol: "exclamationmark.triangle.fill", bold: "Limited support.",
                               text: "This model isn't recognised yet, so some controls may not work.")
                    }
                    BatteryCells()
                    NoiseControlSection()
                    if state.capabilities.bassSteps > 0, state.bass != nil {
                        BassSection()
                    }
                    MoreSection()
                } else if state.connecting != nil {
                    ConnectingSkeleton()
                } else {
                    NotConnectedView()
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 4)
            .padding(.bottom, Theme.margin)
        }
    }
}

// MARK: - Header

private struct MainHeader: View {
    @EnvironmentObject var device: EarbudsController
    @EnvironmentObject var nav: PanelNavigation

    var body: some View {
        let state = device.state
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.panelTitle).lineLimit(1)
                HStack(spacing: 5) {
                    if state.connected {
                        Circle().fill(state.recognized ? Theme.positive : Color.orange)
                            .frame(width: 7, height: 7)
                            .shadow(color: (state.recognized ? Theme.positive : .orange).opacity(0.6), radius: 3)
                    } else if state.connecting != nil {
                        PendingSpinner(size: 9)
                    } else {
                        Circle().fill(Theme.tertiary).frame(width: 7, height: 7)
                    }
                    Text(status).font(.caption11).foregroundStyle(Theme.secondaryLabel)
                }
            }
            Spacer(minLength: 0)
            GlassGroup(spacing: 6) {
                HStack(spacing: 6) {
                    if state.connected {
                        GlassIconButton(symbol: "square.grid.2x2", help: "Quick Settings (⌘K)") {
                            nav.page = .quickSettings
                        }
                    }
                    GlassIconButton(symbol: "gearshape", help: "Settings (⌘,)") { nav.page = .settings }
                }
            }
        }
        .padding(.horizontal, Theme.margin + 2)
        .padding(.top, Theme.margin)
        .padding(.bottom, 8)
        .frame(minHeight: 56)
    }

    private var title: String {
        let state = device.state
        if state.connected { return state.name ?? "Earbuds" }
        return state.connecting ?? "Nothing X Mac"
    }

    private var status: String {
        let state = device.state
        if state.connected { return state.recognized ? "Connected" : "Unrecognised model" }
        return state.connecting != nil ? "Connecting…" : "Not connected"
    }
}

// MARK: - Battery

private struct BatteryCells: View {
    @EnvironmentObject var device: EarbudsController
    @EnvironmentObject var nav: PanelNavigation

    var body: some View {
        let battery = device.state.battery
        let caps = device.state.capabilities
        let gestures = caps.gestures != nil
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                if caps.ring == .buds || battery.left != nil || battery.right != nil {
                    BatteryCell(icon: .bud(mirrored: true), label: "Left", info: battery.left,
                                action: gestures ? { nav.page = .controls(.left) } : nil)
                    BatteryCell(icon: .bud(mirrored: false), label: "Right", info: battery.right,
                                action: gestures ? { nav.page = .controls(.right) } : nil)
                    BatteryCell(icon: .symbol(Earbud.Part.chargingCase.symbol), label: "Case", info: battery.case, action: nil)
                } else {
                    BatteryCell(icon: .symbol("headphones"), label: "Battery", info: battery.stereo, action: nil)
                }
            }
        }
    }
}

enum CellIcon {
    case bud(mirrored: Bool)
    case symbol(String)
}

/// One battery tile: a ring gauge with the part's icon inside, then the level
/// in SF Pro. Low (≤20%, not charging) turns accent; charging turns green.
struct BatteryCell: View {
    let icon: CellIcon
    let label: String
    let info: BatteryLevel?
    let action: (() -> Void)?
    var skeleton = false
    @Environment(\.accent) private var accent
    @StateObject private var hovering = Local(false)

    var body: some View {
        let low = info.map { !$0.charging && $0.level <= 20 } ?? false
        let charging = info?.charging == true
        let ringColor = charging ? Theme.positive : low ? accent : Theme.label
        let content = VStack(spacing: 8) {
            BatteryRing(fraction: info.map { Double($0.level) / 100 } ?? 0, color: ringColor, charging: charging) {
                switch icon {
                case .bud(let mirrored):
                    EarbudGlyph(part: mirrored ? .left : .right, look: skeleton ? .disconnected : .connected,
                                size: 21)
                case .symbol(let name):
                    Image(systemName: name).font(.system(size: 15)).foregroundStyle(Theme.label)
                }
            }
            VStack(spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(info.map { "\($0.level)" } ?? "--")
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                        .foregroundStyle(info == nil ? Theme.tertiary : low ? accent : Theme.label)
                    Text("%").font(.caption11Medium).foregroundStyle(Theme.secondaryLabel)
                }
                Text(label).font(.caption11).foregroundStyle(Theme.secondaryLabel)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)

        Button { action?() } label: {
            content
                .background(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .fill(action != nil && hovering.value ? Theme.controlFill : .clear))
                .contentShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
                .glassSurface(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous),
                              interactive: action != nil)
        }
        .buttonStyle(PressScaleStyle())
        .allowsHitTesting(action != nil)
        .help(action != nil ? "\(label) earbud controls" : "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(info.map { "\($0.level) percent\($0.charging ? ", charging" : "")" } ?? "unknown")")
        .accessibilityAddTraits(action != nil ? .isButton : [])
        .onHover { hovering.value = $0 }
        .animation(.easeOut(duration: 0.3), value: info)
    }
}

/// Circular level gauge, like the Batteries widget.
struct BatteryRing<Icon: View>: View {
    let fraction: Double
    let color: Color
    var charging = false
    var size: CGFloat = 46
    var lineWidth: CGFloat = 4.5
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        ZStack {
            Circle().stroke(Theme.trackOff, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            icon()
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            if charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Theme.positive))
                    .offset(x: 4, y: -3)
                    .accessibilityLabel("Charging")
            }
        }
    }
}

// MARK: - Noise control

private struct NoiseControlSection: View {
    @EnvironmentObject var device: EarbudsController

    var body: some View {
        let state = device.state
        let caps = state.capabilities
        var modes: [SegmentItem<NoiseMode>] = [SegmentItem(id: .anc, label: "Noise Cancel", symbol: "person.wave.2.fill")]
        if caps.transparency {
            modes.append(SegmentItem(id: .transparency, label: "Transparency", symbol: "ear.and.waveform"))
        }
        modes.append(SegmentItem(id: .off, label: "Off", symbol: "speaker.slash"))
        let strengths = caps.adaptive ? caps.strengths + [.adaptive] : caps.strengths

        return PanelCard {
            SectionCaption("Noise Control", symbol: "waveform")
            GlassSegmented(items: modes, selection: state.noiseMode, pending: state.noisePending) {
                device.setNoiseMode($0)
            }
            if state.noiseMode == .anc, !strengths.isEmpty {
                HStack(spacing: 10) {
                    Text("Intensity").font(.caption11Medium).foregroundStyle(Theme.secondaryLabel)
                    GlassSegmented(items: strengths.map { SegmentItem(id: $0, label: Self.label($0)) },
                                   selection: state.ancStrength, pending: state.noisePending,
                                   height: 28) { device.setAncStrength($0) }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.noiseMode == .anc)
    }

    static func label(_ strength: AncStrength) -> String {
        switch strength {
        case .low: return "Low"
        case .mid: return "Mid"
        case .high: return "High"
        case .adaptive: return "Adaptive"
        }
    }
}

// MARK: - Bass Enhance

private struct BassSection: View {
    @EnvironmentObject var device: EarbudsController

    var body: some View {
        let bass = device.state.bass ?? BassValue(enabled: false, level: 1)
        let pending = device.state.bassPending
        let levels = device.state.capabilities.bassLevels
        let index = levels.firstIndex(of: bass.level) ?? 0

        PanelCard {
            HStack(spacing: 10) {
                RowIcon(symbol: "speaker.wave.3.fill", color: Theme.label)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bass Enhance").font(.body13Medium)
                    Text(bass.enabled ? "Level \(index + 1) of \(levels.count)" : "Off")
                        .font(.caption11.monospacedDigit()).foregroundStyle(Theme.secondaryLabel)
                }
                if pending { PendingSpinner(size: 11) }
                Spacer()
                Toggle("Bass Enhance", isOn: Binding(get: { bass.enabled },
                                                     set: { device.setBass(enabled: $0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            SteppedSlider(steps: levels.count, index: index) { i in
                device.setBass(enabled: true, level: levels[i])
            }
            .opacity(bass.enabled ? 1 : 0.4)
        }
        .allowsHitTesting(!pending)
    }
}

/// Slider with detents: 6 pt track, accent fill, a glassy capsule knob, a tick per step.
struct SteppedSlider: View {
    let steps: Int
    let index: Int
    let onChange: (Int) -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        GeometryReader { geo in
            let knobW: CGFloat = 26, knobH: CGFloat = 18
            let usable = geo.size.width - knobW
            let step = steps > 1 ? usable / CGFloat(steps - 1) : 0
            let x = knobW / 2 + CGFloat(index) * step
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.trackOff).frame(height: 6)
                Capsule().fill(accent).frame(width: x, height: 6)
                ForEach(0..<max(steps, 0), id: \.self) { i in
                    Circle().fill(i <= index ? Color.white.opacity(0.9) : Theme.tertiary)
                        .frame(width: 3, height: 3)
                        .position(x: knobW / 2 + CGFloat(i) * step, y: geo.size.height / 2)
                }
                SliderKnob(width: knobW, height: knobH)
                    .position(x: x, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                guard steps > 1 else { return }
                let i = Int(((value.location.x - knobW / 2) / step).rounded())
                let clamped = min(max(i, 0), steps - 1)
                if clamped != index { onChange(clamped) }
            })
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: index)
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityLabel("Level")
        .accessibilityValue("\(index + 1) of \(steps)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if index < steps - 1 { onChange(index + 1) }
            case .decrement: if index > 0 { onChange(index - 1) }
            @unknown default: break
            }
        }
    }
}

/// The capsule thumb used by the panel's sliders.
struct SliderKnob: View {
    var width: CGFloat = 26
    var height: CGFloat = 18

    var body: some View {
        Capsule()
            .fill(Color.white)
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 2.5, y: 1)
            .frame(width: width, height: height)
    }
}

// MARK: - More

/// Shortcuts to the Equalizer, gesture Controls and Quick Settings pages.
private struct MoreSection: View {
    @EnvironmentObject var device: EarbudsController
    @EnvironmentObject var nav: PanelNavigation

    var body: some View {
        let state = device.state
        let caps = state.capabilities
        PanelCard(padding: 6, spacing: 0) {
            if !caps.eq.presets.isEmpty {
                NavigationRow(symbol: "slider.vertical.3", title: "Equalizer",
                              detail: caps.eq.presets.first { $0.id == state.eq.preset }?.label,
                              shortcut: "⌘E") { nav.page = .equalizer }
            }
            if caps.gestures != nil {
                NavigationRow(symbol: "hand.tap", title: "Controls", detail: "Tap gestures") {
                    nav.page = .controls(.left)
                }
            }
            NavigationRow(symbol: "square.grid.2x2", title: "Quick Settings", detail: quickDetail,
                          shortcut: "⌘K") { nav.page = .quickSettings }
        }
    }

    private var quickDetail: String? {
        let state = device.state
        var on: [String] = []
        if state.quick.lowLatency == true { on.append("Low Latency") }
        if let spatial = state.quick.spatial, spatial != .off { on.append("Spatial") }
        if state.dual.enabled == true { on.append("Dual") }
        return on.isEmpty ? nil : on.joined(separator: " · ")
    }
}

// MARK: - Before a connection

private struct ConnectingSkeleton: View {
    var body: some View {
        VStack(spacing: Theme.spacing) {
            HStack(spacing: 8) {
                BatteryCell(icon: .bud(mirrored: true), label: "Left", info: nil, action: nil, skeleton: true)
                BatteryCell(icon: .bud(mirrored: false), label: "Right", info: nil, action: nil, skeleton: true)
                BatteryCell(icon: .symbol(Earbud.Part.chargingCase.symbol), label: "Case", info: nil, action: nil, skeleton: true)
            }
            PanelCard {
                SectionCaption("Noise Control", symbol: "waveform")
                GlassSegmented(items: [SegmentItem(id: 0, label: "Noise Cancel", symbol: "person.wave.2.fill"),
                                       SegmentItem(id: 1, label: "Transparency", symbol: "ear.and.waveform"),
                                       SegmentItem(id: 2, label: "Off", symbol: "speaker.slash")],
                               selection: nil) { _ in }
            }
            .opacity(0.45)
            TipBox(symbol: "iphone.gen3", bold: "Taking a while?",
                   text: "Close the Nothing X or CMF app on your phone. The earbuds accept one controller at a time.")
        }
        .allowsHitTesting(false)
    }
}

private struct NotConnectedView: View {
    @EnvironmentObject var device: EarbudsController

    var body: some View {
        VStack(spacing: Theme.spacing) {
            PanelCard(spacing: 0) {
                VStack(spacing: 0) {
                    EarbudGlyph(part: .pair, look: .disconnected, size: 34)
                        .frame(width: 76, height: 76)
                        .glassSurface(Circle())
                        .padding(.top, 6)
                    Text("No earbuds connected")
                        .font(.panelTitle)
                        .padding(.top, 14)
                    Text("Pair your earbuds in System Settings › Bluetooth. They show up here once connected.")
                        .font(.callout12)
                        .foregroundStyle(Theme.secondaryLabel)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                        .padding(.top, 6)
                    Button {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Open Bluetooth Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(PanelButtonStyle(primary: true, fullWidth: true))
                    .padding(.top, 16)
                }
                .frame(maxWidth: .infinity)
            }

            if !device.paired.isEmpty {
                PanelCard(padding: 6, spacing: 2) {
                    SectionCaption("Paired", symbol: "link")
                        .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 4)
                    ForEach(device.paired) { buds in
                        PairedRow(buds: buds)
                    }
                }
            }

            TipBox(symbol: "iphone.gen3", bold: "Phone app open?",
                   text: "Close Nothing X on your phone. The earbuds accept only one controller at a time.")
        }
    }
}

private struct PairedRow: View {
    let buds: BluetoothTransport.PairedEarbuds
    @EnvironmentObject var device: EarbudsController

    var body: some View {
        let linking = device.linking == buds.address
        HStack(spacing: 10) {
            EarbudGlyph(part: .pair, look: linking ? .connecting : .connected, size: 12, color: Theme.secondaryLabel)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.controlFill))
            Text(buds.name).font(.body13).lineLimit(1)
            Spacer(minLength: 4)
            if linking {
                PendingSpinner(size: 12)
            } else {
                Button("Connect") { device.connectPaired(buds.address) }
                    .buttonStyle(PanelButtonStyle())
                    .disabled(device.linking != nil)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 42)
    }
}

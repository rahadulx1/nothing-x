// Equalizer page: preset list and, for Custom, a frequency-response curve over
// Bass / Mid / Treble sliders (−6…+6 dB), plus custom EQs saved on this Mac.

import AppKit
import NothingKit
import SwiftUI

struct EqualizerView: View {
    @EnvironmentObject var device: EarbudsController
    @EnvironmentObject var settings: AppSettings

    private var eq: EqState { device.state.eq }
    private var caps: EqCapabilities { device.state.capabilities.eq }

    var body: some View {
        let customSelected = caps.customId != nil && eq.preset == caps.customId
        let bands = eq.custom ?? CustomEq()
        VStack(spacing: 0) {
            SubpageHeader(title: "Equalizer", back: .main) {
                if eq.pending { PendingSpinner(size: 12) }
            }

            PageStack {
                PanelCard(spacing: 10) {
                    SectionCaption("Presets", symbol: "music.note")
                    GlassGroup(spacing: 6) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                                  spacing: 6) {
                            ForEach(caps.presets) { preset in
                                let selected = eq.preset == preset.id
                                PresetChip(label: preset.label, selected: selected, pending: selected && eq.pending) {
                                    guard !eq.pending else { return }
                                    device.setEqPreset(preset.id)
                                }
                            }
                        }
                    }
                }

                if customSelected {
                    PanelCard(spacing: 8) {
                        SectionCaption("Custom", trailing: "−6 to +6 dB", symbol: "slider.vertical.3")
                        EqCurve(bands: bands)
                            .frame(height: 84)
                            .padding(.bottom, 4)
                        BandSlider(name: "Bass", value: bands.bass) { var b = bands; b.bass = $0; device.setCustomEq(b) }
                        BandSlider(name: "Mid", value: bands.mid) { var b = bands; b.mid = $0; device.setCustomEq(b) }
                        BandSlider(name: "Treble", value: bands.treble) { var b = bands; b.treble = $0; device.setCustomEq(b) }
                        HStack {
                            Spacer()
                            Button("Reset") { device.setCustomEq(CustomEq()) }
                                .buttonStyle(PanelButtonStyle())
                                .disabled(bands == CustomEq())
                                .help("Set all bands to 0 dB")
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }

                if caps.customId != nil {
                    SavedPresets(current: customSelected ? bands : nil)
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: customSelected)
    }
}

/// A preset as a glass capsule; the selected one is tinted with the accent.
private struct PresetChip: View {
    let label: String
    let selected: Bool
    var pending = false
    let action: () -> Void
    @Environment(\.accentFill) private var accentFill

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if pending {
                    PendingSpinner(size: 10)
                } else if selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                }
                Text(label).font(.system(size: 12, weight: selected ? .semibold : .medium)).lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(selected ? Color.white : Theme.label)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30)
            .contentShape(Capsule())
            .glassSurface(Capsule(), tint: selected ? accentFill : nil, interactive: true)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.easeOut(duration: 0.2), value: selected)
    }
}

/// −6…+6 dB in 1 dB steps; the fill grows from the 0 dB tick.
private struct BandSlider: View {
    let name: String
    let value: Int
    let onChange: (Int) -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 10) {
            Text(name).font(.callout12).frame(width: 44, alignment: .leading)
            GeometryReader { geo in
                let knob: CGFloat = 24
                let usable = geo.size.width - knob
                let xFor = { (v: Int) in knob / 2 + CGFloat(v + 6) / 12 * usable }
                let zero = xFor(0), x = xFor(value)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.trackOff).frame(height: 6)
                    Capsule().fill(accent)
                        .frame(width: max(abs(x - zero), 6), height: 6)
                        .offset(x: min(x, zero) - (abs(x - zero) < 6 ? 3 : 0))
                        .opacity(value == 0 ? 0 : 1)
                    Capsule().fill(Theme.tertiary).frame(width: 2, height: 12).offset(x: zero - 1)
                    SliderKnob(width: knob, height: 16)
                        .offset(x: x - knob / 2)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    let v = Int(((drag.location.x - knob / 2) / usable * 12 - 6).rounded())
                    let clamped = min(max(v, -6), 6)
                    if clamped != value { onChange(clamped) }
                })
            }
            .frame(height: 24)
            .accessibilityElement()
            .accessibilityLabel(name)
            .accessibilityValue(Self.format(value))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: if value < 6 { onChange(value + 1) }
                case .decrement: if value > -6 { onChange(value - 1) }
                @unknown default: break
                }
            }
            Text(Self.format(value)).font(.caption11Medium.monospacedDigit())
                .foregroundStyle(value == 0 ? Theme.secondaryLabel : Theme.label)
                .frame(width: 40, alignment: .trailing)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: value)
    }

    static func format(_ v: Int) -> String {
        v > 0 ? "+\(v) dB" : v < 0 ? "−\(abs(v)) dB" : "0 dB"
    }
}

// MARK: - Saved presets

private struct SavedPresets: View {
    /// The current custom bands, or nil when a built-in preset is selected.
    let current: CustomEq?
    @EnvironmentObject var device: EarbudsController
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        PanelCard(padding: 6, spacing: 2) {
            SectionCaption("Saved Presets", trailing: settings.savedEqs.isEmpty ? nil : "\(settings.savedEqs.count)",
                           symbol: "bookmark")
                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 4)
            if settings.savedEqs.isEmpty {
                Text("Choose Custom, shape the sound, then save it here.")
                    .font(.caption11).foregroundStyle(Theme.tertiary)
                    .padding(.horizontal, 10).padding(.bottom, 4)
            }
            ForEach(settings.savedEqs) { saved in
                HStack(spacing: 0) {
                    SelectRow(label: saved.name, detail: Self.summary(saved), selected: saved.bands == current) {
                        device.setCustomEq(saved.bands)
                    }
                    Menu {
                        Button("Apply") { device.setCustomEq(saved.bands) }
                        if let current, current != saved.bands {
                            Button("Update with Current Bands") {
                                settings.saveEq(name: saved.name, bands: current)
                            }
                        }
                        Button("Rename…") {
                            if let name = NamePrompt.ask(title: "Rename Preset", initial: saved.name) {
                                settings.renameEq(saved, to: name)
                            }
                        }
                        Divider()
                        Button("Delete", role: .destructive) { settings.deleteEq(saved) }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 11, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .tint(Theme.secondaryLabel)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .accessibilityLabel("\(saved.name) options")
                }
            }
            Button {
                if let name = NamePrompt.ask(title: "Save Preset", initial: "") {
                    settings.saveEq(name: name, bands: current ?? CustomEq())
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 13))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 14)
                    Text("Save Current…").font(.body13)
                    Spacer()
                }
                .frame(height: 30)
            }
            .buttonStyle(HoverRowStyle())
            .disabled(current == nil)
            .help(current == nil ? "Choose Custom to save its bands" : "Save the current bands under a name")
        }
    }

    static func summary(_ eq: SavedEq) -> String {
        func f(_ v: Int) -> String { v > 0 ? "+\(v)" : v < 0 ? "−\(abs(v))" : "0" }
        return "B\(f(eq.bass)) M\(f(eq.mid)) T\(f(eq.treble))"
    }
}

/// A small NSAlert asking for a name. Returns nil when cancelled or empty.
enum NamePrompt {
    static func ask(title: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Name"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = initial
        field.placeholderString = "e.g. Commute"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

// MARK: - Curve

/// Frequency response of the three bands on a log axis (20 Hz–20 kHz):
/// low shelf at 150 Hz, peak at 1 kHz, high shelf at 6 kHz.
private struct EqCurve: View {
    let bands: CustomEq
    @Environment(\.accent) private var accent

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, plotH = geo.size.height - 14
            let logMin = log10(20.0), logMax = log10(20_000.0)
            let xFor = { (f: Double) in CGFloat((log10(f) - logMin) / (logMax - logMin)) * w }
            let yFor = { (db: Double) in plotH / 2 - CGFloat(db / 7) * (plotH / 2) }
            let samples = (0...80).map { i -> CGPoint in
                let f = pow(10, logMin + (logMax - logMin) * Double(i) / 80)
                return CGPoint(x: xFor(f), y: yFor(Self.response(f, bands)))
            }
            let curve = Path { p in p.addLines(samples) }
            ZStack(alignment: .topLeading) {
                // ±6 dB lines and decade lines
                Path { p in
                    for db in [-6.0, 6.0] {
                        p.move(to: CGPoint(x: 0, y: yFor(db))); p.addLine(to: CGPoint(x: w, y: yFor(db)))
                    }
                    for f in [100.0, 1000, 10_000] {
                        p.move(to: CGPoint(x: xFor(f), y: 0)); p.addLine(to: CGPoint(x: xFor(f), y: plotH))
                    }
                }
                .stroke(Theme.separator, lineWidth: 1)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: yFor(0))); p.addLine(to: CGPoint(x: w, y: yFor(0)))
                }
                .stroke(Theme.tertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

                Path { p in
                    p.addLines(samples)
                    p.addLine(to: CGPoint(x: w, y: yFor(0)))
                    p.addLine(to: CGPoint(x: 0, y: yFor(0)))
                    p.closeSubpath()
                }
                .fill(accent.opacity(0.12))
                curve.stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                Text("+6").font(.system(size: 9)).foregroundStyle(Theme.secondaryLabel)
                    .offset(x: 2, y: yFor(6) - 12)
                ForEach([(100.0, "100"), (1000, "1k"), (10_000, "10k")], id: \.1) { f, label in
                    Text(label).font(.system(size: 9)).foregroundStyle(Theme.secondaryLabel)
                        .offset(x: xFor(f) + 3, y: plotH + 2)
                }
            }
            .animation(.easeOut(duration: 0.15), value: bands)
        }
        .padding(.horizontal, 2)
        .accessibilityHidden(true)
    }

    /// Smooth approximation of shelf and peak filters, in dB.
    static func response(_ f: Double, _ b: CustomEq) -> Double {
        let octaves = { (fc: Double) in log2(f / fc) }
        let lowShelf = Double(b.bass) / (1 + exp(octaves(150) * 2.2))
        let peak = Double(b.mid) * exp(-pow(octaves(1000), 2) / (2 * 0.9 * 0.9))
        let highShelf = Double(b.treble) / (1 + exp(-octaves(6000) * 2.2))
        return lowShelf + peak + highShelf
    }
}

// Controls page (gestures): pick the left or right bud, then a pop-up per
// gesture. When a gesture is set to Noise Control, checkboxes choose which
// modes it cycles through. Opened by clicking a bud on the main page.

import NothingKit
import SwiftUI

struct ControlsView: View {
    let side: GestureSide
    @EnvironmentObject var device: EarbudsController
    @EnvironmentObject var nav: PanelNavigation

    var body: some View {
        let state = device.state
        VStack(spacing: 0) {
            SubpageHeader(title: "Controls", back: .main)

            PageStack {
                GlassSegmented(items: GestureSide.allCases.map { SegmentItem(id: $0, label: $0.label) },
                               selection: side, height: 32, labelSize: 12) { nav.page = .controls($0) }

                if let caps = state.capabilities.gestures {
                    PanelCard(padding: 6, spacing: 0) {
                        ForEach(Array(caps.slots.enumerated()), id: \.element.id) { index, slot in
                            if index > 0 { PanelSeparator().padding(.horizontal, 8) }
                            GestureRow(side: side, slot: slot)
                            if slot.actions.contains(where: { $0.choice == .noiseControl }),
                               let code = state.gestures.code(side, slot.key),
                               let cycle = GestureCapabilities.noiseCycles[code] {
                                NoiseCycleRows(side: side, slotKey: slot.key, cycle: cycle)
                            }
                        }
                    }
                }

                FooterNote("Changes apply to the \(side.label) earbud only.")
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct GestureRow: View {
    let side: GestureSide
    let slot: GestureSlot
    @EnvironmentObject var device: EarbudsController

    var body: some View {
        let code = device.state.gestures.code(side, slot.key)
        let current = code.map(GestureCapabilities.choice(for:))
        let pending = device.state.gestures.pending.contains("\(side.rawValue).\(slot.key)")
        HStack(spacing: 10) {
            RowIcon(symbol: Self.symbol(for: slot.key), color: Theme.label)
            Text(slot.label.replacingOccurrences(of: " and ", with: " & "))
                .font(.body13)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if pending { PendingSpinner(size: 11) }
            Picker(slot.label, selection: Binding(
                get: { current ?? slot.actions.first!.choice },
                set: { device.setGesture(side, slot: slot.key, choice: $0) })) {
                ForEach(slot.actions, id: \.self) { action in
                    Text(action.label).tag(action.choice)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 132)
            .disabled(pending || current == nil)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 44)
    }

    static func symbol(for key: String) -> String {
        switch key {
        case "doubleTap": return "hand.tap"
        case "tripleTap": return "hand.tap.fill"
        case "tapHold", "pinchHold": return "hand.point.up.left"
        case "doubleTapHold": return "hand.point.up.left.fill"
        default: return "hand.tap"
        }
    }
}

private struct NoiseCycleRows: View {
    let side: GestureSide
    let slotKey: String
    let cycle: NoiseCycle
    @EnvironmentObject var device: EarbudsController

    var body: some View {
        let onCount = [cycle.anc, cycle.transparency, cycle.off].filter { $0 }.count
        VStack(alignment: .leading, spacing: 6) {
            Text("Cycles through").font(.caption11Medium).foregroundStyle(Theme.secondaryLabel)
            row("Noise Cancellation", cycle.anc, onCount) { var c = cycle; c.anc = $0; return c }
            row("Transparency", cycle.transparency, onCount) { var c = cycle; c.transparency = $0; return c }
            row("Off", cycle.off, onCount) { var c = cycle; c.off = $0; return c }
            Text("Pick at least two.").font(.caption11).foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.controlFill))
        .padding(.leading, 42)
        .padding(.trailing, 8)
        .padding(.bottom, 8)
    }

    private func row(_ label: String, _ on: Bool, _ onCount: Int, _ change: @escaping (Bool) -> NoiseCycle) -> some View {
        Toggle(isOn: Binding(get: { on }, set: { device.setGestureNoiseCycle(side, slot: slotKey, cycle: change($0)) })) {
            Text(label).font(.body13)
        }
        .toggleStyle(.checkbox)
        // The last two ticked modes can't be cleared.
        .disabled(on && onCount <= 2)
    }
}

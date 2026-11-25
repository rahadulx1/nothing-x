// The popover panel: the main page plus sub-pages that slide in from the right,
// and the Liquid Glass building blocks they share (see Theme.swift for tokens).

import NothingKit
import SwiftUI

enum PanelPage: Equatable {
    case main, quickSettings, spatial, dual, equalizer, earTip, settings
    case controls(GestureSide)
}

final class PanelNavigation: ObservableObject {
    @Published var page: PanelPage = .main
}

struct PanelView: View {
    static let width = Theme.panelWidth

    @EnvironmentObject var device: EarbudsController
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var nav: PanelNavigation

    var body: some View {
        ZStack {
            switch nav.page {
            case .main:
                MainView().transition(.move(edge: .leading).combined(with: .opacity))
            case .quickSettings:
                QuickSettingsView().transition(.move(edge: .trailing).combined(with: .opacity))
            case .spatial:
                SpatialAudioView().transition(.move(edge: .trailing).combined(with: .opacity))
            case .dual:
                DualConnectionView().transition(.move(edge: .trailing).combined(with: .opacity))
            case .equalizer:
                EqualizerView().transition(.move(edge: .trailing).combined(with: .opacity))
            case .controls(let side):
                ControlsView(side: side).transition(.move(edge: .trailing).combined(with: .opacity))
            case .earTip:
                EarTipTestView().transition(.move(edge: .trailing).combined(with: .opacity))
            case .settings:
                SettingsView().transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: Self.width)
        .background(AmbientBackdrop())
        .foregroundStyle(Theme.label)
        .font(.body13)
        .panelAccent(system: settings.useSystemAccent)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: nav.page)
        .background(KeyboardShortcuts())
        .onChange(of: device.state.connected) { connected in
            if !connected && nav.page != .settings { nav.page = .main }
        }
    }
}

extension PanelPage {
    var parent: PanelPage {
        switch self {
        case .spatial, .dual, .earTip: return .quickSettings
        default: return .main
        }
    }
}

/// A soft accent glow at the top of the panel so the glass above it has
/// something to refract, like a wallpaper showing through.
private struct AmbientBackdrop: View {
    @Environment(\.accent) private var accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            RadialGradient(colors: [accent.opacity(scheme == .dark ? 0.20 : 0.12), .clear],
                           center: UnitPoint(x: 0.15, y: 0), startRadius: 0, endRadius: 260)
            RadialGradient(colors: [Color.blue.opacity(scheme == .dark ? 0.10 : 0.06), .clear],
                           center: UnitPoint(x: 1, y: 0.35), startRadius: 0, endRadius: 240)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Invisible buttons that give the panel its keyboard shortcuts.
private struct KeyboardShortcuts: View {
    @EnvironmentObject var device: EarbudsController
    @EnvironmentObject var nav: PanelNavigation

    var body: some View {
        let state = device.state
        ZStack {
            // Esc goes back one level.
            Button("") { nav.page = nav.page.parent }.keyboardShortcut(.cancelAction)
            Button("") { nav.page = .settings }.keyboardShortcut(",", modifiers: .command)
            Button("") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
            if state.connected {
                Button("") { nav.page = .main }.keyboardShortcut("0", modifiers: .command)
                Button("") { nav.page = .quickSettings }.keyboardShortcut("k", modifiers: .command)
                if !state.capabilities.eq.presets.isEmpty {
                    Button("") { nav.page = .equalizer }.keyboardShortcut("e", modifiers: .command)
                }
                // ⌘1 / ⌘2 / ⌘3: Noise Cancellation, Transparency, Off.
                Button("") { device.setNoiseMode(.anc) }.keyboardShortcut("1", modifiers: .command)
                if state.capabilities.transparency {
                    Button("") { device.setNoiseMode(.transparency) }.keyboardShortcut("2", modifiers: .command)
                }
                Button("") { device.setNoiseMode(.off) }.keyboardShortcut("3", modifiers: .command)
            }
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}

// MARK: - Structure

/// A glass card holding one group of controls.
struct PanelCard<Content: View>: View {
    var padding: CGFloat = Theme.inset
    var spacing: CGFloat = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
    }
}

/// 1 pt hairline between rows inside a card.
struct PanelSeparator: View {
    var body: some View {
        Rectangle().fill(Theme.separator).frame(height: 1)
    }
}

/// Small semibold caption above a group of controls.
struct SectionCaption: View {
    let text: String
    var trailing: String?
    var symbol: String?
    init(_ text: String, trailing: String? = nil, symbol: String? = nil) {
        self.text = text
        self.trailing = trailing
        self.symbol = symbol
    }

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            }
            Text(text).font(.sectionCaption)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing).font(.caption11)
            }
        }
        .foregroundStyle(Theme.secondaryLabel)
    }
}

/// Round glass back button + title for sub-pages, with an optional trailing control.
struct SubpageHeader<Trailing: View>: View {
    let title: String
    var back: PanelPage?
    @ViewBuilder var trailing: () -> Trailing
    @EnvironmentObject var nav: PanelNavigation

    var body: some View {
        HStack(spacing: 10) {
            GlassIconButton(symbol: "chevron.left", help: "Back") { nav.page = back ?? nav.page.parent }
            Text(title).font(.panelTitle).lineLimit(1)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, Theme.margin + 2)
        .padding(.top, Theme.margin)
        .padding(.bottom, 4)
        .frame(minHeight: 52)
    }
}

extension SubpageHeader where Trailing == EmptyView {
    init(title: String, back: PanelPage? = nil) {
        self.title = title
        self.back = back
        self.trailing = { EmptyView() }
    }
}

/// The scrolling-free body of a sub-page: cards stacked with even spacing.
struct PageStack<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: Theme.spacing) { content() }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 6)
            .padding(.bottom, Theme.margin)
    }
}

struct FooterNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption11)
            .foregroundStyle(Theme.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Glass info box (tips, limits, warnings).
struct TipBox: View {
    var symbol = "info.circle.fill"
    var bold: String?
    let text: String
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent)
            (bold.map { Text($0 + " ").fontWeight(.semibold).foregroundColor(Theme.label) } ?? Text(""))
                + Text(text).foregroundColor(Theme.secondaryLabel)
        }
        .font(.caption11)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(radius: 16)
    }
}

// MARK: - Controls

/// Small spinner for "waiting for the buds to confirm" (secondary tint, never accent).
struct PendingSpinner: View {
    var size: CGFloat = 13
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .scaleEffect(size / 16)
            .frame(width: size, height: size)
            .tint(Theme.secondaryLabel)
    }
}

/// A round glass icon button (header actions, back).
struct GlassIconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.label.opacity(0.85))
                .frame(width: size, height: size)
                .contentShape(Circle())
                .glassSurface(Circle(), interactive: true)
        }
        .buttonStyle(PressScaleStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Plain button that gives a gentle squish when pressed.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// One option of a `GlassSegmented` control.
struct SegmentItem<ID: Hashable>: Identifiable {
    let id: ID
    let label: String
    var symbol: String?
}

/// Segmented control: a recessed track with a glass thumb that glides to the
/// selection. The selected icon takes the accent; a pending option shows a
/// spinner instead of its icon while the others dim.
struct GlassSegmented<ID: Hashable>: View {
    let items: [SegmentItem<ID>]
    let selection: ID?
    var pending = false
    var height: CGFloat = 54
    var labelSize: CGFloat = 11
    let onSelect: (ID) -> Void
    @Environment(\.accent) private var accent
    @Namespace private var thumb

    var body: some View {
        let radius: CGFloat = height >= 40 ? 15 : height / 2
        let thumbShape = RoundedRectangle(cornerRadius: radius - 3, style: .continuous)
        HStack(spacing: 0) {
            ForEach(items) { item in
                let selected = item.id == selection
                Button { if !pending { onSelect(item.id) } } label: {
                    VStack(spacing: 4) {
                        if let symbol = item.symbol {
                            if selected && pending {
                                PendingSpinner(size: 14).frame(height: 17)
                            } else {
                                Image(systemName: symbol)
                                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? accent : Theme.secondaryLabel)
                                    .frame(height: 17)
                            }
                        }
                        HStack(spacing: 4) {
                            if item.symbol == nil && selected && pending { PendingSpinner(size: 10) }
                            Text(item.label)
                                .font(.system(size: labelSize, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? Theme.label : Theme.secondaryLabel)
                                .lineLimit(1)
                                .minimumScaleFactor(item.symbol == nil ? 1 : 0.8)
                                .fixedSize(horizontal: item.symbol == nil, vertical: false)
                        }
                        .padding(.horizontal, 6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if selected {
                            SegmentThumb(shape: thumbShape)
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .opacity(pending && !selected ? 0.5 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.controlFill))
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: selection)
    }
}

private struct SegmentThumb: View {
    let shape: RoundedRectangle

    var body: some View {
        if #available(macOS 26.0, *), LiquidGlass.nativeAllowed {
            shape.fill(Theme.thumbFill.opacity(0.55))
                .glassEffect(.regular.interactive(), in: shape)
                .shadow(color: Theme.thumbShadow.opacity(0.5), radius: 3, y: 1)
        } else {
            shape.fill(Theme.thumbFill)
                .overlay(shape.strokeBorder(Theme.glassRimTop.opacity(0.6), lineWidth: 0.5))
                .shadow(color: Theme.thumbShadow, radius: 2.5, y: 1)
        }
    }
}

/// Capsule glass button. Primary is accent-tinted glass with a white label.
struct PanelButtonStyle: ButtonStyle {
    var primary = false
    var fullWidth = false
    @Environment(\.accentFill) private var accentFill
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body13Medium)
            .foregroundStyle(primary ? Color.white : Theme.label)
            .padding(.horizontal, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 30)
            .contentShape(Capsule())
            .glassSurface(Capsule(), tint: primary ? accentFill : nil, interactive: true)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(enabled ? 1 : 0.5)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A list row (preset, spatial mode): accent checkmark, selected row softly filled.
struct SelectRow: View {
    let label: String
    var detail: String?
    let selected: Bool
    var pending = false
    var height: CGFloat = 32
    let action: () -> Void
    @Environment(\.accent) private var accent
    @StateObject private var hovering = Local(false)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Group {
                    if pending {
                        PendingSpinner(size: 11)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(accent)
                            .opacity(selected ? 1 : 0)
                    }
                }
                .frame(width: 14)
                Text(label).font(selected ? .body13Medium : .body13).lineLimit(1)
                Spacer(minLength: 4)
                if let detail {
                    Text(detail).font(.caption11.monospacedDigit()).foregroundStyle(Theme.secondaryLabel)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(selected ? Theme.controlFillStrong : hovering.value ? Theme.controlFill : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering.value = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A full-width row inside a card that highlights on hover, like menu items.
struct HoverRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverRow(configuration: configuration)
    }

    private struct HoverRow: View {
        let configuration: ButtonStyle.Configuration
        @StateObject private var hovering = Local(false)
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                        .fill(configuration.isPressed ? Theme.controlFillStrong
                              : hovering.value && enabled ? Theme.controlFill : .clear)
                )
                .opacity(enabled ? 1 : 0.45)
                .onHover { hovering.value = $0 }
        }
    }
}

/// Icon in a small rounded square, like System Settings rows.
struct RowIcon: View {
    let symbol: String
    var color: Color = Theme.secondaryLabel
    var filled = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(filled ? Color.white : color)
            .frame(width: 24, height: 24)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(filled ? color : Theme.controlFill))
    }
}

/// A row that opens another page: icon, title, optional detail, chevron.
struct NavigationRow: View {
    let symbol: String
    let title: String
    var detail: String?
    var shortcut: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RowIcon(symbol: symbol)
                Text(title).font(.body13)
                Spacer(minLength: 4)
                if let detail {
                    Text(detail).font(.caption11).foregroundStyle(Theme.secondaryLabel).lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.tertiary)
            }
            .frame(height: 32)
        }
        .buttonStyle(HoverRowStyle())
        .help(shortcut.map { "\(title) (\($0))" } ?? title)
    }
}

/// View-local state. Stands in for @State, which is a macro in the current SDK
/// whose plugin only ships with Xcode, not the Command Line Tools.
final class Local<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}

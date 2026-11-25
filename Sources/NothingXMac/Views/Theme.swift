// Design tokens for the Liquid Glass panel: colors (light/dark), radii, type
// (SF Pro via the system font) and the glass surfaces every page is built from.
// On macOS 26+ surfaces use the native Liquid Glass material (`glassEffect`);
// older systems get a layered material fallback with the same shape and highlights.

import AppKit
import SwiftUI

enum Theme {
    // MARK: Colors

    static let brandRed = dynamic(light: NSColor(hex: 0xD92D20), dark: NSColor(hex: 0xFF5A4D))
    /// Primary button fill: white text stays readable in both modes.
    static let brandRedFill = Color(nsColor: NSColor(hex: 0xD92D20))

    static let label = Color(nsColor: .labelColor)
    static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
    static let tertiary = Color(nsColor: .tertiaryLabelColor)
    static let positive = Color(nsColor: .systemGreen)
    static let separator = dynamic(light: .black.withAlphaComponent(0.08), dark: .white.withAlphaComponent(0.09))
    static let controlFill = dynamic(light: .black.withAlphaComponent(0.05), dark: .white.withAlphaComponent(0.07))
    static let controlFillStrong = dynamic(light: .black.withAlphaComponent(0.09), dark: .white.withAlphaComponent(0.13))
    static let trackOff = dynamic(light: .black.withAlphaComponent(0.10), dark: .white.withAlphaComponent(0.14))

    /// Selected segment thumb (fallback fill, and a whisper of tint on real glass).
    static let thumbFill = dynamic(light: .white, dark: .white.withAlphaComponent(0.20))
    static let thumbShadow = dynamic(light: .black.withAlphaComponent(0.16), dark: .black.withAlphaComponent(0.45))

    /// Pre-26 glass: translucent fill and a specular rim that's brighter at the top.
    static let glassFill = dynamic(light: .white.withAlphaComponent(0.55), dark: .white.withAlphaComponent(0.06))
    static let glassRimTop = dynamic(light: .white.withAlphaComponent(0.95), dark: .white.withAlphaComponent(0.22))
    static let glassRimBottom = dynamic(light: .white.withAlphaComponent(0.25), dark: .white.withAlphaComponent(0.04))
    static let glassShadow = dynamic(light: .black.withAlphaComponent(0.07), dark: .black.withAlphaComponent(0.30))

    // MARK: Metrics

    static let panelWidth: CGFloat = 320
    /// Outer margin between the panel edge and its cards.
    static let margin: CGFloat = 12
    /// Inner padding of a card.
    static let inset: CGFloat = 14
    static let cardRadius: CGFloat = 20
    static let tileRadius: CGFloat = 18
    static let rowRadius: CGFloat = 10
    static let spacing: CGFloat = 10

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
                .map { $0 == .darkAqua || $0 == .vibrantDark } == true ? dark : light
        })
    }
}

/// SF Pro (the macOS system font) at the panel's type ramp.
extension Font {
    static let panelTitle = Font.system(size: 15, weight: .semibold)
    static let pageTitle = Font.system(size: 14, weight: .semibold)
    static let body13 = Font.system(size: 13)
    static let body13Medium = Font.system(size: 13, weight: .medium)
    static let callout12 = Font.system(size: 12)
    static let caption11 = Font.system(size: 11)
    static let caption11Medium = Font.system(size: 11, weight: .medium)
    static let sectionCaption = Font.system(size: 11, weight: .semibold)
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

// MARK: - Liquid Glass

enum LiquidGlass {
    /// Native Liquid Glass on macOS 26+. Debug snapshots turn it off because
    /// the system glass is composited by the window server and doesn't show up
    /// in offscreen bitmap captures.
    static var nativeAllowed = true

    static var isNative: Bool {
        if #available(macOS 26.0, *) { return nativeAllowed }
        return false
    }
}

extension View {
    /// A Liquid Glass surface in `shape`. `tint` colors the glass (prominent
    /// controls); `interactive` makes it react to the pointer on macOS 26+.
    func glassSurface<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive))
    }

    /// The standard card: a continuous rounded rectangle of glass.
    func glassCard(radius: CGFloat = Theme.cardRadius) -> some View {
        glassSurface(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

private struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), LiquidGlass.nativeAllowed {
            content.glassEffect(glass, in: shape)
        } else {
            content.background(fallback)
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }

    private var fallback: some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(tint ?? Theme.glassFill)
            shape.strokeBorder(
                LinearGradient(colors: [Theme.glassRimTop, Theme.glassRimBottom],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 0.75)
        }
        .shadow(color: Theme.glassShadow, radius: 8, y: 3)
    }
}

/// Groups glass shapes so they blend and morph together on macOS 26+.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = Theme.spacing
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *), LiquidGlass.nativeAllowed {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

// MARK: - Accent

/// Brand red by default; the system accent color when the user turns that on.
private struct AccentKey: EnvironmentKey {
    static let defaultValue = Theme.brandRed
}

private struct AccentFillKey: EnvironmentKey {
    static let defaultValue = Theme.brandRedFill
}

extension EnvironmentValues {
    var accent: Color {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }

    /// Fill for primary buttons and "on" tile discs (white content on top).
    var accentFill: Color {
        get { self[AccentFillKey.self] }
        set { self[AccentFillKey.self] = newValue }
    }
}

extension View {
    func panelAccent(system: Bool) -> some View {
        environment(\.accent, system ? Color.accentColor : Theme.brandRed)
            .environment(\.accentFill, system ? Color.accentColor : Theme.brandRedFill)
            .tint(system ? Color.accentColor : Theme.brandRed)
    }
}

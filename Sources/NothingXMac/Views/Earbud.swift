// The earbud mark used everywhere (menu bar, battery gauges, fit test, empty
// states): Apple's current AirPods Pro SF Symbols, falling back to older
// AirPods symbols on systems that don't have them. Each state uses the same glyph and only
// changes its opacity (plus a small badge when low), so the menu bar item never jumps.

import AppKit
import SwiftUI

enum Earbud {
    enum Look: Equatable {
        case disconnected, connecting, connected, low
    }

    enum Part {
        case pair, left, right, chargingCase

        /// Newest design first; the first one this system has wins.
        private var candidates: [String] {
            switch self {
            case .pair: return ["airpods.pro.gen3", "airpods.pro", "airpods"]
            case .left: return ["airpodpro.left", "airpod.left"]
            case .right: return ["airpodpro.right", "airpod.right"]
            case .chargingCase: return ["airpods.pro.gen3.chargingcase.wireless.fill",
                                        "airpodspro.chargingcase.wireless.fill", "airpods.chargingcase.fill"]
            }
        }

        var symbol: String {
            if let cached = Part.resolved[self] { return cached }
            let name = candidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
                ?? candidates[candidates.count - 1]
            Part.resolved[self] = name
            return name
        }

        private static var resolved: [Part: String] = [:]
    }

    static func alpha(_ look: Look) -> CGFloat {
        switch look {
        case .disconnected: return 0.4
        case .connecting: return 0.65
        case .connected, .low: return 1
        }
    }

    /// Menu bar template image (black + alpha; macOS tints it). Low adds a dot badge.
    static func templateImage(_ look: Look) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let symbol = NSImage(systemSymbolName: Part.pair.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage()
        let badge: CGFloat = look == .low ? 5 : 0
        let size = NSSize(width: symbol.size.width + badge * 0.6, height: max(symbol.size.height, 16))
        let image = NSImage(size: size, flipped: false) { _ in
            let y = (size.height - symbol.size.height) / 2
            symbol.draw(in: NSRect(x: 0, y: y, width: symbol.size.width, height: symbol.size.height),
                        from: .zero, operation: .sourceOver, fraction: alpha(look))
            if look == .low {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: size.width - badge, y: 0.5, width: badge, height: badge)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Nothing X Mac"
        return image
    }
}

/// An AirPods SF Symbol as a SwiftUI view.
struct EarbudGlyph: View {
    var part: Earbud.Part = .pair
    var look: Earbud.Look = .connected
    var size: CGFloat = 18
    var color: Color = Theme.label

    var body: some View {
        Image(systemName: part.symbol)
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(color)
            .opacity(Earbud.alpha(look))
            .accessibilityHidden(true)
    }
}

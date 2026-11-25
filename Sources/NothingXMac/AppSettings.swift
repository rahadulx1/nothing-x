// User preferences kept in UserDefaults, and Open at Login.

import Foundation
import NothingKit
import ServiceManagement

/// What to show next to the menu bar icon.
enum MenuBarBattery: String, CaseIterable, Identifiable {
    case off, both, average, minimum
    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Icon Only"
        case .both: return "Left · Right"
        case .average: return "Average"
        case .minimum: return "Lowest"
        }
    }

    /// nil when there's nothing to show.
    func text(for battery: Battery) -> String? {
        let left = battery.left?.level
        let right = battery.right?.level
        let single = battery.stereo?.level
        switch (self, left, right) {
        case (.off, _, _):
            return nil
        case (.both, let l?, let r?):
            return "\(l)\u{2009}·\u{2009}\(r)" // thin spaces around the middle dot
        case (.average, let l?, let r?):
            return "\((l + r) / 2)%"
        case (.minimum, let l?, let r?):
            return "\(min(l, r))%"
        case (_, let l?, nil):
            return "\(l)%"
        case (_, nil, let r?):
            return "\(r)%"
        default:
            return single.map { "\($0)%" }
        }
    }
}

/// A named custom EQ the user saved locally.
struct SavedEq: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var bass: Int
    var mid: Int
    var treble: Int

    var bands: CustomEq { CustomEq(bass: bass, mid: mid, treble: treble) }
}

final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var menuBarBattery: MenuBarBattery {
        didSet { defaults.set(menuBarBattery.rawValue, forKey: "menuBarBattery") }
    }

    /// Also show the case level in the menu bar when the buds report it.
    @Published var menuBarCase: Bool {
        didSet { defaults.set(menuBarCase, forKey: "menuBarCase") }
    }

    /// Notify when a bud, the case or headphones drop to 20% and 10%.
    @Published var lowBatteryAlerts: Bool {
        didSet { defaults.set(lowBatteryAlerts, forKey: "lowBatteryAlerts") }
    }

    /// Use the system accent color instead of the brand red.
    @Published var useSystemAccent: Bool {
        didSet { defaults.set(useSystemAccent, forKey: "useSystemAccent") }
    }

    @Published private(set) var savedEqs: [SavedEq] {
        didSet {
            if let data = try? JSONEncoder().encode(savedEqs) { defaults.set(data, forKey: "savedEqs") }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuBarBattery = MenuBarBattery(rawValue: defaults.string(forKey: "menuBarBattery") ?? "") ?? .off
        lowBatteryAlerts = defaults.object(forKey: "lowBatteryAlerts") as? Bool ?? true
        menuBarCase = defaults.object(forKey: "menuBarCase") as? Bool ?? true
        useSystemAccent = defaults.bool(forKey: "useSystemAccent")
        if let data = defaults.data(forKey: "savedEqs"),
           let saved = try? JSONDecoder().decode([SavedEq].self, from: data) {
            savedEqs = saved
        } else {
            savedEqs = []
        }
    }

    func saveEq(name: String, bands: CustomEq) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let i = savedEqs.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            savedEqs[i].bass = bands.bass
            savedEqs[i].mid = bands.mid
            savedEqs[i].treble = bands.treble
        } else {
            savedEqs.append(SavedEq(name: trimmed, bass: bands.bass, mid: bands.mid, treble: bands.treble))
        }
    }

    func renameEq(_ eq: SavedEq, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = savedEqs.firstIndex(where: { $0.id == eq.id }) else { return }
        savedEqs[i].name = trimmed
    }

    func deleteEq(_ eq: SavedEq) {
        savedEqs.removeAll { $0.id == eq.id }
    }
}

/// Open at Login via SMAppService. Only an app bundle can be a login item.
enum LoginItem {
    static var isSupported: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    static var isEnabled: Bool { isSupported && SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ on: Bool) {
        guard isSupported else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.info("Open at Login change failed: \(error.localizedDescription)")
        }
    }

    /// Turn Open at Login on once, the first time the app runs from /Applications
    /// (not from a development build folder).
    static func enableOnFirstRun() {
        let installed = Bundle.main.bundlePath.hasPrefix("/Applications/")
        guard isSupported, installed, !UserDefaults.standard.bool(forKey: "loginItemInitialized") else { return }
        UserDefaults.standard.set(true, forKey: "loginItemInitialized")
        setEnabled(true)
    }
}

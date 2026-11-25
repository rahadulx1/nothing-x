// Decides when a battery level deserves a "low battery" alert.
//
// Each part (left, right, case, single unit) alerts once per threshold as it
// drains: first at 20%, again at 10%. It re-arms after charging, or once the
// level is back at least 5 points above the threshold it last alerted at
// (e.g. a fresh bud swapped in), so alerts never repeat while a battery sits
// at a low level.

public enum BatteryPart: String, CaseIterable {
    case left, right, `case`, single

    public var label: String {
        switch self {
        case .left: return "Left earbud"
        case .right: return "Right earbud"
        case .case: return "Case"
        case .single: return "Battery"
        }
    }
}

public struct LowBatteryAlert: Equatable {
    public let part: BatteryPart
    public let level: Int
    public let threshold: Int

    public init(part: BatteryPart, level: Int, threshold: Int) {
        self.part = part
        self.level = level
        self.threshold = threshold
    }
}

public struct LowBatteryTracker {
    public static let defaultThresholds = [20, 10]
    static let rearmMargin = 5

    public let thresholds: [Int]
    /// Lowest threshold already alerted for each part.
    private var alerted: [BatteryPart: Int] = [:]

    public init(thresholds: [Int] = LowBatteryTracker.defaultThresholds) {
        self.thresholds = thresholds.sorted()
    }

    /// Feed the latest battery report; returns the alerts it triggers.
    public mutating func update(_ battery: Battery) -> [LowBatteryAlert] {
        let parts: [(BatteryPart, BatteryLevel?)] = [
            (.left, battery.left), (.right, battery.right),
            (.case, battery.case), (.single, battery.stereo),
        ]
        return parts.compactMap { part, info in
            guard let info else { return nil } // not reported (e.g. bud in a closed case)
            return update(part, level: info.level, charging: info.charging)
        }
    }

    mutating func update(_ part: BatteryPart, level: Int, charging: Bool) -> LowBatteryAlert? {
        if charging {
            alerted[part] = nil
            return nil
        }
        if let last = alerted[part], level >= last + Self.rearmMargin {
            alerted[part] = nil
        }
        // The lowest threshold the level is at or below, e.g. 18% -> 20, 8% -> 10.
        guard let threshold = thresholds.first(where: { level <= $0 }) else { return nil }
        if let last = alerted[part], threshold >= last { return nil }
        alerted[part] = threshold
        return LowBatteryAlert(part: part, level: level, threshold: threshold)
    }

    public mutating func reset() { alerted.removeAll() }
}

// Per-model capabilities, keyed by the product name the earbuds advertise over
// Bluetooth, plus equalizer preset lists and gesture layouts.
// Capability data referenced from ear-web.

// MARK: - Equalizer presets

public struct EqPreset: Equatable, Identifiable {
    public let id: Int
    /// Picks the tile icon in the UI.
    public let key: String
    public let label: String
}

public enum EqStyle {
    /// Nothing models: GET_EQ / SET_EQ
    case eq
    /// CMF models: GET_LISTENING_MODE / SET_LISTENING_MODE
    case listening
}

public struct EqCapabilities: Equatable {
    public var style: EqStyle
    public var presets: [EqPreset]
    /// Preset id that turns on the 3-band custom EQ (nil = none).
    public var customId: Int?
    public var trebleHz: Int
}

enum EqProfile: String {
    case nothing, nothingNoCustom, cmf, cmfNoDirac, cmfDirac7

    static let nothingPresets = [
        EqPreset(id: 0, key: "balanced", label: "Balanced"),
        EqPreset(id: 3, key: "moreBass", label: "More Bass"),
        EqPreset(id: 2, key: "moreTreble", label: "More Treble"),
        EqPreset(id: 1, key: "voice", label: "Voice"),
    ]
    static let cmfPresets = [
        EqPreset(id: 3, key: "pop", label: "Pop"),
        EqPreset(id: 1, key: "rock", label: "Rock"),
        EqPreset(id: 5, key: "classical", label: "Classical"),
        EqPreset(id: 2, key: "electronic", label: "Electronic"),
        EqPreset(id: 4, key: "vocals", label: "Vocals"),
    ]
    static func dirac(_ id: Int) -> EqPreset { EqPreset(id: id, key: "dirac", label: "Dirac Opteo") }

    func capabilities(trebleHz: Int) -> EqCapabilities {
        let (style, presets, customId): (EqStyle, [EqPreset], Int?) = {
            switch self {
            case .nothing: return (.eq, Self.nothingPresets, 5)
            case .nothingNoCustom: return (.eq, Self.nothingPresets, nil)
            case .cmf: return (.listening, [Self.dirac(0)] + Self.cmfPresets, 6)
            case .cmfNoDirac: return (.listening, Self.cmfPresets, 6)
            case .cmfDirac7: return (.listening, [Self.dirac(7)] + Self.cmfPresets, 6)
            }
        }()
        let all = customId.map { presets + [EqPreset(id: $0, key: "custom", label: "Custom")] } ?? presets
        return EqCapabilities(style: style, presets: all, customId: customId, trebleHz: trebleHz)
    }
}

// MARK: - Gestures

/// What a gesture slot can be set to. "Noise Control" is one choice in the UI but
/// several codes on the wire, depending on which modes tap-and-hold cycles through.
public enum GestureChoice: Hashable {
    case action(UInt8)
    case noiseControl
}

public struct GestureAction: Hashable {
    public let choice: GestureChoice
    public let label: String
}

public struct GestureSlot: Equatable, Identifiable {
    public let key: String
    public let label: String
    public let type: UInt8
    public let actions: [GestureAction]
    public var id: String { key }
}

/// Which modes a tap-and-hold "Noise Control" gesture cycles through.
public struct NoiseCycle: Equatable {
    public var anc: Bool
    public var transparency: Bool
    public var off: Bool
    public init(anc: Bool, transparency: Bool, off: Bool) {
        self.anc = anc
        self.transparency = transparency
        self.off = off
    }
}

public enum GestureSide: String, CaseIterable, Identifiable {
    case left, right
    public var id: String { rawValue }
    public var label: String { self == .left ? "Left" : "Right" }
}

public struct GestureCapabilities: Equatable {
    /// Device ids on the wire: left = 2, right = 3.
    public let sides: [GestureSide: UInt8]
    public let slots: [GestureSlot]

    /// [noise cancellation, transparency, off] -> code (at least two must be on)
    public static let noiseCycles: [UInt8: NoiseCycle] = [
        10: NoiseCycle(anc: true, transparency: true, off: true),
        20: NoiseCycle(anc: false, transparency: true, off: true),
        21: NoiseCycle(anc: true, transparency: false, off: true),
        22: NoiseCycle(anc: true, transparency: true, off: false),
    ]
    public static let defaultNoiseCode: UInt8 = 22

    public static func isNoiseCode(_ code: UInt8?) -> Bool { code.map { noiseCycles[$0] != nil } ?? false }

    public static func noiseCode(for cycle: NoiseCycle) -> UInt8? {
        noiseCycles.first { $0.value == cycle }?.key
    }

    /// UI value for a raw action code.
    public static func choice(for code: UInt8) -> GestureChoice {
        isNoiseCode(code) ? .noiseControl : .action(code)
    }

    /// Tap gestures on CMF buds (CMF Buds 2 Plus / Buds 2 / Buds Pro 2).
    static let cmfTap = GestureCapabilities(
        sides: [.left: 2, .right: 3],
        slots: [
            GestureSlot(key: "doubleTap", label: "Double Tap", type: 2, actions: [
                .init(choice: .action(2), label: "Play/Pause"),
                .init(choice: .action(8), label: "Skip Back"),
                .init(choice: .action(9), label: "Skip Forward"),
                .init(choice: .action(11), label: "Voice Assistant"),
                .init(choice: .action(1), label: "Off"),
            ]),
            GestureSlot(key: "tripleTap", label: "Triple Tap", type: 3, actions: [
                .init(choice: .action(8), label: "Skip Back"),
                .init(choice: .action(9), label: "Skip Forward"),
                .init(choice: .action(11), label: "Voice Assistant"),
                .init(choice: .action(1), label: "Off"),
            ]),
            GestureSlot(key: "tapHold", label: "Tap and Hold", type: 7, actions: [
                .init(choice: .noiseControl, label: "Noise Control"),
                .init(choice: .action(11), label: "Voice Assistant"),
                .init(choice: .action(1), label: "Off"),
            ]),
            GestureSlot(key: "doubleTapHold", label: "Double Tap and Hold", type: 9, actions: [
                .init(choice: .action(18), label: "Volume Up"),
                .init(choice: .action(19), label: "Volume Down"),
                .init(choice: .action(11), label: "Voice Assistant"),
                .init(choice: .action(1), label: "Off"),
            ]),
        ]
    )
}

// MARK: - Models

public struct Capabilities: Equatable {
    public var transparency: Bool
    /// [.low, .mid, .high], [.low, .high] or []
    public var strengths: [AncStrength]
    public var adaptive: Bool
    /// 5, 3 (lowest step is off) or 0 (no Bass Enhance)
    public var bassSteps: Int
    public var inEar: Bool
    public var lowLatency: Bool
    public var ring: RingStyle
    public var eq: EqCapabilities
    public var spatialModes: [SpatialMode]
    public var dualConnection: Bool
    /// Switching dual connection restarts the earbuds.
    public var dualRestarts: Bool
    public var personalSound: PersonalSoundBackend?
    public var gestures: GestureCapabilities?
    /// Ear tip fit test (support list from nikiomori/nothing-x-macos).
    public var earTipTest: Bool

    /// Levels the UI offers while Bass Enhance is on.
    public var bassLevels: [Int] {
        switch bassSteps {
        case 3: return [1, 2]
        case 5: return [1, 2, 3, 4, 5]
        default: return []
        }
    }

    /// Before a device connects.
    public static let none = Capabilities(
        transparency: true, strengths: [], adaptive: false, bassSteps: 0, inEar: false,
        lowLatency: false, ring: .buds,
        eq: EqCapabilities(style: .eq, presets: [], customId: nil, trebleHz: 3400),
        spatialModes: [], dualConnection: false, dualRestarts: false, personalSound: nil, gestures: nil, earTipTest: false
    )

    public static func forDeviceName(_ name: String) -> Capabilities {
        ModelSpec.forName(name).capabilities
    }

    /// True when the name matches a known model rather than the fallback.
    public static func isRecognized(_ name: String) -> Bool {
        let lower = name.lowercased()
        return ModelSpec.all.contains { lower.contains($0.name.lowercased()) }
    }

    /// A known model, or a name that says Nothing or CMF.
    public static func looksLikeEarbuds(_ name: String) -> Bool {
        let lower = name.lowercased()
        return isRecognized(name) || lower.contains("nothing") || lower.contains("cmf")
    }
}

public enum PersonalSoundBackend {
    case mimi, audiodo
}

struct ModelSpec {
    enum Dual { case yes, restart, none }

    let name: String
    /// Noise-control capability bits.
    let anc: Int
    let bass: Int
    let inEar: Bool
    let ring: RingStyle
    let eq: EqProfile
    let treble: Int
    /// Spatial audio capability mask; 0 = none.
    let spatial: Int
    let dual: Dual
    let sound: PersonalSoundBackend?
    let gestures: GestureCapabilities?

    static let earTipModels: Set<String> = [
        "Ear (2)", "Nothing Ear", "Nothing Ear (a)", "Nothing Ear (3)",
        "CMF Buds Pro 2", "CMF Buds 2", "CMF Buds 2 Plus",
    ]

    static let full = 63
    static let strengthMid = 0x02 // adds Mid (Low / Mid / High)
    static let strengthBase = 0x04 // Low / High
    static let adaptiveBit = 0x08
    static let transparencyBit = 0x10

    var capabilities: Capabilities {
        let hasBase = anc & Self.strengthBase != 0
        let hasMid = anc & Self.strengthMid != 0
        let strengths: [AncStrength] = hasBase ? (hasMid ? [.low, .mid, .high] : [.low, .high]) : []
        return Capabilities(
            transparency: anc & Self.transparencyBit != 0,
            strengths: strengths,
            adaptive: hasBase && anc & Self.adaptiveBit != 0,
            bassSteps: bass,
            inEar: inEar,
            lowLatency: true, // every model ear-web supports has it
            ring: ring,
            eq: eq.capabilities(trebleHz: treble),
            spatialModes: SpatialMode.modes(forMask: spatial),
            dualConnection: dual != .none,
            dualRestarts: dual == .restart,
            personalSound: sound,
            gestures: gestures,
            earTipTest: Self.earTipModels.contains(name)
        )
    }

    // Some names cover two hardware revisions (e.g. CMF Buds 2 / Buds Pro 2 come in
    // 5-level and 3-step bass versions); the device layer corrects bass from the
    // first report.
    static let all: [ModelSpec] = [
        .init(name: "Nothing Headphone (1) Pro", anc: full, bass: 0, inEar: true, ring: .headphone, eq: .nothing, treble: 3500, spatial: 7, dual: .yes, sound: .audiodo, gestures: nil),
        .init(name: "Nothing Headphone (1)", anc: full, bass: 5, inEar: true, ring: .headphone, eq: .nothing, treble: 3500, spatial: 7, dual: .yes, sound: .audiodo, gestures: nil),
        .init(name: "Nothing Headphone (a)", anc: full, bass: 3, inEar: false, ring: .headphone, eq: .nothing, treble: 3500, spatial: 28, dual: .yes, sound: nil, gestures: nil),
        .init(name: "Nothing Ear (open)", anc: full, bass: 0, inEar: false, ring: .buds, eq: .nothing, treble: 3400, spatial: 0, dual: .yes, sound: nil, gestures: nil),
        .init(name: "CMF Headphone Pro", anc: full, bass: 0, inEar: false, ring: .headphone, eq: .cmfNoDirac, treble: 3500, spatial: 28, dual: .yes, sound: .audiodo, gestures: nil),
        .init(name: "CMF Buds 2 Plus", anc: full, bass: 5, inEar: true, ring: .buds, eq: .cmfNoDirac, treble: 6900, spatial: 6, dual: .yes, sound: .audiodo, gestures: .cmfTap),
        .init(name: "CMF Buds Pro 2", anc: full, bass: 5, inEar: true, ring: .buds, eq: .cmf, treble: 6900, spatial: 6, dual: .restart, sound: nil, gestures: .cmfTap),
        .init(name: "Nothing Ear (3a)", anc: full, bass: 0, inEar: true, ring: .buds, eq: .nothing, treble: 3400, spatial: 6, dual: .yes, sound: nil, gestures: nil),
        .init(name: "Nothing Ear (a)", anc: full, bass: 5, inEar: true, ring: .buds, eq: .nothing, treble: 3400, spatial: 0, dual: .yes, sound: nil, gestures: nil),
        .init(name: "Nothing Ear (3)", anc: full, bass: 5, inEar: true, ring: .buds, eq: .nothing, treble: 3400, spatial: 6, dual: .yes, sound: .audiodo, gestures: nil),
        .init(name: "Nothing ear (1)", anc: 53, bass: 0, inEar: true, ring: .single, eq: .nothingNoCustom, treble: 3400, spatial: 0, dual: .none, sound: nil, gestures: nil),
        .init(name: "CMF Clip Pro", anc: full, bass: 3, inEar: false, ring: .buds, eq: .cmfNoDirac, treble: 3400, spatial: 6, dual: .yes, sound: nil, gestures: nil),
        .init(name: "Neckband Pro", anc: full, bass: 5, inEar: false, ring: .headphone, eq: .nothing, treble: 6900, spatial: 6, dual: .restart, sound: nil, gestures: nil),
        .init(name: "Ear (Stick)", anc: 33, bass: 0, inEar: true, ring: .buds, eq: .nothing, treble: 3500, spatial: 0, dual: .none, sound: nil, gestures: nil),
        .init(name: "CMF Buds 2a", anc: 49, bass: 5, inEar: false, ring: .buds, eq: .cmfDirac7, treble: 6900, spatial: 0, dual: .yes, sound: nil, gestures: nil),
        .init(name: "CMF Buds 2", anc: full, bass: 5, inEar: true, ring: .buds, eq: .cmf, treble: 6900, spatial: 6, dual: .yes, sound: nil, gestures: .cmfTap),
        .init(name: "Nothing Ear", anc: full, bass: 5, inEar: true, ring: .buds, eq: .nothing, treble: 3400, spatial: 0, dual: .yes, sound: .mimi, gestures: nil),
        .init(name: "CMF Buds", anc: 49, bass: 5, inEar: true, ring: .buds, eq: .cmf, treble: 6900, spatial: 0, dual: .restart, sound: nil, gestures: nil),
        .init(name: "Buds Pro", anc: 55, bass: 0, inEar: true, ring: .buds, eq: .nothing, treble: 3400, spatial: 0, dual: .none, sound: nil, gestures: nil),
        .init(name: "Ear (2)", anc: full, bass: 0, inEar: true, ring: .buds, eq: .nothing, treble: 3400, spatial: 0, dual: .restart, sound: .mimi, gestures: nil),
    ].sorted { $0.name.count > $1.name.count } // longest first: "CMF Buds 2 Plus" before "CMF Buds"

    /// Unknown or renamed device: assume what current earbuds support.
    static let fallback = ModelSpec(name: "", anc: full, bass: 5, inEar: true, ring: .buds, eq: .nothing, treble: 3400, spatial: 0, dual: .yes, sound: nil, gestures: nil)

    static func forName(_ name: String) -> ModelSpec {
        let lower = name.lowercased()
        return all.first { lower.contains($0.name.lowercased()) } ?? fallback
    }
}

// Command ids and payload codecs. Values referenced from ear-web.

import Foundation

public enum Command {
    public static let getBattery: UInt16 = 0xC007
    public static let getNoiseMode: UInt16 = 0xC01E
    public static let setNoiseMode: UInt16 = 0xF00F
    public static let getBass: UInt16 = 0xC04E
    public static let setBass: UInt16 = 0xF051
    public static let getInEar: UInt16 = 0xC00E
    public static let setInEar: UInt16 = 0xF004
    public static let getLowLatency: UInt16 = 0xC041
    public static let setLowLatency: UInt16 = 0xF040
    public static let getFirmware: UInt16 = 0xC042
    public static let ring: UInt16 = 0xF002
    // Equalizer presets: Nothing models use "EQ", CMF models "listening mode".
    public static let getEq: UInt16 = 0xC01F
    public static let setEq: UInt16 = 0xF010
    public static let getListeningMode: UInt16 = 0xC050
    public static let setListeningMode: UInt16 = 0xF01D
    public static let getCustomEq: UInt16 = 0xC044
    public static let setCustomEq: UInt16 = 0xF041
    public static let getSpatialAudio: UInt16 = 0xC04F
    public static let setSpatialAudio: UInt16 = 0xF052
    public static let getDualEnable: UInt16 = 0xC027
    public static let setDualEnable: UInt16 = 0xF01A
    public static let getDualList: UInt16 = 0xC028
    public static let setDualConnect: UInt16 = 0xF01B
    // Personal Sound Profile: Mimi (older Nothing models) or Audiodo (newer ones)
    public static let getMimi: UInt16 = 0xC022
    public static let setMimi: UInt16 = 0xF015
    public static let getAudiodo: UInt16 = 0xC05A
    public static let setAudiodo: UInt16 = 0xF05C
    public static let getGestures: UInt16 = 0xC018
    public static let setGesture: UInt16 = 0xF003
    // From nikiomori/nothing-x-macos: serial number and ear tip fit test.
    public static let getSerial: UInt16 = 0xC006
    public static let startEarTipTest: UInt16 = 0xF014
}

/// Frames the earbuds send back (replies and unsolicited updates).
public enum Response {
    public static let battery: Set<UInt16> = [0x4007, 0xE001]
    public static let noiseMode: Set<UInt16> = [0x401E, 0xE003, 0x6003]
    public static let bass: Set<UInt16> = [0x404E]
    public static let inEar: Set<UInt16> = [0x400E]
    public static let lowLatency: Set<UInt16> = [0x4041]
    public static let firmware: Set<UInt16> = [0x4042]
    public static let eqPreset: Set<UInt16> = [0x401F, 0x4050]
    public static let customEq: Set<UInt16> = [0x4044]
    public static let spatialAudio: Set<UInt16> = [0x404F]
    public static let dualEnable: Set<UInt16> = [0x4027]
    public static let dualList: Set<UInt16> = [0x4028]
    public static let dualDeviceEvent: Set<UInt16> = [0xE00E]
    public static let mimi: Set<UInt16> = [0x4022]
    public static let audiodo: Set<UInt16> = [0x405A, 0xE019, 0x6019]
    public static let gestures: Set<UInt16> = [0x4018]
    public static let serial: Set<UInt16> = [0x4006]
    public static let earTipResult: Set<UInt16> = [0xE00D, 0x600D]
}

@inline(__always) func at(_ p: [UInt8], _ i: Int) -> UInt8? { i >= 0 && i < p.count ? p[i] : nil }

// MARK: - Battery

public struct BatteryLevel: Equatable {
    public var level: Int
    public var charging: Bool
    public init(level: Int, charging: Bool) {
        self.level = level
        self.charging = charging
    }
}

public struct Battery: Equatable {
    public var left: BatteryLevel?
    public var right: BatteryLevel?
    public var `case`: BatteryLevel?
    public var stereo: BatteryLevel?
    public init() {}
}

public enum Codec {
    /// payload: [count, (partId, level|charging) × count]. Parts not listed come back nil.
    public static func decodeBattery(_ p: [UInt8]) -> Battery {
        var battery = Battery()
        let count = Int(at(p, 0) ?? 0)
        for i in 0..<count {
            guard let part = at(p, 1 + i * 2), let raw = at(p, 2 + i * 2) else { continue }
            let value = BatteryLevel(level: Int(raw & 0x7F), charging: raw & 0x80 != 0)
            switch part {
            case 0x02: battery.left = value
            case 0x03: battery.right = value
            case 0x04: battery.case = value
            case 0x06: battery.stereo = value
            default: break
            }
        }
        return battery
    }

    // MARK: Noise control

    /// One wire code covers both the mode and, for noise cancellation, its strength.
    static let noiseCodes: [(code: UInt8, mode: NoiseMode, strength: AncStrength?)] = [
        (0x01, .anc, .high),
        (0x02, .anc, .mid),
        (0x03, .anc, .low),
        (0x04, .anc, .adaptive),
        (0x05, .off, nil),
        (0x07, .transparency, nil),
    ]

    /// payload: [?, code, ...]
    public static func decodeNoiseMode(_ p: [UInt8]) -> NoiseSetting? {
        guard let code = at(p, 1), let e = noiseCodes.first(where: { $0.code == code }) else { return nil }
        return NoiseSetting(mode: e.mode, strength: e.strength)
    }

    /// strength only matters for .anc; it defaults to high.
    public static func encodeNoiseMode(_ mode: NoiseMode, strength: AncStrength? = .high) -> [UInt8] {
        let wanted = strength ?? .high
        let e = noiseCodes.first { $0.mode == mode && (mode != .anc || $0.strength == wanted) }
        return [0x01, e?.code ?? 0x05, 0x00]
    }

    // MARK: Bass enhance

    /// Most models use 5 levels sent as level×2 (2..10). A few use 3 steps sent as
    /// 0 / 5 / 10 where step 0 means off; those become off + levels 1..2.
    static let threeStepWire: [UInt8] = [0, 5, 10]

    /// payload: [enabled, wireLevel]. level is nil if it doesn't fit the model.
    public static func decodeBass(_ p: [UInt8], steps: Int) -> (enabled: Bool, level: Int?) {
        let enabled = at(p, 0) == 1
        let wire = at(p, 1) ?? 0
        let level: Int?
        if steps == 3 {
            let index = threeStepWire.firstIndex(of: wire) ?? -1
            level = index > 0 ? index : nil
        } else {
            level = (2...10).contains(wire) && wire % 2 == 0 ? Int(wire) / 2 : nil
        }
        return (enabled, level)
    }

    public static func encodeBass(enabled: Bool, level: Int, steps: Int) -> [UInt8] {
        let wire: UInt8
        if steps == 3 {
            let index = enabled ? level : 0
            wire = threeStepWire.indices.contains(index) ? threeStepWire[index] : 0
        } else {
            wire = UInt8(clamping: level * 2)
        }
        return [enabled ? 0x01 : 0x00, wire]
    }

    // MARK: Quick settings

    /// In-ear detection. payload: [?, ?, on]
    public static func decodeInEar(_ p: [UInt8]) -> Bool { at(p, 2) == 1 }
    public static func encodeInEar(_ on: Bool) -> [UInt8] { [0x01, 0x01, on ? 0x01 : 0x00] }

    /// Low latency mode. payload: [1 = on, 2 = off]
    public static func decodeLowLatency(_ p: [UInt8]) -> Bool { at(p, 0) == 1 }
    public static func encodeLowLatency(_ on: Bool) -> [UInt8] { [on ? 0x01 : 0x02, 0x00] }

    /// Personal Sound Profile (Mimi or Audiodo). payload: [on]
    public static func decodePersonalSound(_ p: [UInt8]) -> Bool { at(p, 0) == 1 }
    public static func encodePersonalSound(_ on: Bool) -> [UInt8] { [on ? 0x01 : 0x00] }

    /// Firmware version as ASCII, e.g. "1.0.3.124".
    public static func decodeFirmware(_ p: [UInt8]) -> String? {
        let text = String(decoding: p.filter { $0 != 0 }, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Find my earbuds. side: .left/.right for buds; ignored for other styles.
    public static func encodeRing(style: RingStyle, side: RingTarget, on: Bool) -> [UInt8] {
        let flag: UInt8 = on ? 0x01 : 0x00
        switch style {
        case .single: return [flag]
        case .headphone: return [0x06, flag]
        case .buds: return [side == .left ? 0x02 : 0x03, flag]
        }
    }

    /// Device info as text lines "device,type,value"; type 4 is the serial number.
    public static func decodeSerial(_ p: [UInt8]) -> String? {
        let text = String(decoding: p.filter { $0 != 0 }, as: UTF8.self)
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count == 3, Int(parts[1]) == 4 else { continue }
            let value = parts[2].trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// Ear tip fit test result. payload: [left, right]; 0 good seal, 1 poor seal, else not in ear.
    public static func decodeEarTipResult(_ p: [UInt8]) -> (left: EarTipFit, right: EarTipFit) {
        func fit(_ v: UInt8?) -> EarTipFit {
            switch v {
            case 0: return .good
            case 1: return .poor
            default: return .notInEar
            }
        }
        return (fit(at(p, 0)), fit(at(p, 1)))
    }

    // MARK: Equalizer

    public static func decodePreset(_ p: [UInt8]) -> Int? { at(p, 0).map(Int.init) }
    public static func encodePreset(_ id: Int) -> [UInt8] { [UInt8(clamping: id), 0x00] }

    // Custom EQ: three filters, gains in dB (−6..+6), floats little-endian.
    //   payload: [count, totalGain f32, (type u8, gain f32, freq f32, q f32) × count, 3 zero bytes × count]
    // Filter types: 0 low shelf (Bass), 1 peak (Mid), 2 high shelf (Treble).
    static let bandBytes = 13

    public static func decodeCustomEq(_ p: [UInt8]) -> CustomEq {
        var bands = CustomEq()
        let count = Int(at(p, 0) ?? 0)
        for i in 0..<count {
            let start = 5 + i * bandBytes
            guard start + 5 <= p.count else { break }
            let gain = Int(readFloatLE(p, start + 1).rounded())
            switch p[start] {
            case 0: bands.bass = gain
            case 1: bands.mid = gain
            case 2: bands.treble = gain
            default: break
            }
        }
        return bands
    }

    /// trebleHz differs per model (3400, 3500 or 6900 Hz).
    public static func encodeCustomEq(_ eq: CustomEq, trebleHz: Int) -> [UInt8] {
        let bands: [(type: UInt8, gain: Float, freq: Float, q: Float)] = [
            (1, Float(eq.mid), 980, 0.7),
            (2, Float(eq.treble), Float(trebleHz), 1.0),
            (0, Float(eq.bass), 140, 0.8),
        ]
        // Overall gain is lowered by the largest boost so the result doesn't clip.
        let totalGain = -max(0, bands.map(\.gain).max() ?? 0)

        var out: [UInt8] = [UInt8(bands.count)]
        out += floatLE(totalGain)
        for b in bands {
            out.append(b.type)
            out += floatLE(b.gain) + floatLE(b.freq) + floatLE(b.q)
        }
        out += [UInt8](repeating: 0, count: bands.count * 3)
        return out
    }

    // MARK: Spatial audio

    /// payload: [mode, head]
    public static func decodeSpatialAudio(_ p: [UInt8]) -> SpatialMode {
        let mode = at(p, 0) ?? 0
        let head = at(p, 1) ?? 0
        if head == 1 { return .headTracked }
        return SpatialMode.allCases.first { $0.wire.head == 0 && $0.wire.mode == mode } ?? .off
    }

    public static func encodeSpatialAudio(_ mode: SpatialMode) -> [UInt8] { [mode.wire.mode, mode.wire.head] }

    // MARK: Dual connection

    public static func macString(_ bytes: ArraySlice<UInt8>) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: "-")
    }

    public static func macBytes(_ mac: String) -> [UInt8] {
        mac.split(whereSeparator: { $0 == "-" || $0 == ":" }).compactMap { UInt8($0, radix: 16) }
    }

    public static func decodeDualEnable(_ p: [UInt8]) -> Bool { at(p, 0) == 1 }
    public static func encodeDualEnable(_ on: Bool) -> [UInt8] { [on ? 0x01 : 0x00] }

    /// Remembered devices, one page per request.
    ///   payload: [?, ?, count, (flags, mac×6, nameLength, name…) × count]
    ///   flags: high nibble set = this device (the Mac), low nibble set = connected
    public static func decodeDualList(_ p: [UInt8]) -> [DualDevice] {
        var devices: [DualDevice] = []
        let count = Int(at(p, 2) ?? 0)
        var i = 3
        for _ in 0..<count {
            guard i + 8 <= p.count else { break }
            let flags = p[i]
            let nameLength = Int(p[i + 7] & 0x7F)
            let nameEnd = min(i + 8 + nameLength, p.count)
            devices.append(DualDevice(
                mac: macString(p[(i + 1)..<(i + 7)]),
                name: String(decoding: p[(i + 8)..<nameEnd], as: UTF8.self),
                isSelf: flags & 0xF0 != 0,
                isConnected: flags & 0x0F != 0
            ))
            i += 8 + nameLength
        }
        return devices
    }

    public static func encodeDualListRequest(start: Int) -> [UInt8] { [UInt8(truncatingIfNeeded: start)] }

    /// payload: [connected, mac×6]
    public static func decodeDualDeviceEvent(_ p: [UInt8]) -> (mac: String, isConnected: Bool) {
        let end = min(7, p.count)
        return (macString(p.count > 1 ? p[1..<end] : []), at(p, 0) == 1)
    }

    public static func encodeDualConnect(mac: String, connect: Bool) -> [UInt8] {
        [connect ? 0x01 : 0x00] + macBytes(mac)
    }

    // MARK: Gestures

    /// payload: [count, (device, button, gestureType, action) × count]
    public static func decodeGestures(_ p: [UInt8]) -> [GestureRecord] {
        var records: [GestureRecord] = []
        let count = Int(at(p, 0) ?? 0)
        for i in 0..<count {
            let s = 1 + i * 4
            guard s + 3 < p.count else { break }
            records.append(GestureRecord(device: p[s], button: p[s + 1], type: p[s + 2], action: p[s + 3]))
        }
        return records
    }

    /// One gesture: [1, device, button, gestureType, action]
    public static func encodeGesture(device: UInt8, type: UInt8, action: UInt8, button: UInt8 = 0x01) -> [UInt8] {
        [0x01, device, button, type, action]
    }

    // MARK: Float helpers

    static func floatLE(_ value: Float) -> [UInt8] {
        let bits = value.bitPattern
        return [UInt8(bits & 0xFF), UInt8((bits >> 8) & 0xFF), UInt8((bits >> 16) & 0xFF), UInt8(bits >> 24)]
    }

    static func readFloatLE(_ p: [UInt8], _ i: Int) -> Float {
        guard i + 4 <= p.count else { return 0 }
        let bits = UInt32(p[i]) | UInt32(p[i + 1]) << 8 | UInt32(p[i + 2]) << 16 | UInt32(p[i + 3]) << 24
        return Float(bitPattern: bits)
    }
}

// MARK: - Value types

public enum NoiseMode: String, CaseIterable {
    case anc, transparency, off
}

public enum AncStrength: String, CaseIterable {
    case low, mid, high, adaptive
}

public struct NoiseSetting: Equatable {
    public var mode: NoiseMode
    public var strength: AncStrength?
    public init(mode: NoiseMode, strength: AncStrength?) {
        self.mode = mode
        self.strength = strength
    }
}

public struct CustomEq: Equatable {
    public var bass = 0
    public var mid = 0
    public var treble = 0
    public init(bass: Int = 0, mid: Int = 0, treble: Int = 0) {
        self.bass = bass
        self.mid = mid
        self.treble = treble
    }
}

public enum SpatialMode: String, CaseIterable, Identifiable {
    case off, headTracked, fixed, concert, theatre, game

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .off: return "Off"
        case .headTracked: return "Head Tracked"
        case .fixed: return "Fixed"
        case .concert: return "Concert"
        case .theatre: return "Theatre"
        case .game: return "Game"
        }
    }

    /// Flag in a model's spatial capability mask; nil = always available (Off).
    var bit: Int? {
        switch self {
        case .off: return nil
        case .headTracked: return 0x01
        case .fixed: return 0x02
        case .concert: return 0x08
        case .theatre: return 0x10
        case .game: return 0x20
        }
    }

    var wire: (mode: UInt8, head: UInt8) {
        switch self {
        case .off: return (0, 0)
        case .headTracked: return (1, 1)
        case .fixed: return (1, 0)
        case .concert: return (2, 0)
        case .theatre: return (3, 0)
        case .game: return (4, 0)
        }
    }

    /// Modes a model supports, from its capability mask. [] = no spatial audio.
    public static func modes(forMask mask: Int) -> [SpatialMode] {
        guard mask != 0 else { return [] }
        return allCases.filter { m in m.bit.map { mask & $0 != 0 } ?? true }
    }
}

public struct DualDevice: Equatable, Identifiable {
    public var mac: String
    public var name: String
    public var isSelf: Bool
    public var isConnected: Bool
    public var id: String { mac }
    public init(mac: String, name: String, isSelf: Bool, isConnected: Bool) {
        self.mac = mac
        self.name = name
        self.isSelf = isSelf
        self.isConnected = isConnected
    }
}

public struct GestureRecord: Equatable {
    public var device: UInt8
    public var button: UInt8
    public var type: UInt8
    public var action: UInt8
    public init(device: UInt8, button: UInt8, type: UInt8, action: UInt8) {
        self.device = device
        self.button = button
        self.type = type
        self.action = action
    }
}

public enum RingStyle: String {
    /// left/right separately
    case buds
    /// one sound for the whole device
    case headphone
    /// Nothing ear (1)
    case single
}

public enum EarTipFit: Equatable {
    case good, poor, notInEar
}

public enum RingTarget: String {
    case left, right, all
}

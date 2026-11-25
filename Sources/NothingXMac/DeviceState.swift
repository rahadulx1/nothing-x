// Snapshot of everything the panel shows about the connected earbuds.

import NothingKit

struct BassValue: Equatable {
    var enabled: Bool
    var level: Int
}

enum QuickSetting: Hashable {
    case inEar, lowLatency, personalSound, spatial
}

struct QuickState: Equatable {
    var inEar: Bool?
    var lowLatency: Bool?
    var personalSound: Bool?
    var spatial: SpatialMode?
    var pending: Set<QuickSetting> = []
    var firmware: String?
    var serial: String?
    /// While a find sound is playing.
    var ringing: RingTarget?
}

struct EqState: Equatable {
    var preset: Int?
    var pending = false
    var custom: CustomEq?
}

struct DualState: Equatable {
    var enabled: Bool?
    var pending = false
    var devices: [DualDevice] = []
    /// Device currently being connected/disconnected.
    var busyMac: String?
    let maxConnected = 2

    var connectedCount: Int { devices.filter(\.isConnected).count }
}

struct GestureState: Equatable {
    /// side -> slot key -> raw action code
    var values: [GestureSide: [String: UInt8]] = [:]
    /// "left.doubleTap" etc. while a change is unconfirmed
    var pending: Set<String> = []

    func code(_ side: GestureSide, _ slot: String) -> UInt8? { values[side]?[slot] }
}

enum EarTipTestState: Equatable {
    case idle
    case running
    case finished(left: EarTipFit, right: EarTipFit)
    case failed
}

struct DeviceState: Equatable {
    var connected = false
    /// Earbuds the control channel is being opened to (before `connected`).
    var connecting: String?
    var name: String?
    var address: String?
    var battery = Battery()
    var noiseMode: NoiseMode?
    /// While noiseMode is .anc.
    var ancStrength: AncStrength?
    var noisePending = false
    /// nil if unknown or unsupported.
    var bass: BassValue?
    var bassPending = false
    var quick = QuickState()
    var eq = EqState()
    var dual = DualState()
    var gestures = GestureState()
    var earTip = EarTipTestState.idle
    var capabilities = Capabilities.none
    /// False for a model missing from the capability table (fallback features).
    var recognized = true
}

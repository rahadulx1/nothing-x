// High-level earbud state and every setting the panel can change.
//
// Setters ignore requests while a previous change of the same kind is still in
// flight, so rapid clicks can't queue up commands on the earbuds. Runs on the
// main thread (IOBluetooth delivers its callbacks there).

import Foundation
import NothingKit

final class EarbudsController: ObservableObject {
    @Published private(set) var state = DeviceState()
    /// Paired Nothing/CMF earbuds that aren't connected, for the "not connected" page.
    @Published private(set) var paired: [BluetoothTransport.PairedEarbuds] = []
    /// Address of a paired device we're bringing up the Bluetooth link to.
    @Published private(set) var linking: String?

    private static let batteryPoll: TimeInterval = 60
    private static let queryGap: TimeInterval = 0.15
    private static let customEqSendDelay: TimeInterval = 0.12
    private static let localCustomWins: TimeInterval = 1
    private static let ringAutoStop: TimeInterval = 30
    private static let dualConnectTimeout: TimeInterval = 15
    private static let maxDualListPages = 20
    private static let gestureReadBack: TimeInterval = 0.4
    private static let gesturePendingTimeout: TimeInterval = 4
    private static let earTipTimeout: TimeInterval = 15

    private let transport = BluetoothTransport()
    private var parser = FrameParser()
    private var operationId: UInt8 = 0
    /// Strength to use when noise cancellation is turned back on.
    private var lastAncStrength: AncStrength = .high

    private let startupReads = TimerBag()
    private var batteryTimer: Timer?
    private let customEqTimer = Delayed()
    private var lastLocalCustomAt = Date.distantPast
    private let ringTimer = Delayed()
    private let dualBusyTimer = Delayed()
    private var dualPagesRequested = 0
    private let gestureReadTimer = Delayed()
    private let gesturePendingTimer = Delayed()
    private let earTipTimer = Delayed()

    private lazy var noise = ConfirmedSetting<NoiseSetting>(
        read: { [unowned self] in self.send(Command.getNoiseMode) },
        matches: { r, t in r.mode == t.mode && (r.mode != .anc || r.strength == t.strength) },
        onTimeout: { [unowned self] in self.state.noisePending = false }
    )
    private lazy var bassSetting = ConfirmedSetting<BassValue>(
        read: { [unowned self] in self.send(Command.getBass) },
        matches: { r, t in r.enabled == t.enabled && (!t.enabled || r.level == t.level) },
        onTimeout: { [unowned self] in self.state.bassPending = false }
    )
    private lazy var eqConfirm = ConfirmedSetting<Int>(
        read: { [unowned self] in self.send(self.eqCommands.get) },
        onTimeout: { [unowned self] in self.state.eq.pending = false }
    )
    private lazy var dualConfirm = ConfirmedSetting<Bool>(
        read: { [unowned self] in self.send(Command.getDualEnable) },
        onTimeout: { [unowned self] in self.state.dual.pending = false }
    )
    private lazy var spatialConfirm = ConfirmedSetting<SpatialMode>(
        read: { [unowned self] in self.send(Command.getSpatialAudio) },
        onTimeout: { [unowned self] in self.state.quick.pending.remove(.spatial) }
    )
    private var toggleConfirms: [QuickSetting: ConfirmedSetting<Bool>] = [:]

    private var caps: Capabilities { state.capabilities }

    init() {
        for setting in [QuickSetting.inEar, .lowLatency, .personalSound] {
            toggleConfirms[setting] = ConfirmedSetting<Bool>(
                read: { [unowned self] in
                    if let spec = self.toggleSpec(setting) { self.send(spec.get) }
                },
                onTimeout: { [unowned self] in self.state.quick.pending.remove(setting) }
            )
        }
        transport.onConnected = { [unowned self] name, address in self.didConnect(name: name, address: address) }
        transport.onDisconnected = { [unowned self] in self.didDisconnect() }
        transport.onConnecting = { [unowned self] name in
            if !self.state.connected, self.state.connecting != name { self.state.connecting = name }
        }
        transport.onData = { [unowned self] bytes in self.didReceive(bytes) }
    }

    func start() { transport.start() }

    #if DEBUG
    func setSampleState(_ sample: DeviceState) { state = sample }
    func setSamplePaired(_ sample: [BluetoothTransport.PairedEarbuds]) { paired = sample }
    #endif

    func stop() {
        resetTimers()
        transport.stop()
    }

    func refreshPaired() {
        guard !state.connected else { return }
        let found = BluetoothTransport.pairedEarbuds(isEarbuds: Capabilities.looksLikeEarbuds)
        if found != paired { paired = found }
    }

    /// Connect paired earbuds' Bluetooth link; the transport then opens the control channel.
    func connectPaired(_ address: String) {
        guard linking == nil else { return }
        linking = address
        transport.connectPaired(address) { [weak self] ok in
            guard let self else { return }
            self.linking = nil
            if !ok { Log.info("Could not connect \(address)") }
            self.refreshPaired()
        }
    }

    func refreshBattery() {
        if state.connected { send(Command.getBattery) }
    }

    // MARK: - Noise control

    func setNoiseMode(_ mode: NoiseMode) {
        guard state.connected, !noise.pending, mode != state.noiseMode else { return }
        applyNoise(mode, strength: mode == .anc ? usableStrength(lastAncStrength) : nil)
    }

    func setAncStrength(_ strength: AncStrength) {
        guard state.connected, !noise.pending else { return }
        if state.noiseMode == .anc && strength == state.ancStrength { return }
        applyNoise(.anc, strength: usableStrength(strength))
    }

    private func usableStrength(_ strength: AncStrength) -> AncStrength {
        if strength == .adaptive && caps.adaptive { return .adaptive }
        return caps.strengths.contains(strength) ? strength : .high
    }

    private func applyNoise(_ mode: NoiseMode, strength: AncStrength?) {
        send(Command.setNoiseMode, Codec.encodeNoiseMode(mode, strength: strength))
        noise.begin(NoiseSetting(mode: mode, strength: strength))
        setNoiseState(mode, strength)
    }

    private func setNoiseState(_ mode: NoiseMode, _ strength: AncStrength?) {
        if mode == .anc, let strength { lastAncStrength = strength }
        state.noiseMode = mode
        state.ancStrength = mode == .anc ? strength : nil
        state.noisePending = noise.pending
    }

    // MARK: - Bass

    /// Missing fields keep their current value.
    func setBass(enabled: Bool? = nil, level: Int? = nil) {
        guard state.connected, !bassSetting.pending, caps.bassSteps > 0 else { return }
        let levels = caps.bassLevels
        let on = enabled ?? state.bass?.enabled ?? false
        var newLevel = level ?? state.bass?.level ?? levels.first ?? 1
        if !levels.contains(newLevel) { newLevel = levels.first ?? 1 }
        if let bass = state.bass, bass.enabled == on, !on || bass.level == newLevel { return }

        send(Command.setBass, Codec.encodeBass(enabled: on, level: newLevel, steps: caps.bassSteps))
        let value = BassValue(enabled: on, level: newLevel)
        bassSetting.begin(value)
        state.bass = value
        state.bassPending = true
    }

    private func onBassReport(_ payload: [UInt8]) {
        // A wire level of 5 only exists on 3-step models: correct a name-based guess.
        if caps.bassSteps == 5 && payload.count > 1 && payload[1] == 5 {
            state.capabilities.bassSteps = 3
        }
        let report = Codec.decodeBass(payload, steps: caps.bassSteps)
        // Disabled models remember their last level; keep showing it.
        let level = report.level ?? state.bass?.level ?? caps.bassLevels.first ?? 1
        let value = BassValue(enabled: report.enabled, level: level)
        guard bassSetting.accept(value) else { return }
        state.bass = value
        state.bassPending = false
    }

    // MARK: - Quick settings

    private struct ToggleSpec {
        let get: UInt16
        let set: UInt16
        let responses: Set<UInt16>
        let decode: ([UInt8]) -> Bool
        let encode: (Bool) -> [UInt8]
    }

    private func toggleSpec(_ setting: QuickSetting) -> ToggleSpec? {
        switch setting {
        case .inEar where caps.inEar:
            return ToggleSpec(get: Command.getInEar, set: Command.setInEar, responses: Response.inEar,
                              decode: Codec.decodeInEar, encode: Codec.encodeInEar)
        case .lowLatency where caps.lowLatency:
            return ToggleSpec(get: Command.getLowLatency, set: Command.setLowLatency, responses: Response.lowLatency,
                              decode: Codec.decodeLowLatency, encode: Codec.encodeLowLatency)
        case .personalSound:
            switch caps.personalSound {
            case .mimi:
                return ToggleSpec(get: Command.getMimi, set: Command.setMimi, responses: Response.mimi,
                                  decode: Codec.decodePersonalSound, encode: Codec.encodePersonalSound)
            case .audiodo:
                return ToggleSpec(get: Command.getAudiodo, set: Command.setAudiodo, responses: Response.audiodo,
                                  decode: Codec.decodePersonalSound, encode: Codec.encodePersonalSound)
            case nil:
                return nil
            }
        default:
            return nil
        }
    }

    private func quickValue(_ setting: QuickSetting) -> Bool? {
        switch setting {
        case .inEar: return state.quick.inEar
        case .lowLatency: return state.quick.lowLatency
        case .personalSound: return state.quick.personalSound
        case .spatial: return nil
        }
    }

    private func setQuickValue(_ setting: QuickSetting, _ value: Bool) {
        switch setting {
        case .inEar: state.quick.inEar = value
        case .lowLatency: state.quick.lowLatency = value
        case .personalSound: state.quick.personalSound = value
        case .spatial: break
        }
    }

    /// .inEar, .lowLatency or .personalSound
    func setToggle(_ setting: QuickSetting, _ on: Bool) {
        guard state.connected, let spec = toggleSpec(setting), let confirm = toggleConfirms[setting],
              !confirm.pending, quickValue(setting) != on else { return }
        send(spec.set, spec.encode(on))
        confirm.begin(on)
        setQuickValue(setting, on)
        state.quick.pending.insert(setting)
    }

    func setSpatialAudio(_ mode: SpatialMode) {
        guard state.connected, caps.spatialModes.contains(mode), !spatialConfirm.pending,
              state.quick.spatial != mode else { return }
        send(Command.setSpatialAudio, Codec.encodeSpatialAudio(mode))
        spatialConfirm.begin(mode)
        state.quick.spatial = mode
        state.quick.pending.insert(.spatial)
    }

    /// Only one sound at a time; it stops by itself after 30 seconds.
    /// side is ignored for headphone/single styles.
    func ring(_ side: RingTarget, on: Bool) {
        guard state.connected else { return }
        let target: RingTarget = caps.ring == .buds ? side : .all
        if !on { return stopRing() }
        if let ringing = state.quick.ringing, ringing != target { stopRing() }

        send(Command.ring, Codec.encodeRing(style: caps.ring, side: target, on: true))
        ringTimer.schedule(Self.ringAutoStop) { [weak self] in self?.stopRing() }
        state.quick.ringing = target
    }

    private func stopRing() {
        guard let ringing = state.quick.ringing else { return }
        send(Command.ring, Codec.encodeRing(style: caps.ring, side: ringing, on: false))
        ringTimer.cancel()
        state.quick.ringing = nil
    }

    // MARK: - Equalizer

    private var eqCommands: (get: UInt16, set: UInt16) {
        caps.eq.style == .listening
            ? (Command.getListeningMode, Command.setListeningMode)
            : (Command.getEq, Command.setEq)
    }

    func setEqPreset(_ id: Int) {
        guard state.connected, !eqConfirm.pending, id != state.eq.preset,
              caps.eq.presets.contains(where: { $0.id == id }) else { return }
        send(eqCommands.set, Codec.encodePreset(id))
        eqConfirm.begin(id)
        state.eq.preset = id
        state.eq.pending = true
        // Picking Custom: load the saved bands so the sliders show them.
        if id == caps.eq.customId {
            startupReads.after(0.3) { [weak self] in self?.send(Command.getCustomEq) }
        }
    }

    /// Applies immediately in the UI, sends the full set to the earbuds (debounced).
    func setCustomEq(_ bands: CustomEq) {
        guard state.connected, caps.eq.customId != nil else { return }
        let clamp = { (v: Int) in max(-6, min(6, v)) }
        let next = CustomEq(bass: clamp(bands.bass), mid: clamp(bands.mid), treble: clamp(bands.treble))
        state.eq.custom = next
        lastLocalCustomAt = Date()
        let trebleHz = caps.eq.trebleHz
        customEqTimer.schedule(Self.customEqSendDelay) { [weak self] in
            self?.send(Command.setCustomEq, Codec.encodeCustomEq(next, trebleHz: trebleHz))
        }
    }

    // MARK: - Dual connection

    func setDualConnection(_ on: Bool) {
        guard state.connected, caps.dualConnection, !dualConfirm.pending, state.dual.enabled != on else { return }
        send(Command.setDualEnable, Codec.encodeDualEnable(on))
        dualConfirm.begin(on)
        state.dual.enabled = on
        state.dual.pending = true
    }

    /// Connect or disconnect a remembered device. One at a time; this Mac can't
    /// be disconnected from here (that would drop the app's own connection).
    func setDualDevice(_ mac: String, connect: Bool) {
        let dual = state.dual
        guard state.connected, dual.enabled == true, dual.busyMac == nil,
              let device = dual.devices.first(where: { $0.mac == mac }),
              !device.isSelf, device.isConnected != connect else { return }
        if connect && dual.connectedCount >= dual.maxConnected { return }

        send(Command.setDualConnect, Codec.encodeDualConnect(mac: mac, connect: connect))
        dualBusyTimer.schedule(Self.dualConnectTimeout) { [weak self] in
            self?.state.dual.busyMac = nil
            self?.refreshDualList() // show whatever actually happened
        }
        state.dual.busyMac = mac
    }

    private func refreshDualList() {
        dualPagesRequested = 0
        state.dual.devices = []
        requestDualPage(0)
    }

    private func requestDualPage(_ start: Int) {
        dualPagesRequested += 1
        send(Command.getDualList, Codec.encodeDualListRequest(start: start))
    }

    /// Pages may repeat devices; keep requesting while new ones keep arriving.
    private func mergeDualPage(_ page: [DualDevice]) {
        var devices = state.dual.devices
        var added = false
        for device in page {
            if let i = devices.firstIndex(where: { $0.mac == device.mac }) {
                devices[i] = device
            } else {
                devices.append(device)
                added = true
            }
        }
        state.dual.devices = sortDevices(devices)
        if added && !page.isEmpty && dualPagesRequested < Self.maxDualListPages {
            requestDualPage(devices.count)
        }
    }

    private func onDualDeviceEvent(mac: String, isConnected: Bool) {
        guard state.dual.devices.contains(where: { $0.mac == mac }) else {
            refreshDualList() // a device we haven't seen yet
            return
        }
        state.dual.devices = sortDevices(state.dual.devices.map {
            var d = $0
            if d.mac == mac { d.isConnected = isConnected }
            return d
        })
        if state.dual.busyMac == mac {
            dualBusyTimer.cancel()
            state.dual.busyMac = nil
        }
    }

    /// This Mac first, then connected devices, then the rest by name.
    private func sortDevices(_ devices: [DualDevice]) -> [DualDevice] {
        devices.sorted { a, b in
            if a.isSelf != b.isSelf { return a.isSelf }
            if a.isConnected != b.isConnected { return a.isConnected }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - Gestures

    func setGesture(_ side: GestureSide, slot slotKey: String, choice: GestureChoice) {
        guard state.connected, let g = caps.gestures,
              let slot = g.slots.first(where: { $0.key == slotKey }),
              slot.actions.contains(where: { $0.choice == choice }) else { return }
        let current = state.gestures.code(side, slotKey)
        let code: UInt8
        switch choice {
        case .action(let value):
            code = value
        case .noiseControl:
            if GestureCapabilities.isNoiseCode(current) { return } // already Noise Control
            code = GestureCapabilities.defaultNoiseCode
        }
        if code == current { return }
        writeGesture(side, slot, code)
    }

    /// Only for a slot that's set to Noise Control. At least two modes must be on.
    func setGestureNoiseCycle(_ side: GestureSide, slot slotKey: String, cycle: NoiseCycle) {
        guard state.connected, let g = caps.gestures,
              let slot = g.slots.first(where: { $0.key == slotKey }),
              let current = state.gestures.code(side, slotKey), GestureCapabilities.isNoiseCode(current),
              let code = GestureCapabilities.noiseCode(for: cycle), code != current else { return }
        writeGesture(side, slot, code)
    }

    private func writeGesture(_ side: GestureSide, _ slot: GestureSlot, _ code: UInt8) {
        guard let device = caps.gestures?.sides[side] else { return }
        send(Command.setGesture, Codec.encodeGesture(device: device, type: slot.type, action: code))
        state.gestures.values[side, default: [:]][slot.key] = code
        state.gestures.pending.insert("\(side.rawValue).\(slot.key)")
        gestureReadTimer.schedule(Self.gestureReadBack) { [weak self] in self?.send(Command.getGestures) }
        gesturePendingTimer.schedule(Self.gesturePendingTimeout) { [weak self] in
            self?.state.gestures.pending = []
        }
    }

    private func onGestures(_ payload: [UInt8]) {
        guard let g = caps.gestures else { return }
        for record in Codec.decodeGestures(payload) {
            guard let side = g.sides.first(where: { $0.value == record.device })?.key,
                  let slot = g.slots.first(where: { $0.type == record.type }) else { continue }
            state.gestures.values[side, default: [:]][slot.key] = record.action
        }
        gesturePendingTimer.cancel()
        state.gestures.pending = []
    }

    // MARK: - Ear tip fit test

    func startEarTipTest() {
        guard state.connected, caps.earTipTest, state.earTip != .running else { return }
        send(Command.startEarTipTest, [0x01])
        state.earTip = .running
        earTipTimer.schedule(Self.earTipTimeout) { [weak self] in
            if self?.state.earTip == .running { self?.state.earTip = .failed }
        }
    }

    /// Stop waiting for a result (the buds finish their tone on their own).
    func cancelEarTipTest() {
        earTipTimer.cancel()
        state.earTip = .idle
    }

    /// Leaving the page (Back, Esc, closing the panel) ends the test, even
    /// mid-run: otherwise it stays "running" with no timeout and can't restart.
    func resetEarTipTest() {
        earTipTimer.cancel()
        state.earTip = .idle
    }

    // MARK: - Connection

    private func send(_ command: UInt16, _ payload: [UInt8] = []) {
        operationId &+= 1
        let frame = Frame.encode(command: command, payload: payload, operationId: operationId)
        Log.frame("->", frame)
        transport.write(frame)
    }

    private func didConnect(name: String, address: String) {
        parser.reset()
        resetTimers()
        var fresh = DeviceState()
        fresh.connected = true
        fresh.name = name
        fresh.address = address
        fresh.capabilities = Capabilities.forDeviceName(name)
        fresh.recognized = Capabilities.isRecognized(name)
        state = fresh

        // Stagger the first reads so the earbuds aren't flooded.
        var reads: [UInt16] = [Command.getBattery, Command.getNoiseMode]
        if caps.bassSteps > 0 { reads.append(Command.getBass) }
        reads.append(Command.getFirmware)
        reads.append(Command.getSerial)
        for setting in [QuickSetting.inEar, .lowLatency, .personalSound] {
            if let spec = toggleSpec(setting) { reads.append(spec.get) }
        }
        if !caps.spatialModes.isEmpty { reads.append(Command.getSpatialAudio) }
        reads.append(eqCommands.get)
        if caps.eq.customId != nil { reads.append(Command.getCustomEq) }
        if caps.dualConnection { reads.append(Command.getDualEnable) }
        if caps.gestures != nil { reads.append(Command.getGestures) }

        for (i, command) in reads.enumerated() {
            startupReads.after(Double(i) * Self.queryGap) { [weak self] in self?.send(command) }
        }
        if caps.dualConnection {
            startupReads.after(Double(reads.count) * Self.queryGap) { [weak self] in self?.refreshDualList() }
        }

        batteryTimer = Timer.scheduledTimer(withTimeInterval: Self.batteryPoll, repeats: true) { [weak self] _ in
            self?.refreshBattery()
        }
    }

    private func didDisconnect() {
        resetTimers()
        parser.reset()
        if state.connected { state = DeviceState() }
    }

    private func resetTimers() {
        startupReads.cancelAll()
        batteryTimer?.invalidate()
        batteryTimer = nil
        noise.reset()
        bassSetting.reset()
        eqConfirm.reset()
        dualConfirm.reset()
        spatialConfirm.reset()
        toggleConfirms.values.forEach { $0.reset() }
        customEqTimer.cancel()
        ringTimer.cancel()
        dualBusyTimer.cancel()
        dualPagesRequested = 0
        gestureReadTimer.cancel()
        gesturePendingTimer.cancel()
        earTipTimer.cancel()
    }

    private func didReceive(_ bytes: [UInt8]) {
        Log.frame("<-", bytes)
        for frame in parser.push(bytes) { handle(frame) }
    }

    private func handle(_ frame: IncomingFrame) {
        let c = frame.command
        let p = frame.payload

        if Response.battery.contains(c) {
            state.battery = Codec.decodeBattery(p)
        } else if Response.noiseMode.contains(c) {
            if let report = Codec.decodeNoiseMode(p), noise.accept(report) {
                setNoiseState(report.mode, report.strength)
            }
        } else if Response.bass.contains(c) {
            if caps.bassSteps > 0 { onBassReport(p) }
        } else if Response.eqPreset.contains(c) {
            if let preset = Codec.decodePreset(p), eqConfirm.accept(preset) {
                state.eq.preset = preset
                state.eq.pending = false
            }
        } else if Response.customEq.contains(c) {
            // Don't let a read that crossed a slider change undo the user's values.
            if Date().timeIntervalSince(lastLocalCustomAt) > Self.localCustomWins {
                state.eq.custom = Codec.decodeCustomEq(p)
            }
        } else if Response.spatialAudio.contains(c) {
            let mode = Codec.decodeSpatialAudio(p)
            if spatialConfirm.accept(mode) {
                state.quick.spatial = mode
                state.quick.pending.remove(.spatial)
            }
        } else if Response.firmware.contains(c) {
            state.quick.firmware = Codec.decodeFirmware(p)
        } else if Response.serial.contains(c) {
            if let serial = Codec.decodeSerial(p) { state.quick.serial = serial }
        } else if Response.dualEnable.contains(c) {
            let enabled = Codec.decodeDualEnable(p)
            if dualConfirm.accept(enabled) {
                let turnedOn = enabled && state.dual.enabled == false
                state.dual.enabled = enabled
                state.dual.pending = false
                if turnedOn { refreshDualList() }
            }
        } else if Response.dualList.contains(c) {
            mergeDualPage(Codec.decodeDualList(p))
        } else if Response.dualDeviceEvent.contains(c) {
            let event = Codec.decodeDualDeviceEvent(p)
            onDualDeviceEvent(mac: event.mac, isConnected: event.isConnected)
        } else if Response.gestures.contains(c) {
            onGestures(p)
        } else if Response.earTipResult.contains(c) {
            // A late result after Cancel or leaving the page is stale; drop it.
            guard state.earTip == .running else { return }
            earTipTimer.cancel()
            let result = Codec.decodeEarTipResult(p)
            state.earTip = .finished(left: result.left, right: result.right)
        } else {
            for setting in [QuickSetting.inEar, .lowLatency, .personalSound] {
                guard let spec = toggleSpec(setting), spec.responses.contains(c) else { continue }
                let value = spec.decode(p)
                if toggleConfirms[setting]?.accept(value) ?? true {
                    setQuickValue(setting, value)
                    state.quick.pending.remove(setting)
                }
                return
            }
        }
    }
}

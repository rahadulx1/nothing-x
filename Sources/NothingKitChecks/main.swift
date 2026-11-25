// Protocol self-checks: `swift run NothingKitChecks`.
// (XCTest / swift-testing aren't available with only the Command Line Tools.)

import Foundation
import NothingKit

var failures = 0
var passes = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if condition() {
        passes += 1
    } else {
        failures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

func hex(_ s: String) -> [UInt8] {
    var out: [UInt8] = []
    var i = s.startIndex
    while i < s.endIndex {
        let j = s.index(i, offsetBy: 2)
        out.append(UInt8(s[i..<j], radix: 16)!)
        i = j
    }
    return out
}

// CRC-16/MODBUS reference value for "123456789" is 0x4B37.
check(Frame.crc16(Array("123456789".utf8)) == 0x4B37, "crc16 check value")

// Framing round trip.
let frame = Frame.encode(command: Command.getBattery, payload: [], operationId: 7)
check(frame.count == 10, "empty-payload frame is 10 bytes")
check(Array(frame[0..<8]) == [0x55, 0x60, 0x01, 0x07, 0xC0, 0x00, 0x00, 0x07], "header bytes")
var parser = FrameParser()
let parsed = parser.push([0x00, 0x12] + frame) // leading junk is skipped
check(parsed.count == 1 && parsed[0].command == Command.getBattery && parsed[0].operationId == 7, "parse own frame")

// Split delivery.
let withPayload = Frame.encode(command: 0x4007, payload: [3, 0x02, 0x55, 0x03, 0xD0, 0x04, 0x40], operationId: 1)
var split = FrameParser()
check(split.push(Array(withPayload[0..<5])).isEmpty, "partial frame waits")
let rest = split.push(Array(withPayload[5...]))
check(rest.count == 1 && rest[0].payload.count == 7, "frame completes after second chunk")

// Two frames back to back.
var both = FrameParser()
check(both.push(frame + withPayload).count == 2, "two frames in one chunk")

// Battery.
let battery = Codec.decodeBattery(rest[0].payload)
check(battery.left == BatteryLevel(level: 85, charging: false), "left battery")
check(battery.right == BatteryLevel(level: 80, charging: true), "right battery charging bit")
check(battery.case == BatteryLevel(level: 64, charging: false), "case battery")
check(battery.stereo == nil, "stereo missing")

// Noise.
check(Codec.encodeNoiseMode(.anc, strength: .mid) == [0x01, 0x02, 0x00], "encode anc mid")
check(Codec.encodeNoiseMode(.transparency) == [0x01, 0x07, 0x00], "encode transparency")
check(Codec.decodeNoiseMode([0x01, 0x04]) == NoiseSetting(mode: .anc, strength: .adaptive), "decode adaptive")
check(Codec.decodeNoiseMode([0x01, 0x05]) == NoiseSetting(mode: .off, strength: nil), "decode off")
check(Codec.decodeNoiseMode([0x01, 0x09]) == nil, "unknown noise code")

// Bass.
check(Codec.encodeBass(enabled: true, level: 3, steps: 5) == [1, 6], "bass 5-step encode")
check(Codec.encodeBass(enabled: true, level: 2, steps: 3) == [1, 10], "bass 3-step encode")
check(Codec.encodeBass(enabled: false, level: 2, steps: 3) == [0, 0], "bass 3-step off")
check(Codec.decodeBass([1, 8], steps: 5) == (true, 4), "bass decode 5-step")
check(Codec.decodeBass([1, 5], steps: 3) == (true, 1), "bass decode 3-step")
check(Codec.decodeBass([0, 0], steps: 3).level == nil, "bass 3-step zero has no level")

// Custom EQ round trip.
let eq = CustomEq(bass: 4, mid: -2, treble: 6)
let eqPayload = Codec.encodeCustomEq(eq, trebleHz: 6900)
check(eqPayload.count == 1 + 4 + 3 * 13 + 9, "custom EQ payload length")
check(Codec.decodeCustomEq(eqPayload) == eq, "custom EQ round trip")

// Spatial.
check(SpatialMode.modes(forMask: 6) == [.off, .fixed], "CMF Buds 2 Plus spatial: Off/Fixed")
check(SpatialMode.modes(forMask: 0).isEmpty, "no spatial")
for mode in SpatialMode.allCases {
    check(Codec.decodeSpatialAudio(Codec.encodeSpatialAudio(mode)) == mode, "spatial round trip \(mode)")
}

// Dual list.
var dualPayload: [UInt8] = [0, 0, 2]
dualPayload.append(0x11)
dualPayload += hex("AABBCCDDEEFF")
dualPayload.append(3)
dualPayload += Array("Mac".utf8)
dualPayload.append(0x00)
dualPayload += hex("010203040506")
dualPayload.append(5)
dualPayload += Array("Pixel".utf8)
let devices = Codec.decodeDualList(dualPayload)
check(devices.count == 2, "dual list count")
check(devices[0] == DualDevice(mac: "AA-BB-CC-DD-EE-FF", name: "Mac", isSelf: true, isConnected: true), "dual self")
check(devices[1] == DualDevice(mac: "01-02-03-04-05-06", name: "Pixel", isSelf: false, isConnected: false), "dual other")
check(Codec.encodeDualConnect(mac: "01-02-03-04-05-06", connect: true) == [1, 1, 2, 3, 4, 5, 6], "dual connect")
let event = Codec.decodeDualDeviceEvent([1] + hex("010203040506"))
check(event.mac == "01-02-03-04-05-06" && event.isConnected, "dual event")

// Gestures.
let gestures = Codec.decodeGestures([2, 2, 1, 2, 9, 3, 1, 7, 22])
check(gestures == [
    GestureRecord(device: 2, button: 1, type: 2, action: 9),
    GestureRecord(device: 3, button: 1, type: 7, action: 22),
], "gesture decode")
check(GestureCapabilities.noiseCode(for: NoiseCycle(anc: true, transparency: false, off: true)) == 21, "noise cycle code")
check(GestureCapabilities.choice(for: 22) == .noiseControl, "noise code maps to Noise Control")

// Models.
let plus = Capabilities.forDeviceName("CMF Buds 2 Plus")
check(plus.gestures != nil && plus.eq.style == .listening && plus.eq.customId == 6, "CMF Buds 2 Plus caps")
check(plus.strengths == [.low, .mid, .high] && plus.adaptive, "CMF Buds 2 Plus ANC strengths")
let buds = Capabilities.forDeviceName("CMF Buds")
check(buds.gestures == nil && buds.dualRestarts, "CMF Buds is not matched as Buds 2 Plus")
let ear1 = Capabilities.forDeviceName("Nothing ear (1)")
check(ear1.ring == .single && ear1.eq.customId == nil && !ear1.dualConnection, "ear (1) caps")
check(Codec.decodeFirmware(Array("1.0.3.124\0\0".utf8)) == "1.0.3.124", "firmware decode")

check(Codec.decodeSerial(Array("2,1,abc\n2,4,SH12345678\n".utf8)) == "SH12345678", "serial decode")
check(Codec.decodeSerial(Array("2,1,abc".utf8)) == nil, "no serial")
let tip = Codec.decodeEarTipResult([0, 1])
check(tip.left == .good && tip.right == .poor, "ear tip result")
check(plus.earTipTest && !ear1.earTipTest, "ear tip support")
check(Response.earTipResult.contains(0xE00D) && Response.earTipResult.contains(0x600D), "ear tip result ids (E00D and 600D)")

// Low battery alerts.
func report(left: Int?, right: Int? = nil, charging: Bool = false) -> Battery {
    var b = Battery()
    b.left = left.map { BatteryLevel(level: $0, charging: charging) }
    b.right = right.map { BatteryLevel(level: $0, charging: charging) }
    return b
}
var lowTracker = LowBatteryTracker()
check(lowTracker.update(report(left: 50)).isEmpty, "no alert above 20%")
check(lowTracker.update(report(left: 20)) == [LowBatteryAlert(part: .left, level: 20, threshold: 20)], "alert at 20%")
check(lowTracker.update(report(left: 19)).isEmpty, "no repeat while draining toward 10%")
check(lowTracker.update(report(left: 21)).isEmpty, "small bounce doesn't re-arm")
check(lowTracker.update(report(left: 10)).map(\.threshold) == [10], "second alert at 10%")
check(lowTracker.update(report(left: 4)).isEmpty, "no repeat below 10%")
check(lowTracker.update(report(left: 4, charging: true)).isEmpty, "no alert while charging")
check(lowTracker.update(report(left: 15)).map(\.threshold) == [20], "re-armed after charging")
check(lowTracker.update(report(left: nil, right: 18)).map(\.part) == [.right], "missing bud ignored, other bud alerts")
var connectLow = LowBatteryTracker()
check(connectLow.update(report(left: 8, right: 9)).map(\.threshold) == [10, 10], "connecting already low alerts once per bud at 10%")
var swapped = LowBatteryTracker()
_ = swapped.update(report(left: 9))
check(swapped.update(report(left: 15)).map(\.threshold) == [20], "recovering 5+ points re-arms (15% after 10% alert)")

// Model recognition (used for the "unrecognised model" banner and the paired list)
check(Capabilities.isRecognized("CMF Buds 2 Plus"), "known model is recognised")
check(!Capabilities.isRecognized("Sony WH-1000XM5"), "other headphones are not recognised")
check(Capabilities.looksLikeEarbuds("Nothing Ear (9)"), "unknown Nothing model still looks like earbuds")
check(!Capabilities.looksLikeEarbuds("AirPods Pro"), "AirPods are not Nothing earbuds")

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)

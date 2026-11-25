// Bluetooth transport: finds a connected, paired earbud that exposes the Nothing
// control service, opens an RFCOMM channel to it and relays raw bytes.
// It knows nothing about the earbud protocol; that lives in NothingKit.
//
// All IOBluetooth callbacks arrive on the main run loop, so this class (and
// everything it calls) runs on the main thread.

import Foundation
import IOBluetooth

final class BluetoothTransport: NSObject, IOBluetoothRFCOMMChannelDelegate {
    var onConnected: ((_ name: String, _ address: String) -> Void)?
    var onData: (([UInt8]) -> Void)?
    var onDisconnected: (() -> Void)?
    /// Name of the earbuds the channel is being opened to, or nil when there are none.
    var onConnecting: ((String?) -> Void)?

    /// Nothing / CMF control service (SPP over RFCOMM).
    private static let serviceUUIDBytes: [UInt8] = [
        0xAE, 0xAC, 0x4A, 0x03, 0xDF, 0xF5, 0x49, 0x8F,
        0x84, 0x3A, 0x34, 0x48, 0x7C, 0xF1, 0x33, 0xEB,
    ]
    private static let scanInterval: TimeInterval = 3
    private static let openTimeout: TimeInterval = 10

    private let serviceUUID: IOBluetoothSDPUUID = {
        var bytes = BluetoothTransport.serviceUUIDBytes
        return IOBluetoothSDPUUID(bytes: &bytes, length: bytes.count)
    }()

    private var channel: IOBluetoothRFCOMMChannel?
    private var opening: (channel: IOBluetoothRFCOMMChannel?, device: IOBluetoothDevice, startedAt: Date)?
    private var scanTimer: Timer?
    private var sdpRequested = Set<String>()
    private var openFailures: [String: Int] = [:]
    private var linkResetDone = Set<String>()
    private var stopped = true

    var isConnected: Bool { channel != nil }

    func start() {
        guard stopped else { return }
        stopped = false
        scan()
        scanTimer = Timer.scheduledTimer(withTimeInterval: Self.scanInterval, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    /// Close the channel properly so the earbuds accept a new one next launch.
    func stop() {
        stopped = true
        scanTimer?.invalidate()
        scanTimer = nil
        if let channel {
            self.channel = nil
            channel.setDelegate(nil)
            channel.close()
        }
        if let pending = opening?.channel {
            pending.setDelegate(nil)
            pending.close()
        }
        opening = nil
    }

    func write(_ bytes: [UInt8]) {
        guard let channel, !bytes.isEmpty else { return }
        var data = bytes
        let status = data.withUnsafeMutableBytes { buffer in
            channel.writeSync(buffer.baseAddress, length: UInt16(buffer.count))
        }
        if status != kIOReturnSuccess { Log.info("Write failed (\(describe(status)))") }
    }

    // MARK: Scanning

    /// Look for a connected paired device that offers the control service.
    private func scan() {
        guard channel == nil, !stopped else { return }
        if let opening {
            // An async open that never completed: give up on it and try again.
            guard Date().timeIntervalSince(opening.startedAt) > Self.openTimeout else { return }
            opening.channel?.setDelegate(nil)
            opening.channel?.close()
            self.opening = nil
            handleOpenFailure(opening.device, status: kIOReturnTimeout)
        }
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        let connected = paired.filter { $0.isConnected() }
        // Keep "Connecting…" up between retries; clear it once no candidate is around.
        if !connected.contains(where: { $0.getServiceRecord(for: serviceUUID) != nil }) {
            onConnecting?(nil)
        }

        for candidate in connected {
            let address = candidate.addressString ?? ""
            guard let record = candidate.getServiceRecord(for: serviceUUID) else {
                // Service list not cached yet: ask once, pick it up on a later scan.
                if !sdpRequested.contains(address) {
                    sdpRequested.insert(address)
                    candidate.performSDPQuery(nil)
                }
                continue
            }

            var channelID: BluetoothRFCOMMChannelID = 0
            guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else { continue }

            var newChannel: IOBluetoothRFCOMMChannel?
            let status = candidate.openRFCOMMChannelAsync(&newChannel, withChannelID: channelID, delegate: self)
            guard status == kIOReturnSuccess else {
                handleOpenFailure(candidate, status: status)
                continue
            }
            opening = (newChannel, candidate, Date())
            onConnecting?(candidate.name ?? candidate.nameOrAddress)
            return
        }
    }

    // Opening usually fails because the earbuds still hold a channel from an
    // earlier session that never closed it. Recover in two steps:
    //   1st failure: refresh the service record in case the channel id moved.
    //   3rd failure: drop and re-establish the Bluetooth link once, which makes
    //                the earbuds forget the stale channel (brief audio blip).
    private func handleOpenFailure(_ device: IOBluetoothDevice, status: IOReturn) {
        let address = device.addressString ?? ""
        let attempt = (openFailures[address] ?? 0) + 1
        openFailures[address] = attempt
        let name = device.nameOrAddress ?? "device"
        Log.info("Could not open channel to \(name) (\(describe(status))), attempt \(attempt)")

        if attempt == 1 {
            device.performSDPQuery(nil)
        }
        if attempt == 3 && !linkResetDone.contains(address) {
            linkResetDone.insert(address)
            Log.info("Resetting Bluetooth link to \(name) to clear a stale channel")
            device.closeConnection()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                _ = device.openConnection()
            }
        }
    }

    // MARK: Paired earbuds

    struct PairedEarbuds: Equatable, Identifiable {
        var name: String
        var address: String
        var id: String { address }
    }

    /// Paired devices that look like Nothing or CMF earbuds but aren't connected.
    static func pairedEarbuds(isEarbuds: (String) -> Bool) -> [PairedEarbuds] {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return paired.compactMap { device in
            guard !device.isConnected(), let name = device.name, isEarbuds(name),
                  let address = device.addressString else { return nil }
            return PairedEarbuds(name: name, address: address)
        }
    }

    /// Bring up the Bluetooth (audio) link to paired earbuds; the scan then opens the channel.
    func connectPaired(_ address: String, completion: @escaping (Bool) -> Void) {
        guard let device = IOBluetoothDevice(addressString: address) else { return completion(false) }
        var target: ConnectTarget?
        target = ConnectTarget { [weak self] status in
            self?.pendingConnects.removeAll { $0 === target }
            completion(status == kIOReturnSuccess)
        }
        guard let target else { return }
        pendingConnects.append(target)
        let status = device.openConnection(target)
        if status != kIOReturnSuccess {
            pendingConnects.removeAll { $0 === target }
            completion(false)
        }
    }

    private var pendingConnects: [ConnectTarget] = []

    private final class ConnectTarget: NSObject {
        let done: (IOReturn) -> Void
        init(_ done: @escaping (IOReturn) -> Void) { self.done = done }

        @objc func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
            done(status)
        }
    }

    // MARK: IOBluetoothRFCOMMChannelDelegate

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard let opening, let rfcommChannel else { return }
        self.opening = nil
        let device = opening.device

        guard error == kIOReturnSuccess, !stopped else {
            if stopped { rfcommChannel.close() }
            handleOpenFailure(device, status: error)
            return
        }
        openFailures[device.addressString ?? ""] = 0
        channel = rfcommChannel
        let name = device.name ?? device.nameOrAddress ?? "Earbuds"
        Log.info("Connected to \(name)")
        onConnected?(name, device.addressString ?? "")
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                           data dataPointer: UnsafeMutableRawPointer!,
                           length dataLength: Int) {
        guard rfcommChannel === channel, let dataPointer, dataLength > 0 else { return }
        let buffer = UnsafeRawBufferPointer(start: dataPointer, count: dataLength)
        onData?(Array(buffer))
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        guard rfcommChannel === channel else { return }
        channel = nil
        Log.info("Channel closed")
        onDisconnected?()
    }
}

private func describe(_ status: IOReturn) -> String {
    let code = String(format: "0x%08X", UInt32(bitPattern: status))
    switch status {
    case kIOReturnError: return "\(code) general error"
    case kIOReturnBusy: return "\(code) busy"
    case kIOReturnTimeout: return "\(code) timeout"
    case kIOReturnNotOpen: return "\(code) not open"
    case kIOReturnNoDevice: return "\(code) no device"
    default: return code
    }
}

enum Log {
    /// NXM_DEBUG=1 logs every frame to and from the earbuds.
    static let debug = ProcessInfo.processInfo.environment["NXM_DEBUG"] != nil

    static func info(_ message: String) { NSLog("[NothingXMac] %@", message) }

    static func frame(_ direction: String, _ bytes: [UInt8]) {
        guard debug else { return }
        info("\(direction) \(bytes.map { String(format: "%02x", $0) }.joined())")
    }
}

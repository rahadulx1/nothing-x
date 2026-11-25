// Nothing earbud packet framing.
// Protocol details referenced from ear-web (github.com/radiance-project/ear-web).
//
// Frame layout:
//   [0]    0x55 start byte
//   [1..2] flags (0x60 0x01 when sending)
//   [3..4] command, little-endian uint16
//   [5]    payload length
//   [6]    reserved
//   [7]    operation id
//   [8..]  payload
//   [..+2] CRC16 (Modbus), little-endian

public enum Frame {
    static let startByte: UInt8 = 0x55
    static let headerLength = 8
    static let crcLength = 2

    /// CRC-16/MODBUS.
    public static func crc16<S: Sequence>(_ bytes: S) -> UInt16 where S.Element == UInt8 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1
            }
        }
        return crc
    }

    public static func encode(command: UInt16, payload: [UInt8] = [], operationId: UInt8 = 0) -> [UInt8] {
        var body: [UInt8] = [
            startByte, 0x60, 0x01,
            UInt8(command & 0xFF), UInt8(command >> 8),
            UInt8(truncatingIfNeeded: payload.count), 0x00, operationId,
        ]
        body += payload
        let crc = crc16(body)
        return body + [UInt8(crc & 0xFF), UInt8(crc >> 8)]
    }
}

public struct IncomingFrame: Equatable {
    public let command: UInt16
    public let operationId: UInt8
    public let payload: [UInt8]
}

/// Turns an arbitrary byte stream into frames.
public struct FrameParser {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func push(_ chunk: [UInt8]) -> [IncomingFrame] {
        buffer += chunk
        var frames: [IncomingFrame] = []

        while true {
            guard let start = buffer.firstIndex(of: Frame.startByte) else {
                buffer.removeAll()
                break
            }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= Frame.headerLength else { break }

            let bodyLength = Frame.headerLength + Int(buffer[5])
            guard buffer.count >= bodyLength else { break }

            let body = Array(buffer[0..<bodyLength])
            var frameLength = bodyLength
            if buffer.count >= bodyLength + Frame.crcLength {
                let crc = UInt16(buffer[bodyLength]) | (UInt16(buffer[bodyLength + 1]) << 8)
                if crc == Frame.crc16(body) { frameLength += Frame.crcLength }
            }

            frames.append(IncomingFrame(
                command: UInt16(body[3]) | (UInt16(body[4]) << 8),
                operationId: body[7],
                payload: Array(body[Frame.headerLength...])
            ))
            buffer.removeFirst(frameLength)
        }
        return frames
    }

    public mutating func reset() { buffer.removeAll() }
}

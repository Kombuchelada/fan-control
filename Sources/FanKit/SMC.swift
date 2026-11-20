import CSMC
import Foundation
import IOKit

/// A four-character SMC key such as `F0Ac` or `TC0P`.
public struct SMCKey: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let code: UInt32

    public init(code: UInt32) { self.code = code }

    public init(_ string: String) {
        precondition(string.utf8.count == 4, "SMC keys are four ASCII characters")
        code = string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    public init(stringLiteral value: String) { self.init(value) }

    public var description: String { fourCC(code) }

    /// Fan-indexed key, e.g. `SMCKey.fan(1, "Ac")` → `F1Ac`.
    public static func fan(_ index: Int, _ suffix: String) -> SMCKey { SMCKey("F\(index)\(suffix)") }
}

func fourCC(_ code: UInt32) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
    return String(decoding: bytes, as: UTF8.self)
}

/// A decoded SMC value.
public struct SMCReading: Sendable {
    public let key: SMCKey
    public let type: String
    public let bytes: [UInt8]

    /// Numeric interpretation of the value, if its type is understood.
    public var number: Double? {
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "ui8 ", "flag":
            return bytes.first.map(Double.init)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(bytes[0..<4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
        default:
            return nil
        }
    }

    /// Encodes `value` in this reading's type, for writing back to the same key.
    public func encode(_ value: Double) -> [UInt8]? {
        switch type {
        case "flt ":
            let bits = Float(value).bitPattern
            return [UInt8(bits & 0xFF), UInt8((bits >> 8) & 0xFF), UInt8((bits >> 16) & 0xFF), UInt8(bits >> 24)]
        case "fpe2":
            let raw = UInt16(clamping: Int((value * 4).rounded()))
            return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        case "ui8 ", "flag":
            return [UInt8(clamping: Int(value.rounded()))]
        case "ui16":
            let raw = UInt16(clamping: Int(value.rounded()))
            return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        default:
            return nil
        }
    }
}

public enum SMCError: Error, CustomStringConvertible {
    case unavailable(kern_return_t)
    case keyNotFound(SMCKey)
    case writeFailed(SMCKey, kern_return_t)
    case unsupportedType(SMCKey, String)

    public var description: String {
        switch self {
        case .unavailable(let code): "The system management controller is unavailable (\(String(code, radix: 16)))."
        case .keyNotFound(let key): "SMC key \(key) was not found."
        case .writeFailed(let key, let code):
            code == kIOReturnNotPrivileged
                ? "Writing \(key) requires administrator privileges."
                : "Writing SMC key \(key) failed (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .unsupportedType(let key, let type): "SMC key \(key) has unsupported type '\(type)'."
        }
    }
}

/// A connection to the Apple System Management Controller.
///
/// Reading works for any user; writing requires root.
/// Not thread-safe: confine each instance to one thread or actor.
public final class SMC {
    private var connection: io_connect_t = 0

    public init() throws {
        let result = SMCOpen(&connection)
        guard result == KERN_SUCCESS else { throw SMCError.unavailable(result) }
    }

    deinit { SMCClose(connection) }

    public func read(_ key: SMCKey) throws -> SMCReading {
        var value = SMCValue()
        guard SMCReadKey(connection, key.code, &value) == KERN_SUCCESS, value.dataSize > 0 else {
            throw SMCError.keyNotFound(key)
        }
        let bytes = withUnsafeBytes(of: value.bytes) { Array($0.prefix(Int(value.dataSize))) }
        return SMCReading(key: key, type: fourCC(value.dataType), bytes: bytes)
    }

    public func number(_ key: SMCKey) -> Double? {
        try? read(key).number
    }

    public func write(_ key: SMCKey, bytes: [UInt8]) throws {
        let result = SMCWriteKey(connection, key.code, bytes, UInt32(bytes.count))
        guard result == KERN_SUCCESS else { throw SMCError.writeFailed(key, result) }
    }

    /// Writes a numeric value, encoding it in the key's native type.
    public func write(_ key: SMCKey, number: Double) throws {
        let current = try read(key)
        guard let bytes = current.encode(number) else { throw SMCError.unsupportedType(key, current.type) }
        try write(key, bytes: bytes)
    }

    public func allKeys() -> [SMCKey] {
        var count: UInt32 = 0
        guard SMCKeyCount(connection, &count) == KERN_SUCCESS else { return [] }
        return (0..<count).compactMap { index in
            var code: UInt32 = 0
            return SMCKeyAtIndex(connection, index, &code) == KERN_SUCCESS ? SMCKey(code: code) : nil
        }
    }
}

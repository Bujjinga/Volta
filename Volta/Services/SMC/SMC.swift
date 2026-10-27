//
//  SMC.swift
//  Volta
//

import Foundation
import IOKit

/// Minimal client for the System Management Controller (SMC).
///
/// The SMC is the chip that owns charging, fans, and many sensors. macOS exposes it
/// through the `AppleSMC` IOKit service. Any process may **read** keys; **writes**
/// require root, which is why charge limiting runs in the privileged helper.
///
/// Key names and types are undocumented and differ between Intel and Apple Silicon,
/// so callers should always check `keyExists(_:)` before relying on a key.
nonisolated final class SMC {
    enum SMCError: Error, CustomStringConvertible {
        case serviceNotFound
        case openFailed(kern_return_t)
        case callFailed(kern_return_t)
        case keyNotFound(String)
        case smcResult(String, UInt8)
        case sizeMismatch(String, expected: Int, got: Int)

        var description: String {
            switch self {
            case .serviceNotFound: "AppleSMC service not found"
            case .openFailed(let code): "Could not open AppleSMC (\(String(format: "0x%x", code)))"
            case .callFailed(let code): "SMC call failed (\(String(format: "0x%x", code)))"
            case .keyNotFound(let key): "SMC key \(key) not present on this Mac"
            case .smcResult(let key, let result): "SMC returned \(result) for key \(key)"
            case .sizeMismatch(let key, let expected, let got): "SMC key \(key) is \(expected) bytes, tried to write \(got)"
            }
        }
    }

    struct KeyInfo {
        var size: Int
        var type: String
    }

    private var connection: io_connect_t = 0

    init() throws {
        // Find the AppleSMC kernel service. It exists on every Intel and Apple Silicon Mac.
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }

        // IOServiceOpen creates a user-client connection to the driver. Type 0 is the
        // default SMC user client. The connection must be closed with IOServiceClose.
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { throw SMCError.openFailed(result) }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    // MARK: - Public API

    func keyExists(_ key: String) -> Bool {
        (try? keyInfo(key)) != nil
    }

    /// Asks the SMC for a key's size and four-character type code.
    func keyInfo(_ key: String) throws -> KeyInfo {
        var input = VoltaSMCParamStruct()
        input.key = Self.fourCharCode(key)
        input.data8 = CChar(VOLTA_SMC_CMD_READ_KEYINFO)
        let output = try call(input, key: key)
        return KeyInfo(size: Int(output.keyInfo.dataSize), type: Self.string(fromFourCharCode: output.keyInfo.dataType))
    }

    /// Reads a key's raw bytes.
    func read(_ key: String) throws -> [UInt8] {
        let info = try keyInfo(key)
        var input = VoltaSMCParamStruct()
        input.key = Self.fourCharCode(key)
        input.keyInfo.dataSize = UInt32(info.size)
        input.data8 = CChar(VOLTA_SMC_CMD_READ_BYTES)
        let output = try call(input, key: key)
        return withUnsafeBytes(of: output.bytes) { Array($0.prefix(info.size)) }
    }

    /// Writes raw bytes to a key. Requires root; fails with kIOReturnNotPrivileged otherwise.
    func write(_ key: String, bytes: [UInt8]) throws {
        let info = try keyInfo(key)
        guard info.size == bytes.count else {
            throw SMCError.sizeMismatch(key, expected: info.size, got: bytes.count)
        }
        var input = VoltaSMCParamStruct()
        input.key = Self.fourCharCode(key)
        input.keyInfo.dataSize = UInt32(info.size)
        input.data8 = CChar(VOLTA_SMC_CMD_WRITE_BYTES)
        withUnsafeMutableBytes(of: &input.bytes) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = byte }
        }
        _ = try call(input, key: key)
    }

    /// Reads a temperature-style key and decodes it according to its SMC type.
    func readDouble(_ key: String) throws -> Double? {
        let info = try keyInfo(key)
        let bytes = try read(key)
        switch info.type {
        case "flt ":
            // Apple Silicon: little-endian IEEE-754 float.
            guard bytes.count == 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case "sp78":
            // Intel: signed fixed point, 7 integer bits + 8 fraction bits, big-endian.
            guard bytes.count == 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "ui8 ":
            return bytes.first.map(Double.init)
        case "ui16":
            guard bytes.count == 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        default:
            return nil
        }
    }

    /// Lists every key the SMC exposes whose name starts with `prefix`.
    /// Used for diagnostics so users can report which charge keys their firmware has.
    func keys(withPrefix prefix: String) -> [String] {
        // "#KEY" is a ui32 holding the total number of keys.
        guard let countBytes = try? read("#KEY"), countBytes.count == 4 else { return [] }
        let count = countBytes.reduce(0) { $0 << 8 | UInt32($1) }

        var result: [String] = []
        for index in 0..<count {
            var input = VoltaSMCParamStruct()
            input.data8 = CChar(VOLTA_SMC_CMD_READ_INDEX)
            input.data32 = index
            guard let output = try? call(input, key: "#\(index)") else { continue }
            let name = Self.string(fromFourCharCode: output.key)
            if name.hasPrefix(prefix) { result.append(name) }
        }
        return result
    }

    // MARK: - Low level

    /// Sends one request to the SMC user client.
    private func call(_ input: VoltaSMCParamStruct, key: String) throws -> VoltaSMCParamStruct {
        var input = input
        var output = VoltaSMCParamStruct()
        var outputSize = MemoryLayout<VoltaSMCParamStruct>.stride

        // IOConnectCallStructMethod passes a struct in and receives a struct back. Selector
        // 2 (kSMCHandleYPCEvent) is the SMC's general entry point; `data8` inside the struct
        // selects read / write / key-info.
        let result = IOConnectCallStructMethod(
            connection,
            UInt32(VOLTA_KERNEL_INDEX_SMC),
            &input, MemoryLayout<VoltaSMCParamStruct>.stride,
            &output, &outputSize
        )
        guard result == kIOReturnSuccess else { throw SMCError.callFailed(result) }

        let smcResult = UInt8(bitPattern: output.result)
        if smcResult == VOLTA_SMC_RESULT_KEY_NOT_FOUND { throw SMCError.keyNotFound(key) }
        guard smcResult == 0 else { throw SMCError.smcResult(key, smcResult) }
        return output
    }

    /// Packs "BCLM" into 0x42434C4D.
    static func fourCharCode(_ string: String) -> UInt32 {
        string.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    static func string(fromFourCharCode code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

nonisolated extension SMC {
    /// Battery temperature from the SMC, used when the IORegistry doesn't publish one.
    /// "TB0T"… are the battery thermistors on both Intel and Apple Silicon.
    static func batteryTemperature() -> Double? {
        guard let smc = try? SMC() else { return nil }
        for key in ["TB0T", "TB1T", "TB2T"] {
            if let value = try? smc.readDouble(key), value > 0, value < 100 {
                return value
            }
        }
        return nil
    }
}

//
//  HelperProtocol.swift
//  Volta
//
//  Shared between the app (XPC client) and the privileged helper (XPC server).
//

import Foundation
import Security

nonisolated enum HelperConstants {
    /// Must match the Label and MachServices key in bashirul.Volta.helper.plist.
    static let machServiceName = "bashirul.Volta.helper"
    /// File name inside Volta.app/Contents/Library/LaunchDaemons/.
    static let plistName = "bashirul.Volta.helper.plist"
    /// launchd starts the main executable with this argument to run as the helper.
    static let helperFlag = "--helper"
    static let appBundleIdentifier = "bashirul.Volta"
    static let version = 1
}

/// The XPC interface the root helper exports. Replies carry `nil` on success or an error message.
@objc(VoltaHelperProtocol)
protocol VoltaHelperProtocol {
    func helperVersion(reply: @escaping (Int) -> Void)
    /// Enables or inhibits charging (Apple Silicon CHTE / CH0B+CH0C).
    func setChargingEnabled(_ enabled: Bool, reply: @escaping (String?) -> Void)
    /// Firmware-enforced charge ceiling (Intel BCLM).
    func setChargeLimit(_ percent: Int, reply: @escaping (String?) -> Void)
    /// Puts every charge key back to its factory value.
    func restoreDefaults(reply: @escaping (String?) -> Void)
}

/// Which set of SMC keys this Mac uses for charge control.
///
/// Detection only *reads* keys, which any process may do. We never write a key that
/// isn't on this list, because an unknown key could leave charging stuck.
nonisolated enum ChargeControlMethod: String {
    /// Intel Macs: "BCLM" (ui8) holds a charge ceiling (percent) the firmware enforces.
    case bclm
    /// Apple Silicon on newer firmware (macOS 15-era): "CHTE" (4 bytes). 01 00 00 00
    /// inhibits charging, 00 00 00 00 allows it.
    case chte
    /// Apple Silicon on older firmware: "CH0B" and "CH0C" (1 byte each). 0x02 inhibits
    /// charging, 0x00 allows it. Both keys are written together.
    case ch0bc
    /// None of the known keys exist (e.g. some M5 / macOS 27 firmware).
    case unsupported

    static func detect(using smc: SMC) -> ChargeControlMethod {
        #if arch(x86_64)
        if smc.keyExists("BCLM") { return .bclm }
        #endif
        if smc.keyExists("CHTE") { return .chte }
        if smc.keyExists("CH0B") && smc.keyExists("CH0C") { return .ch0bc }
        if smc.keyExists("BCLM") { return .bclm }
        return .unsupported
    }

    static func detect() -> ChargeControlMethod {
        guard let smc = try? SMC() else { return .unsupported }
        return detect(using: smc)
    }

    var title: String {
        switch self {
        case .bclm: "Intel (BCLM)"
        case .chte: "Apple Silicon (CHTE)"
        case .ch0bc: "Apple Silicon (CH0B/CH0C)"
        case .unsupported: "Not supported on this firmware"
        }
    }

    var isSupported: Bool { self != .unsupported }
}

/// Code-signing helpers used by both sides of the XPC connection.
nonisolated enum CodeSigning {
    /// The Team ID this binary is signed with, or `nil` for ad-hoc / unsigned builds.
    static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Requirement a peer must satisfy: Volta's bundle ID, signed by the same team.
    static func peerRequirement() -> String {
        if let team = ownTeamIdentifier() {
            return "anchor apple generic and identifier \"\(HelperConstants.appBundleIdentifier)\" and certificate leaf[subject.OU] = \"\(team)\""
        }
        // Development builds signed "to run locally" have no team.
        return "identifier \"\(HelperConstants.appBundleIdentifier)\""
    }
}

//
//  HelperDaemon.swift
//  Volta
//
//  The privileged helper. launchd runs Volta.app/Contents/MacOS/Volta --helper as root
//  (see bashirul.Volta.helper.plist). It only writes SMC charge keys and runs pmset.
//

import Foundation

nonisolated enum HelperDaemon {
    static func run() -> Never {
        // Always start from a known-good state. With RunAtLoad this also runs at boot, so
        // a Mac that was rebooted (or had Volta deleted) while charging was inhibited
        // goes back to normal charging.
        _ = HelperOperations.restoreDefaults()

        let delegate = HelperListenerDelegate()
        let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
        listener.delegate = delegate
        listener.resume()
        delegate.scheduleIdleExit()

        RunLoop.main.run()
        exit(0)
    }
}

/// Accepts connections only from a correctly signed Volta app.
nonisolated final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "bashirul.Volta.helper.state")
    private var activeConnections = 0
    private var idleExit: DispatchWorkItem?

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Reject any process that isn't Volta signed by our team (macOS 13+).
        connection.setCodeSigningRequirement(CodeSigning.peerRequirement())

        connection.exportedInterface = NSXPCInterface(with: VoltaHelperProtocol.self)
        connection.exportedObject = HelperService()

        connection.invalidationHandler = { [weak self] in
            // The app quit, crashed, or was killed: put charging back to normal.
            self?.connectionClosed()
        }
        queue.sync {
            activeConnections += 1
            idleExit?.cancel()
        }
        connection.resume()
        return true
    }

    private func connectionClosed() {
        queue.sync { activeConnections -= 1 }
        _ = HelperOperations.restoreDefaults()
        scheduleIdleExit()
    }

    /// launchd relaunches us on demand, so exit when nobody is connected.
    func scheduleIdleExit() {
        queue.sync {
            idleExit?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let idle = self.queue.sync { self.activeConnections == 0 }
                if idle { exit(0) }
            }
            idleExit = item
            DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: item)
        }
    }
}

/// The object exported over XPC.
nonisolated final class HelperService: NSObject, VoltaHelperProtocol {
    func helperVersion(reply: @escaping (Int) -> Void) {
        reply(HelperConstants.version)
    }

    func setChargingEnabled(_ enabled: Bool, reply: @escaping (String?) -> Void) {
        reply(HelperOperations.setChargingEnabled(enabled))
    }

    func setChargeLimit(_ percent: Int, reply: @escaping (String?) -> Void) {
        reply(HelperOperations.setChargeLimit(percent))
    }

    func restoreDefaults(reply: @escaping (String?) -> Void) {
        reply(HelperOperations.restoreDefaults())
    }
}

/// The actual privileged work. Every function returns `nil` on success or an error message.
nonisolated enum HelperOperations {
    private static let lock = NSLock()

    static func setChargingEnabled(_ enabled: Bool) -> String? {
        withSMC { smc, method in
            switch method {
            case .chte:
                // CHTE: 4 bytes, first byte 1 = inhibit charging, 0 = allow.
                try smc.write("CHTE", bytes: [enabled ? 0x00 : 0x01, 0x00, 0x00, 0x00])
            case .ch0bc:
                // CH0B / CH0C: 0x02 = inhibit charging, 0x00 = allow. Always written as a pair.
                let value: UInt8 = enabled ? 0x00 : 0x02
                try smc.write("CH0B", bytes: [value])
                try smc.write("CH0C", bytes: [value])
            case .bclm:
                // Intel has no on/off switch; emulate with the ceiling.
                try smc.write("BCLM", bytes: [enabled ? 100 : 1])
            case .unsupported:
                throw SMC.SMCError.keyNotFound("CHTE/CH0B/BCLM")
            }
        }
    }

    static func setChargeLimit(_ percent: Int) -> String? {
        withSMC { smc, method in
            guard method == .bclm else { throw SMC.SMCError.keyNotFound("BCLM") }
            // BCLM: ui8 percentage; the firmware stops charging at this level.
            try smc.write("BCLM", bytes: [UInt8(min(max(percent, 20), 100))])
        }
    }

    static func restoreDefaults() -> String? {
        withSMC { smc, method in
            switch method {
            case .chte: try smc.write("CHTE", bytes: [0, 0, 0, 0])
            case .ch0bc:
                try smc.write("CH0B", bytes: [0])
                try smc.write("CH0C", bytes: [0])
            case .bclm: try smc.write("BCLM", bytes: [100])
            case .unsupported: break
            }
        }
    }

    private static func withSMC(_ body: (SMC, ChargeControlMethod) throws -> Void) -> String? {
        lock.lock()
        defer { lock.unlock() }
        do {
            let smc = try SMC()
            try body(smc, ChargeControlMethod.detect(using: smc))
            return nil
        } catch {
            return String(describing: error)
        }
    }
}

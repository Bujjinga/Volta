//
//  ChargeController.swift
//  Volta
//

import AppKit
import Foundation
import Observation
import ServiceManagement

/// App-side control of charge limiting and Low Power Mode via the privileged helper.
@Observable
final class ChargeController {
    /// Detected with unprivileged SMC reads at launch.
    let method: ChargeControlMethod
    private(set) var helperStatus: SMAppService.Status = .notRegistered
    private(set) var isChargingInhibited = false
    private(set) var lastError: String?
    /// Set by "Charge to 100% once"; clears itself when the battery is full.
    private(set) var isTopUpActive = false

    @ObservationIgnored private let daemon = SMAppService.daemon(plistName: HelperConstants.plistName)
    @ObservationIgnored private var connection: NSXPCConnection?
    @ObservationIgnored private var lastSentLimit: Int?
    @ObservationIgnored private var latest = BatteryInfo()

    init() {
        method = ChargeControlMethod.detect()
        refreshStatus()
    }

    // MARK: - Helper installation

    /// `true` when the LaunchDaemon plist was embedded in the bundle at build time.
    var isHelperBundled: Bool {
        let url = Bundle.main.bundleURL.appending(path: "Contents/Library/LaunchDaemons/\(HelperConstants.plistName)")
        return FileManager.default.fileExists(atPath: url.path)
    }

    var isHelperReady: Bool { helperStatus == .enabled }

    func refreshStatus() {
        helperStatus = daemon.status
    }

    func installHelper() {
        do {
            try daemon.register()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refreshStatus()
        if helperStatus == .requiresApproval {
            // Admins approve daemons in System Settings › General › Login Items & Extensions.
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    /// Restores normal charging, then removes the helper.
    func uninstallHelper() {
        UserDefaults.standard.set(false, forKey: SettingsKey.chargeLimitEnabled)
        UserDefaults.standard.set(false, forKey: SettingsKey.sailingMode)
        restoreNormalCharging { [weak self] in
            guard let self else { return }
            self.connection?.invalidate()
            self.connection = nil
            self.daemon.unregister { error in
                Task { @MainActor in
                    self.lastError = error?.localizedDescription
                    self.refreshStatus()
                }
            }
        }
    }

    // MARK: - Charge limiting

    /// Called on every battery change and whenever settings change.
    func evaluate(_ info: BatteryInfo) {
        latest = info
        let defaults = UserDefaults.standard
        let limitEnabled = defaults.bool(forKey: SettingsKey.chargeLimitEnabled)
        let sailing = defaults.bool(forKey: SettingsKey.sailingMode)
        let limit = defaults.integer(forKey: SettingsKey.chargeLimit)

        guard info.hasBattery, method.isSupported, isHelperReady else { return }

        if isTopUpActive, info.percentage >= 100 || info.isFullyCharged {
            isTopUpActive = false
        }

        guard (limitEnabled || sailing) && !isTopUpActive else {
            if isChargingInhibited || lastSentLimit != nil { restoreNormalCharging() }
            return
        }

        switch method {
        case .bclm:
            // Intel: the firmware enforces the ceiling itself.
            let target = sailing ? max(info.percentage, 20) : limit
            guard target != lastSentLimit else { return }
            lastSentLimit = target
            call { $0.setChargeLimit(target, reply: $1) }
        case .chte, .ch0bc:
            // Apple Silicon: toggle charging around the limit with a 2% band so we don't
            // flip the SMC on every percentage tick.
            let shouldInhibit: Bool
            if sailing {
                // Sailing mode: hold the current level while on AC.
                shouldInhibit = info.isOnAC
            } else if isChargingInhibited {
                shouldInhibit = info.percentage > limit - 2
            } else {
                shouldInhibit = info.percentage >= limit
            }
            guard shouldInhibit != isChargingInhibited else { return }
            setChargingEnabled(!shouldInhibit)
        case .unsupported:
            break
        }
    }

    func chargeToFullOnce() {
        isTopUpActive = true
        restoreNormalCharging()
    }

    func settingsChanged() {
        evaluate(latest)
    }

    private func setChargingEnabled(_ enabled: Bool) {
        isChargingInhibited = !enabled
        call { $0.setChargingEnabled(enabled, reply: $1) }
    }

    /// Puts every key back to factory values.
    func restoreNormalCharging(completion: (() -> Void)? = nil) {
        isChargingInhibited = false
        lastSentLimit = nil
        guard isHelperReady else {
            completion?()
            return
        }
        call({ $0.restoreDefaults(reply: $1) }, completion: completion)
    }

    /// Synchronous restore used from `applicationWillTerminate`, where async replies
    /// would never arrive. The helper also restores on disconnect as a backstop.
    func restoreNormalChargingBeforeQuit() {
        guard isHelperReady, isChargingInhibited || lastSentLimit != nil,
              let proxy = connectionProxy(synchronous: true) else { return }
        proxy.restoreDefaults { _ in }
    }

    // MARK: - XPC

    private func call(_ body: (VoltaHelperProtocol, @escaping (String?) -> Void) -> Void, completion: (() -> Void)? = nil) {
        guard let proxy = connectionProxy(synchronous: false) else {
            completion?()
            return
        }
        body(proxy) { [weak self] error in
            Task { @MainActor in
                self?.lastError = error
                completion?()
            }
        }
    }

    private func connectionProxy(synchronous: Bool) -> VoltaHelperProtocol? {
        let connection = self.connection ?? makeConnection()
        let errorHandler: (Error) -> Void = { [weak self] error in
            Task { @MainActor in self?.lastError = error.localizedDescription }
        }
        let proxy = synchronous
            ? connection.synchronousRemoteObjectProxyWithErrorHandler(errorHandler)
            : connection.remoteObjectProxyWithErrorHandler(errorHandler)
        return proxy as? VoltaHelperProtocol
    }

    private func makeConnection() -> NSXPCConnection {
        // .privileged: the Mach service lives in the system (root) launchd domain.
        let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: VoltaHelperProtocol.self)
        // Make sure we're talking to our own helper, not an impostor.
        connection.setCodeSigningRequirement(CodeSigning.peerRequirement())
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        connection.resume()
        self.connection = connection
        return connection
    }
}

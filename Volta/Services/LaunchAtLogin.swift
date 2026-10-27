//
//  LaunchAtLogin.swift
//  Volta
//

import ServiceManagement

/// Registers Volta itself as a login item (System Settings › General › Login Items).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

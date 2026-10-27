//
//  NotificationSender.swift
//  Volta
//

import Foundation
import Intents
import UserNotifications

/// Optional fallback: standard macOS notifications via UNUserNotificationCenter.
enum NotificationSender {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Reads the user's Focus / Do Not Disturb state.
///
/// `INFocusStatusCenter` only reports a value after the user grants access, and only
/// when the app is signed with the Communication Notifications capability. Without
/// those, `isFocused` is `false`, so alerts behave normally.
enum FocusMonitor {
    static func requestAuthorization() {
        INFocusStatusCenter.default.requestAuthorization { _ in }
    }

    static var isAuthorized: Bool {
        INFocusStatusCenter.default.authorizationStatus == .authorized
    }

    static var isFocused: Bool {
        guard isAuthorized else { return false }
        return INFocusStatusCenter.default.focusStatus.isFocused ?? false
    }
}

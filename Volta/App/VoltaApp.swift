//
//  VoltaApp.swift
//  Volta
//

import AppKit
import SwiftData
import SwiftUI

/// Process entry point. The same binary also serves as the privileged helper daemon,
/// which launchd starts with `--helper` (see Helper/HelperDaemon.swift).
@main
enum VoltaEntry {
    /// Xcode Previews launch the app too; they must not add a second menu bar icon.
    static let isRunningForPreviews = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    static func main() {
        if CommandLine.arguments.contains(HelperConstants.helperFlag) {
            HelperDaemon.run()
        }
        if !isRunningForPreviews {
            SingleInstance.replaceOlderInstances()
        }
        VoltaApp.main()
    }
}

/// Only one Volta may own the menu bar. The newest launch wins: it broadcasts a
/// distributed notification and any older copy (an old build, a second double-click,
/// login item + manual launch) quits. Xcode Preview hosts neither send nor listen.
enum SingleInstance {
    private static let name = Notification.Name("bashirul.Volta.newInstanceLaunched")
    private static var observer: NSObjectProtocol?

    static func replaceOlderInstances() {
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        DistributedNotificationCenter.default().postNotificationName(
            name, object: pid, userInfo: nil, deliverImmediately: true
        )
    }

    /// Call once the app has launched.
    static func quitWhenReplaced() {
        guard !VoltaEntry.isRunningForPreviews, observer == nil else { return }
        let ownPID = String(ProcessInfo.processInfo.processIdentifier)
        observer = DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { note in
            guard let sender = note.object as? String, sender != ownPID else { return }
            MainActor.assumeIsolated { NSApplication.shared.terminate(nil) }
        }
    }
}

struct VoltaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    @State private var showsMenuBarItem = !VoltaEntry.isRunningForPreviews

    var body: some Scene {
        MenuBarExtra(isInserted: $showsMenuBarItem) {
            PopoverView()
                .environment(model)
                .environment(model.battery)
                .modelContainer(model.history.container)
        } label: {
            MenuBarLabel(battery: model.battery, renderer: model.iconRenderer)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .environment(model.battery)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        SingleInstance.quitWhenReplaced()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave charging inhibited after Volta quits.
        AppModel.shared.charge.restoreNormalChargingBeforeQuit()
    }
}

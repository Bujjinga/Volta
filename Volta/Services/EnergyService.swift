//
//  EnergyService.swift
//  Volta
//

import AppKit
import Darwin
import Observation

/// One row in the Energy tab: an app (with its helpers folded in) or a bare process.
struct AppEnergy: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    let impact: Double
}

/// Samples Activity Monitor-style "Energy Impact" via `top`.
///
/// There's no public API for Energy Impact. `top`'s POWER column is the same metric,
/// so we run `top -l 2` and read the second sample (the first has no time delta).
/// Sampling happens only while the Energy tab is visible.
@Observable
final class EnergyService {
    private(set) var apps: [AppEnergy] = []
    private(set) var isLoading = false

    @ObservationIgnored private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        isLoading = apps.isEmpty
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sample()
                try? await Task.sleep(for: .seconds(8))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func sample() async {
        // Run `top` off the main actor; it blocks for about one second.
        let rows = await Task.detached(priority: .utility) { () -> [TopRow] in
            Self.parse(Self.runTop())
        }.value
        guard !Task.isCancelled else { return }
        apps = Self.group(rows)
        isLoading = false
    }

    // MARK: - top

    struct TopRow: Sendable {
        let pid: pid_t
        let command: String
        let power: Double
    }

    nonisolated private static func runTop() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        // -l 2: two samples · -s 1: one second apart · -n 30: top 30 processes
        // -o power: sort by energy impact · -stats: only the columns we parse
        process.arguments = ["-l", "2", "-s", "1", "-n", "30", "-o", "power", "-stats", "pid,command,power"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Parses the rows that follow the *last* "PID COMMAND POWER" header.
    nonisolated static func parse(_ output: String) -> [TopRow] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        guard let header = lines.lastIndex(where: { $0.hasPrefix("PID") }) else { return [] }
        return lines[(header + 1)...].compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3,
                  let pid = pid_t(parts[0]),
                  let power = Double(parts[parts.count - 1]) else { return nil }
            let command = parts[1..<(parts.count - 1)].joined(separator: " ")
            return TopRow(pid: pid, command: command, power: power)
        }
    }

    // MARK: - Grouping

    private static func group(_ rows: [TopRow]) -> [AppEnergy] {
        struct Bucket { var name: String; var icon: NSImage; var impact: Double }
        var buckets: [String: Bucket] = [:]
        let ownPID = ProcessInfo.processInfo.processIdentifier

        for row in rows where row.power > 0 && row.command != "top" && row.pid != ownPID {
            let path = executablePath(for: row.pid)
            if let bundle = path.flatMap(outermostAppBundle) {
                // Fold "Foo Helper (Renderer).app" etc. into the outer "Foo.app".
                if buckets[bundle] == nil {
                    let running = NSRunningApplication(processIdentifier: row.pid)
                    let icon = running?.bundleURL?.path == bundle ? running?.icon : nil
                    buckets[bundle] = Bucket(
                        name: displayName(forBundleAt: bundle),
                        icon: icon ?? NSWorkspace.shared.icon(forFile: bundle),
                        impact: 0
                    )
                }
                buckets[bundle]?.impact += row.power
            } else {
                // `top` truncates command names to 16 characters; the path has the full name.
                let name = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? row.command
                let key = "process:\(name)"
                if buckets[key] == nil {
                    let icon = NSImage(systemSymbolName: "gearshape.2", accessibilityDescription: nil) ?? NSImage()
                    buckets[key] = Bucket(name: name, icon: icon, impact: 0)
                }
                buckets[key]?.impact += row.power
            }
        }

        return buckets
            .map { AppEnergy(id: $0.key, name: $0.value.name, icon: $0.value.icon, impact: $0.value.impact) }
            .sorted { $0.impact > $1.impact }
            .prefix(8)
            .map { $0 }
    }

    /// Full path of a process's executable, via libproc.
    private static func executablePath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    /// "/Applications/Foo.app/Contents/Frameworks/Bar.app/…" → "/Applications/Foo.app"
    nonisolated private static func outermostAppBundle(in path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    private static func displayName(forBundleAt path: String) -> String {
        let bundle = Bundle(path: path)
        return bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
}

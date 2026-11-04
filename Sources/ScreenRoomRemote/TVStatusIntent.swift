import AppIntents
import SwiftUI
import Foundation

/// Read-only. ADB's state reflects the local ADB server, not current playback.
struct TVConnectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Check TV Connection"
    static let description = IntentDescription("Checks the remote's saved Fire TV connection.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let address = UserDefaults.standard.string(forKey: "tvAddress") ?? ""
        let connected = await Task.detached(priority: .userInitiated) { () -> Bool in
            guard !address.isEmpty else { return false }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: (FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/adb") ? "/opt/homebrew/bin/adb" : "/usr/local/bin/adb"))
            process.arguments = ["-s", address + ":5555", "get-state"]
            let output = Pipe(); process.standardOutput = output; process.standardError = Pipe()
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return process.terminationStatus == 0 && String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "device"
            } catch { return false }
        }.value
        let detail = address.isEmpty ? "Choose a TV in Screen Room Remote first." : connected ? "The saved Fire TV is connected." : "The saved Fire TV is not connected. Open the remote to reconnect."
        return .result(dialog: IntentDialog(stringLiteral: detail), view: TVStatusCard(connected: connected, configured: !address.isEmpty))
    }
}

private struct TVStatusCard: View {
    let connected: Bool
    let configured: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("SCREEN ROOM REMOTE", systemImage: "tv").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(!configured ? "Choose a TV" : connected ? "Fire TV connected" : "Fire TV unavailable").font(.headline)
            Text(!configured ? "Open the remote and connect a Fire TV." : connected ? "Ready for remote controls." : "Open the remote to reconnect.").font(.subheadline).foregroundStyle(.secondary)
        }.padding(12)
    }
}

struct RemoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TVConnectionIntent(), phrases: ["Check TV connection in \(.applicationName)", "Is the TV connected in \(.applicationName)"], shortTitle: "TV Connection", systemImageName: "tv")
    }
}

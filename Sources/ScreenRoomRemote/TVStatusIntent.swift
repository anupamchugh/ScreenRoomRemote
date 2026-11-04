import AppIntents
import SwiftUI
import Foundation

/// Checks ADB state; it does not claim to know what is playing.
struct TVConnectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Check TV Connection"
    static let description = IntentDescription("Checks the remote's saved Fire TV connection.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        let address = UserDefaults.standard.string(forKey: "tvAddress") ?? ""
        let connected = await Task.detached(priority: .userInitiated) { () -> Bool in
            guard !address.isEmpty else { return false }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/adb") ? "/opt/homebrew/bin/adb" : "/usr/local/bin/adb")
            process.arguments = ["-s", address + ":5555", "get-state"]
            let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return process.terminationStatus == 0 && String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "device"
            } catch { return false }
        }.value
        let dialog: IntentDialog
        if address.isEmpty { dialog = "Choose a TV in Screen Room Remote first." }
        else if connected { dialog = "Your Fire TV is connected." }
        else { dialog = "Your Fire TV is not connected." }
        return .result(dialog: dialog, snippetIntent: TVStatusSnippetIntent(connected: connected, configured: !address.isEmpty))
    }
}

/// Rendering can be repeated by the system and therefore has no side effects.
struct TVStatusSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "TV Connection Card"
    static let isDiscoverable = false
    @Parameter var connected: Bool
    @Parameter var configured: Bool
    init() {}
    init(connected: Bool, configured: Bool) { self.connected = connected; self.configured = configured }
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: TVStatusCard(connected: connected, configured: configured))
    }
}

/// High-contrast SiriCardKit card material (opaque dark ink 0.92 -> 0.98 so light text stays crisp on any Siri sheet).
private struct TVStatusCardMaterial: View {
    let tint: Color

    private static let ink = Color(red: 0.08, green: 0.07, blue: 0.11)
    private static let stops: [Gradient.Stop] = [
        .init(color: ink.opacity(0.92), location: 0.00),
        .init(color: ink.opacity(0.93), location: 0.20),
        .init(color: ink.opacity(0.95), location: 0.45),
        .init(color: ink.opacity(0.97), location: 0.75),
        .init(color: ink.opacity(0.98), location: 1.00),
    ]

    var body: some View {
        ZStack {
            LinearGradient(stops: Self.stops, startPoint: .top, endPoint: .bottom)
            LinearGradient(
                stops: [
                    .init(color: tint.opacity(0.22), location: 0.0),
                    .init(color: tint.opacity(0.10), location: 0.55),
                    .init(color: tint.opacity(0.04), location: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.plusLighter)
        }
    }
}

private struct TVStatusCard: View {
    let connected: Bool
    let configured: Bool
    private var tint: Color {
        if !configured { return .orange }
        return connected ? .mint : .pink
    }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("SCREEN ROOM REMOTE", systemImage: "tv")
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.76))
                Spacer()
                Circle()
                    .fill(connected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
            }
            if !configured {
                Text("Choose a TV")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            } else if connected {
                Text("Fire TV connected")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            } else {
                Text("Fire TV unavailable")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
            Text("This checks the ADB connection, not playback.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.82))
            HStack(spacing: 10) {
                Button(intent: TVConnectionIntent()) {
                    Label("Check Again", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                if configured && connected {
                    Button(intent: PauseTVIntent()) {
                        Label("Pause TV", systemImage: "pause.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(tint.opacity(0.28), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background { TVStatusCardMaterial(tint: tint) }
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.16), lineWidth: 0.75) }
    }
}

struct PauseTVIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause TV"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let sent = await TVRemoteAction.pause.send(address: UserDefaults.standard.string(forKey: "tvAddress") ?? "")
        return .result(dialog: sent ? "Pause command sent. Check the TV." : "Couldn’t send the command. Check the TV connection.")
    }
}

struct ResumeTVIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume TV"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let sent = await TVRemoteAction.resume.send(address: UserDefaults.standard.string(forKey: "tvAddress") ?? "")
        return .result(dialog: sent ? "Resume command sent. Check the TV." : "Couldn’t send the command. Check the TV connection.")
    }
}

struct ToggleTVMuteIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle TV Mute"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let sent = await TVRemoteAction.toggleMute.send(address: UserDefaults.standard.string(forKey: "tvAddress") ?? "")
        return .result(dialog: sent ? "Mute toggle sent. Check the TV audio." : "Couldn’t send the command. Check the TV connection.")
    }
}

struct RemoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TVConnectionIntent(), phrases: ["Check TV connection in \(.applicationName)", "Is the TV connected in \(.applicationName)"], shortTitle: "TV Connection", systemImageName: "tv")
        AppShortcut(intent: PauseTVIntent(), phrases: ["Pause TV in \(.applicationName)"], shortTitle: "Pause TV", systemImageName: "pause.fill")
        AppShortcut(intent: ResumeTVIntent(), phrases: ["Resume TV in \(.applicationName)"], shortTitle: "Resume TV", systemImageName: "play.fill")
        AppShortcut(intent: ToggleTVMuteIntent(), phrases: ["Toggle TV mute in \(.applicationName)"], shortTitle: "Toggle TV Mute", systemImageName: "speaker.slash")
    }
}

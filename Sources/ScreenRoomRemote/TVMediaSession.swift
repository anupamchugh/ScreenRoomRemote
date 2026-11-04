import Foundation
import FoundationModels

struct TVNowPlaying: Sendable, Equatable, PromptRepresentable, InstructionsRepresentable {
    let title: String
    let artist: String?
    let state: String

    var promptRepresentation: Prompt {
        Prompt {
            "TV reports: \(title)"
            if let artist, !artist.isEmpty {
                "Artist/Channel: \(artist)"
            }
            "Playback: \(state)"
        }
    }

    var instructionsRepresentation: Instructions {
        Instructions {
            "Active Fire TV media session: \(title) (\(state))."
        }
    }
}

enum TVMediaSession {
    /// Parse only the active media-button session; never attribute another session's metadata to it.
    static func parse(_ text: String) -> TVNowPlaying? {
        let lines = text.components(separatedBy: .newlines)
        guard let active = lines.first(where: { $0.contains("Media button session is ") }),
              let token = active.components(separatedBy: "Media button session is ").last?.split(separator: " ").first,
              token.contains("/") else { return nil }
        let session = String(token)
        guard let start = lines.firstIndex(where: { !$0.contains("Media button session is ") && $0.contains(" " + session + " ") && $0.contains("(userId=") }) else { return nil }
        let remainder = lines[(start + 1)...]
        let end = remainder.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? lines.endIndex
        let section = lines[start..<end]
        guard let metadata = section.first(where: { $0.contains("metadata:") && $0.contains("description=") }),
              let description = metadata.components(separatedBy: "description=").last, !description.isEmpty else { return nil }
        var fields = description.components(separatedBy: ", ")
        guard fields.count >= 3 else { return nil }
        _ = fields.removeLast()
        let artistField = fields.removeLast().trimmingCharacters(in: .whitespacesAndNewlines)
        let title = fields.joined(separator: ", ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != "null" else { return nil }
        let stateLine = section.first(where: { $0.contains("state=PlaybackState") }) ?? ""
        let state: String
        if stateLine.contains("state=3,") { state = "Playing" }
        else if stateLine.contains("state=2,") { state = "Paused" }
        else if stateLine.contains("state=6,") { state = "Buffering" }
        else { state = "State unavailable" }
        return TVNowPlaying(title: title, artist: artistField.isEmpty || artistField == "null" ? nil : artistField, state: state)
    }

    static func read(address: String) async -> TVNowPlaying? {
        guard !address.isEmpty, address.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" }) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            let adb = FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/adb") ? "/opt/homebrew/bin/adb" : "/usr/local/bin/adb"
            process.executableURL = URL(fileURLWithPath: adb)
            process.arguments = ["-s", address + ":5555", "shell", "dumpsys", "media_session"]
            let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return nil }
                return parse(text)
            } catch { return nil }
        }.value
    }
}


/// A deliberately small set of direct, user-requested remote actions.
enum TVRemoteAction: String, Sendable {
    case pause, resume, toggleMute, volumeUp, volumeDown

    var key: String {
        switch self {
        case .pause: "KEYCODE_MEDIA_PAUSE"
        case .resume: "KEYCODE_MEDIA_PLAY"
        case .toggleMute: "KEYCODE_VOLUME_MUTE"
        case .volumeUp: "KEYCODE_VOLUME_UP"
        case .volumeDown: "KEYCODE_VOLUME_DOWN"
        }
    }

    static func explicitRequest(_ text: String) -> Self? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        return switch normalized {
        case "pause", "pause tv", "pause the tv", "pause playback": .pause
        case "resume", "resume tv", "resume the tv", "resume playback", "play": .resume
        case "toggle mute", "toggle tv mute", "toggle the tv mute": .toggleMute
        case "volume up", "turn up the volume": .volumeUp
        case "volume down", "turn down the volume": .volumeDown
        default: nil
        }
    }

    func send(address: String) async -> Bool {
        guard !address.isEmpty, address.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" }) else { return false }
        let key = self.key
        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            let adb = FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/adb") ? "/opt/homebrew/bin/adb" : "/usr/local/bin/adb"
            process.executableURL = URL(fileURLWithPath: adb)
            process.arguments = ["-s", address + ":5555", "shell", "input", "keyevent", key]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 }
            catch { return false }
        }.value
    }
}

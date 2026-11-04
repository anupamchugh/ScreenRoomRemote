import SwiftUI
import FoundationModels
import ScreenRoomKit
import ModelRelay

struct ChatMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
}

@MainActor final class MovieChat: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft = ""
    @Published var isResponding = false
    @Published var error: String?
    @Published var sourceNotice: String?
    private let trace = MovieSearchTrace()
    private var modelSession: Any?
    private var credential: TMDBCredential?
    private var tvAddress: String?

    func configure(credential: TMDBCredential?, tvAddress: String?) {
        if self.credential != credential || self.tvAddress != tvAddress {
            self.credential = credential; self.tvAddress = tvAddress; modelSession = nil
        }
    }

    var availability: String {
        guard #available(macOS 26.0, *) else { return "Requires macOS 26 or later with Apple Intelligence." }
        switch SystemLanguageModel.default.availability {
        case .available: return "On-device Apple Intelligence · Replies may be inaccurate"
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in System Settings to use chat."
        case .unavailable(.deviceNotEligible): return "This Mac does not support the on-device model."
        case .unavailable(.modelNotReady): return "The on-device model is not ready yet. Try again later."
        case .unavailable: return "The on-device model is unavailable on this Mac."
        @unknown default: return "The on-device model is unavailable on this Mac."
        }
    }
    var canSend: Bool {
        guard #available(macOS 26.0, *) else { return false }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isResponding && !text.isEmpty && (TVRemoteAction.explicitRequest(text) != nil || SystemLanguageModel.default.availability == .available)
    }
    func send() {
        guard #available(macOS 26.0, *), canSend else { return }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""; error = nil; sourceNotice = nil; isResponding = true
        messages.append(ChatMessage(isUser: true, text: prompt))
        if let action = TVRemoteAction.explicitRequest(prompt) {
            let address = tvAddress ?? ""
            Task {
                let sent = await action.send(address: address)
                let message = sent ? (action == .toggleMute ? "Mute toggle sent. Check your TV audio." : "TV command sent. Check the TV for the result.") : "Couldn’t send the command. Check the TV connection."
                messages.append(ChatMessage(isUser: false, text: message))
                isResponding = false
            }
            return
        }
        let session: LanguageModelSession
        if let existing = modelSession as? LanguageModelSession { session = existing }
        else {
            session = LanguageModelSession(tools: [MovieSearchTool(credential: credential, trace: trace), TVNowPlayingTool(address: tvAddress, trace: trace)], instructions: """
                You are a concise film conversation assistant in Screen Room Remote. Suggest films and discuss movies.
                For film title searches, use the movie search tool and clearly identify results as catalog information. The tool may send a title query to TMDB. For a question about what is playing, use the TV now-playing tool and report only what it returns. You cannot otherwise browse the web, see the TV screen, access Netflix, check streaming availability, sign in, or control playback.
                Never claim you did those things. Treat availability as unknown. Do not invent current listings.
                """)
            modelSession = session
        }
        Task {
            await trace.reset()
            do {
                let answer = try await session.respond(to: prompt)
                messages.append(ChatMessage(isUser: false, text: answer.content))
                let sources = await trace.sources
                if !sources.isEmpty { sourceNotice = "Sources: \(sources.joined(separator: ", ")). Streaming availability is unknown." }
            } catch { self.error = "Chat couldn’t respond: \(error.localizedDescription)" }
            isResponding = false
        }
    }
    /// Select only from catalog titles; the model never gets to invent a recommendation.
    func planMovieNight() {
        guard #available(macOS 26.0, *), !isResponding else { return }
        guard SystemLanguageModel.default.availability == .available else {
            error = "Apple Intelligence is unavailable on this Mac."
            return
        }
        let preference = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = preference.isEmpty ? "a light movie night" : preference
        let configured = credential
        draft = ""; error = nil; sourceNotice = nil; isResponding = true
        messages.append(ChatMessage(isUser: true, text: "Movie night: " + request))
        Task {
            do {
                let catalog: any FilmCatalog = configured.map { TMDBClient(credential: $0) } ?? SampleCatalog()
                let films = try await catalog.films(on: configured == nil ? .trending : .popular)
                let candidates = Array(films.prefix(12))
                guard !candidates.isEmpty else { throw MovieNightFailure.noCandidates }
                let candidateLines = candidates.map { film in
                    let context = String(film.overview.prefix(320)).replacingOccurrences(of: "\n", with: " ")
                    return "- \(film.title): \(context)"
                }
                let workflow = Workflow("Movie night", output: "result") {
                    Step.prompt("suggestion", "Choose a film from the candidate list that fits the preference. If none fits, return NO_MATCH. Otherwise return ONLY its exact title, with no explanation or punctuation. Never invent a title. {{input}}", model: .appleOnDevice).withPolicy(.localOnly)
                    Step.template("result", "{{suggestion}}")
                }
                let input = "Preference: \(request)\nCandidates (title and description):\n" + candidateLines.joined(separator: "\n")
                let execution = WorkflowExecutor().execute(workflow, input: .text(input), limits: .init(maxModelCalls: 1, maxToolCalls: 0, maxConcurrentSteps: 1))
                let report = try await execution.result
                let output = report.output.textValue.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”"))
                if output.uppercased() == "NO_MATCH" { throw MovieNightFailure.noMatch }
                guard let selected = candidates.first(where: { $0.title.caseInsensitiveCompare(output) == .orderedSame }) else { throw MovieNightFailure.ungrounded }
                messages.append(ChatMessage(isUser: false, text: "Try \(selected.title)" + (selected.year.map { " (\($0))" } ?? "") + "."))
                sourceNotice = configured == nil ? "Screen Room sample catalog · streaming availability unknown" : "TMDB catalog · streaming availability unknown"
            } catch {
                self.error = (error as? MovieNightFailure)?.localizedDescription ?? (error as? ScreenRoomError)?.localizedDescription ?? "Couldn’t plan movie night. Check the connection and try again."
            }
            isResponding = false
        }
    }
    func clear() { guard !isResponding else { return }; messages = []; modelSession = nil; error = nil; sourceNotice = nil }
}

private enum MovieNightFailure: LocalizedError {
    case noCandidates, noMatch, ungrounded
    var errorDescription: String? {
        switch self {
        case .noCandidates: "The film catalog returned no candidates."
        case .noMatch: "No close match among the current catalog picks. Try a different preference."
        case .ungrounded: "The model did not choose a catalog title. Try again."
        }
    }
}

actor MovieSearchTrace {
    private(set) var sources: [String] = []
    func reset() { sources = [] }
    func mark(_ source: String) { if !sources.contains(source) { sources.append(source) } }
}

@available(macOS 26.0, *)
struct MovieSearchTool: Tool {
    let name = "searchMovies"
    let description = "Search the Screen Room film catalog by movie title. Results do not establish streaming availability."
    let credential: TMDBCredential?
    let trace: MovieSearchTrace

    @Generable struct Arguments {
        @Guide(description: "The movie title or title fragment to search for")
        var title: String
    }

    func call(arguments: Arguments) async throws -> String {
        let catalog: any FilmCatalog = credential.map { TMDBClient(credential: $0) } ?? SampleCatalog()
        let results = try await catalog.search(arguments.title)
        await trace.mark(credential == nil ? "the sample catalog" : "TMDB")
        guard !results.isEmpty else { return credential == nil ? "No matches in the three-film sample catalog." : "No matching films in TMDB." }
        let titles = results.prefix(5).map { $0.title + ($0.year.map { " (\($0))" } ?? "") }.joined(separator: "; ")
        return "\(credential == nil ? "Sample catalog" : "TMDB") results: \(titles). Streaming availability is unknown."
    }
}

@available(macOS 26.0, *)
struct TVNowPlayingTool: Tool {
    let name = "tvNowPlaying"
    let description = "Read the connected Fire TV's active title and playback state."
    let address: String?
    let trace: MovieSearchTrace
    @Generable struct Arguments {
        @Guide(description: "Whether to include the current playback state")
        var includePlaybackState: Bool
    }
    func call(arguments: Arguments) async throws -> String {
        guard let address, let playing = await TVMediaSession.read(address: address) else {
            await trace.mark("Fire TV media session")
            return "No active title could be read from the Fire TV. Do not guess."
        }
        await trace.mark("Fire TV media session")
        return "TV reports: \(playing.title). Playback: \(playing.state)."
    }
}

struct MovieChatView: View {
    @ObservedObject var chat: MovieChat
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Movie Chat").font(.title2.bold())
                    Text(chat.availability).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Movie Night") { chat.planMovieNight() }.disabled(chat.isResponding)
                Button("New Chat") { chat.clear() }.disabled(chat.isResponding)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if chat.messages.isEmpty {
                            Text("Ask for a film suggestion or talk about a movie. A film search may send your query to TMDB. Chat can read the TV’s reported title and send simple commands such as “pause” or “resume”. Mute is a toggle. It cannot verify streaming availability.")
                                .foregroundStyle(.secondary).padding(.vertical, 16)
                        }
                        ForEach(chat.messages) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(message.isUser ? "You" : "Screen Room").font(.caption.bold()).foregroundStyle(.secondary)
                                Text(message.text).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(message.isUser ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                            .id(message.id)
                        }
                        if chat.isResponding { ProgressView("Thinking…").padding(8) }
                    }.padding(2)
                }.onChange(of: chat.messages.count) { if let id = chat.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
            }
            if let source = chat.sourceNotice { Label(source, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary) }
            if let error = chat.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                TextField("Ask about a movie…", text: $chat.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...4).onSubmit { chat.send() }
                Button("Send") { chat.send() }.buttonStyle(.borderedProminent).disabled(!chat.canSend)
            }
        }.padding(22).frame(minWidth: 590, minHeight: 500)
        .background(LinearGradient(colors: [Color(red: 0.18, green: 0.12, blue: 0.18), Color(red: 0.10, green: 0.08, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(.dark)
    }
}

import SwiftUI
import FoundationModels
import ScreenRoomKit

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

    func configure(credential: TMDBCredential?) {
        if self.credential != credential { self.credential = credential; modelSession = nil }
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
        return SystemLanguageModel.default.availability == .available && !isResponding && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    func send() {
        guard #available(macOS 26.0, *), canSend else { return }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""; error = nil; sourceNotice = nil; isResponding = true
        messages.append(ChatMessage(isUser: true, text: prompt))
        let session: LanguageModelSession
        if let existing = modelSession as? LanguageModelSession { session = existing }
        else {
            session = LanguageModelSession(tools: [MovieSearchTool(credential: credential, trace: trace)], instructions: """
                You are a concise film conversation assistant in Screen Room Remote. Suggest films and discuss movies.
                For film title searches, use the movie search tool and clearly identify results as catalog information. The tool may send a title query to TMDB. You cannot otherwise browse the web, see the TV, access Netflix, check current availability, sign in, or control playback.
                Never claim you did those things. Treat availability as unknown. Do not invent current listings.
                """)
            modelSession = session
        }
        Task {
            await trace.reset()
            do {
                let answer = try await session.respond(to: prompt)
                messages.append(ChatMessage(isUser: false, text: answer.content))
                if let source = await trace.source { sourceNotice = "Searched \(source). Streaming availability is unknown." }
            } catch { self.error = "Chat couldn’t respond: \(error.localizedDescription)" }
            isResponding = false
        }
    }
    func clear() { guard !isResponding else { return }; messages = []; modelSession = nil; error = nil; sourceNotice = nil }
}

actor MovieSearchTrace {
    private(set) var source: String?
    func reset() { source = nil }
    func mark(_ source: String) { self.source = source }
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
                Button("New Chat") { chat.clear() }.disabled(chat.isResponding)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if chat.messages.isEmpty {
                            Text("Ask for a film suggestion or talk about a movie. A film search may send your query to TMDB. Chat can’t see Netflix or verify streaming availability.")
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

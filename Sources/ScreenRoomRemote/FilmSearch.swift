import SwiftUI
import ScreenRoomKit
import Security

@MainActor final class FilmSearch: ObservableObject {
    @Published var query = ""
    @Published var credential = ""
    @Published var results: [FilmSummary] = []
    @Published var featured: [FilmSummary] = []
    @Published var featuredStatus = "Loading films…"
    @Published var isLoadingFeatured = false
    @Published var message = "Sample catalog: Arrival, Casablanca and Spirited Away."
    @Published var isLoading = false
    @Published var showing = false
    @Published var keyMessage: String?
    private var generation = 0
    private var savedCredential: String?

    init() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.screenroom.remote.tmdb", kSecAttrAccount as String: "api-key", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty {
            savedCredential = value
            message = "Screen Room TMDB key available. Search the live catalog."
        }
    }

    func loadFeatured() {
        guard !isLoadingFeatured else { return }
        isLoadingFeatured = true
        let configured = activeCredential
        let catalog: any FilmCatalog = configured.map { TMDBClient(credential: $0) } ?? SampleCatalog()
        Task {
            do {
                let found = try await catalog.films(on: .trending)
                featured = Array(found.prefix(4))
                featuredStatus = configured == nil ? "Screen Room sample catalog" : "Trending films · TMDB"
            } catch {
                featured = []
                featuredStatus = "Couldn’t load films. Open Search to check your catalog settings."
            }
            isLoadingFeatured = false
        }
    }
    func saveCredential() {
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TMDBCredential(configuredValue: trimmed) != nil, let data = trimmed.data(using: .utf8) else { keyMessage = "Enter a TMDB key first."; return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.screenroom.remote.tmdb", kSecAttrAccount as String: "api-key"]
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status == errSecSuccess { savedCredential = trimmed; credential = ""; keyMessage = "Key saved in Keychain. Search to verify it."; loadFeatured() }
        else { keyMessage = "Could not save the key in Keychain (\(status))." }
    }

    var activeCredential: TMDBCredential? {
        let override = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        return TMDBCredential(configuredValue: override.isEmpty ? savedCredential : override)
    }

    func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        generation += 1
        let request = generation
        let configured = activeCredential
        let catalog: any FilmCatalog = configured.map { TMDBClient(credential: $0) } ?? SampleCatalog()
        let isSample = configured == nil
        isLoading = true; message = "Searching…"
        Task {
            do {
                let found = try await catalog.search(text)
                guard request == generation else { return }
                results = found
                message = found.isEmpty ? (isSample ? "No sample matches. Add a TMDB key for the live catalog." : "No matching films found on TMDB.") : (isSample ? "Screen Room sample catalog · streaming availability unknown" : "Film data from TMDB · streaming availability unknown")
            } catch {
                guard request == generation else { return }
                results = []
                message = "Search failed: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}

struct FilmSearchView: View {
    @ObservedObject var films: FilmSearch
    @EnvironmentObject var tv: TV
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Find a film").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Search uses Screen Room’s film catalog. A title in the catalog may not be available on Netflix.").font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("Film title", text: $films.query).onSubmit { films.search() }
                Button("Search") { films.search() }.disabled(films.isLoading || films.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack {
                SecureField("TMDB API key or read token", text: $films.credential)
                Button("Save Key") { films.saveCredential() }.disabled(films.credential.isEmpty)
            }
            if let keyMessage = films.keyMessage { Text(keyMessage).font(.caption).foregroundStyle(.secondary) }
            Text(films.message).font(.caption).foregroundStyle(.secondary)
            if films.isLoading { ProgressView() }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(films.results) { film in
                        HStack(alignment: .top, spacing: 12) {
                            if let url = TMDBImage.url(path: film.posterPath, size: .poster) {
                                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.12) }
                                    .frame(width: 64, height: 96).clipped().clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(film.title + (film.year.map { " (\($0))" } ?? "")).font(.headline)
                                Text("Film details from Screen Room. Plot hidden to avoid spoilers.").font(.callout).foregroundStyle(.secondary)
                                Button("Open Netflix on TV") { tv.openNetflix() }.disabled(!tv.connected)
                                Text("Then search for this title on the TV.").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            Text("This product uses the TMDB API but is not endorsed or certified by TMDB.").font(.caption2).foregroundStyle(.secondary)
        }.padding(22).frame(minWidth: 590, minHeight: 500)
    }
}

import Foundation

public protocol FilmCatalog: Sendable {
    func search(_ query: String) async throws -> [FilmSummary]
    func details(id: Int) async throws -> FilmDetails
    func films(on shelf: FilmShelf) async throws -> [FilmSummary]
}

/// A browsable list of films for the home screen.
public enum FilmShelf: String, CaseIterable, Sendable, Identifiable {
    case trending
    case popular
    case topRated

    public var id: String { rawValue }

    var tmdbPath: String {
        switch self {
        case .trending: "/3/trending/movie/week"
        case .popular: "/3/movie/popular"
        case .topRated: "/3/movie/top_rated"
        }
    }
}

public struct TMDBClient: FilmCatalog, PersonCatalog {
    public static let maximumCast = 12

    private let credential: TMDBCredential
    private let transport: any HTTPTransport

    public init(credential: TMDBCredential, transport: any HTTPTransport = URLSessionTransport()) {
        self.credential = credential
        self.transport = transport
    }

    public func search(_ query: String) async throws -> [FilmSummary] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let data = try await transport.fetch(request("/3/search/movie", [("query", text), ("include_adult", "false")]))
        return try JSONDecoder.snakeCase.decodeResponse(SearchPage.self, from: data).results.map(\.summary)
    }

    public func details(id: Int) async throws -> FilmDetails {
        let data = try await transport.fetch(request("/3/movie/\(id)", [("append_to_response", "credits,external_ids")]))
        return try JSONDecoder.snakeCase.decodeResponse(Details.self, from: data).film
    }

    public func films(on shelf: FilmShelf) async throws -> [FilmSummary] {
        let data = try await transport.fetch(request(shelf.tmdbPath, []))
        return try JSONDecoder.snakeCase.decodeResponse(SearchPage.self, from: data).results.map(\.summary)
    }

    public func searchPeople(_ query: String) async throws -> [PersonSummary] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let data = try await transport.fetch(request("/3/search/person", [("query", text), ("include_adult", "false")]))
        return try JSONDecoder.snakeCase.decodeResponse(PersonSearchPage.self, from: data).results.map { PersonSummary(id: $0.id, name: $0.name, profilePath: $0.profilePath, knownFor: $0.knownForDepartment ?? "") }
    }

    public func person(id: Int) async throws -> PersonDetails {
        let data = try await transport.fetch(request("/3/person/\(id)", [("append_to_response", "movie_credits")]))
        let person = try JSONDecoder.snakeCase.decodeResponse(PersonResponse.self, from: data)
        let credits = (person.movieCredits?.cast ?? []).filter { !$0.title.isEmpty }.sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
        var seen = Set<Int>()
        let films = credits.filter { seen.insert($0.id).inserted }.prefix(20).map { FilmSummary(id: $0.id, title: $0.title, year: year(from: $0.releaseDate), overview: $0.overview ?? "", posterPath: $0.posterPath) }
        return PersonDetails(id: person.id, name: person.name, biography: person.biography ?? "", profilePath: person.profilePath, films: Array(films))
    }

    private func request(_ path: String, _ items: [(String, String)]) -> URLRequest {
        var query = items
        if case .apiKey(let key) = credential { query.append(("api_key", key)) }
        var request = URLRequest(url: Query.url("https://api.themoviedb.org\(path)", query))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if case .bearerToken(let token) = credential {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

private func year(from releaseDate: String?) -> String? {
    guard let prefix = releaseDate?.prefix(4), prefix.count == 4, prefix.allSatisfy(\.isNumber) else { return nil }
    return String(prefix)
}

private struct SearchPage: Decodable {
    struct Result: Decodable {
        let id: Int
        let title: String
        let releaseDate: String?
        let overview: String?
        let posterPath: String?

        var summary: FilmSummary {
            FilmSummary(id: id, title: title, year: year(from: releaseDate), overview: overview ?? "", posterPath: posterPath)
        }
    }

    let results: [Result]
}

private struct Details: Decodable {
    struct Credits: Decodable {
        struct Cast: Decodable {
            let id: Int
            let name: String
            let character: String?
            let profilePath: String?
            let order: Int?
        }

        struct Crew: Decodable {
            let name: String
            let job: String?
        }

        let cast: [Cast]?
        let crew: [Crew]?
    }

    struct ExternalIDs: Decodable {
        let wikidataId: String?
    }

    let id: Int
    let title: String
    let tagline: String?
    let overview: String?
    let releaseDate: String?
    let runtime: Int?
    let posterPath: String?
    let credits: Credits?
    let externalIds: ExternalIDs?

    var film: FilmDetails {
        let cast = (credits?.cast ?? [])
            .sorted { ($0.order ?? .max) < ($1.order ?? .max) }
            .prefix(TMDBClient.maximumCast)
            .map { CastMember(id: $0.id, name: $0.name, character: $0.character ?? "", profilePath: $0.profilePath) }
        return FilmDetails(
            id: id, title: title, year: year(from: releaseDate), tagline: tagline ?? "", overview: overview ?? "",
            runtimeMinutes: runtime.flatMap { $0 > 0 ? $0 : nil }, posterPath: posterPath,
            directors: (credits?.crew ?? []).filter { $0.job == "Director" }.map(\.name),
            cast: Array(cast), wikidataID: externalIds?.wikidataId
        )
    }
}

public struct PersonSummary: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let profilePath: String?
    public let knownFor: String
    public init(id: Int, name: String, profilePath: String?, knownFor: String) { self.id = id; self.name = name; self.profilePath = profilePath; self.knownFor = knownFor }
}

public struct PersonDetails: Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let biography: String
    public let profilePath: String?
    public let films: [FilmSummary]
}

public protocol PersonCatalog: Sendable {
    func searchPeople(_ query: String) async throws -> [PersonSummary]
    func person(id: Int) async throws -> PersonDetails
}

private struct PersonSearchPage: Decodable {
    struct Person: Decodable { let id: Int; let name: String; let profilePath: String?; let knownForDepartment: String? }
    let results: [Person]
}
private struct PersonResponse: Decodable {
    struct Credits: Decodable {
        struct Film: Decodable { let id: Int; let title: String; let releaseDate: String?; let overview: String?; let posterPath: String?; let popularity: Double? }
        let cast: [Film]?
    }
    let id: Int
    let name: String
    let biography: String?
    let profilePath: String?
    let movieCredits: Credits?
}

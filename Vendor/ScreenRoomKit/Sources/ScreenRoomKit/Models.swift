import Foundation

/// A film as listed in search results.
public struct FilmSummary: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public let title: String
    public let year: String?
    public let overview: String
    public let posterPath: String?

    public init(id: Int, title: String, year: String?, overview: String, posterPath: String?) {
        self.id = id
        self.title = title
        self.year = year
        self.overview = overview
        self.posterPath = posterPath
    }
}

public struct CastMember: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public let name: String
    public let character: String
    public let profilePath: String?

    public init(id: Int, name: String, character: String, profilePath: String?) {
        self.id = id
        self.name = name
        self.character = character
        self.profilePath = profilePath
    }
}

/// Everything TMDB says about one film. Cast and crew only ever come from here.
public struct FilmDetails: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public let title: String
    public let year: String?
    public let tagline: String
    public let overview: String
    public let runtimeMinutes: Int?
    public let posterPath: String?
    public let directors: [String]
    public let cast: [CastMember]
    public let wikidataID: String?

    public init(
        id: Int, title: String, year: String?, tagline: String, overview: String,
        runtimeMinutes: Int?, posterPath: String?, directors: [String], cast: [CastMember],
        wikidataID: String?
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.tagline = tagline
        self.overview = overview
        self.runtimeMinutes = runtimeMinutes
        self.posterPath = posterPath
        self.directors = directors
        self.cast = cast
        self.wikidataID = wikidataID
    }

    public var summary: FilmSummary {
        FilmSummary(id: id, title: title, year: year, overview: overview, posterPath: posterPath)
    }
}

public enum TMDBImage {
    public enum Size: String, Sendable {
        case poster = "w342"
        case profile = "w185"
    }

    public static func url(path: String?, size: Size) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size.rawValue)\(path)")
    }
}

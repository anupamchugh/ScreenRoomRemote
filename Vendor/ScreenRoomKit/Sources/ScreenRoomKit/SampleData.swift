import Foundation

/// A film with text written for previews and the demo mode. None of it is quoted from
/// TMDB or Wikipedia, and the app labels it as sample data wherever it appears.
public struct SampleFilm: Sendable {
    public let details: FilmDetails
    public let lead: [String]
    public let plot: [String]

    public var summary: FilmSummary { details.summary }
}

public struct SampleCatalog: FilmCatalog {
    public init() {}

    public static let all: [SampleFilm] = [
        SampleFilm(
            details: FilmDetails(
                id: 329865, title: "Arrival", year: "2016", tagline: "",
                overview: "Twelve mysterious spacecraft touch down around the world. A linguist is recruited by the army to find out why they came.",
                runtimeMinutes: 116, posterPath: nil, directors: ["Denis Villeneuve"],
                cast: [
                    CastMember(id: 1, name: "Amy Adams", character: "Louise Banks", profilePath: nil),
                    CastMember(id: 2, name: "Jeremy Renner", character: "Ian Donnelly", profilePath: nil),
                    CastMember(id: 3, name: "Forest Whitaker", character: "Colonel Weber", profilePath: nil),
                    CastMember(id: 4, name: "Michael Stuhlbarg", character: "Agent Halpern", profilePath: nil),
                    CastMember(id: 5, name: "Tzi Ma", character: "General Shang", profilePath: nil),
                ],
                wikidataID: nil
            ),
            lead: ["Arrival (2016) is a science fiction drama directed by Denis Villeneuve, about a linguist who tries to communicate with visitors from another world."],
            plot: [
                "Twelve alien spacecraft settle low over different places on Earth, and no one knows why they have come. Louise Banks, a linguist, is recruited by the army to find a way to talk with the visitors.",
                "At the site in Montana, Louise works with the physicist Ian Donnelly. The visitors, nicknamed heptapods, do not speak in a way humans can follow, but they write in complex circular symbols.",
                "As Louise learns to read the symbols, she begins to see vivid memories of a daughter growing up and falling ill. The visions seem to be changing her sense of time.",
                "Other countries read the visitors' messages as a threat. China prepares to attack, the nations stop sharing what they learn, and the army presses Louise to finish before the situation turns violent.",
                "Louise understands that her visions are glimpses of the future, not memories. She uses that knowledge to talk the Chinese general out of the attack, and she chooses to live the life she has seen, knowing how it ends.",
            ]
        ),
        SampleFilm(
            details: FilmDetails(
                id: 289, title: "Casablanca", year: "1942", tagline: "",
                overview: "In wartime Casablanca, a nightclub owner has to choose between love and doing the right thing when his former lover walks in with her husband.",
                runtimeMinutes: 102, posterPath: nil, directors: ["Michael Curtiz"],
                cast: [
                    CastMember(id: 11, name: "Humphrey Bogart", character: "Rick Blaine", profilePath: nil),
                    CastMember(id: 12, name: "Ingrid Bergman", character: "Ilsa Lund", profilePath: nil),
                    CastMember(id: 13, name: "Paul Henreid", character: "Victor Laszlo", profilePath: nil),
                    CastMember(id: 14, name: "Claude Rains", character: "Captain Louis Renault", profilePath: nil),
                    CastMember(id: 15, name: "Conrad Veidt", character: "Major Strasser", profilePath: nil),
                ],
                wikidataID: nil
            ),
            lead: ["Casablanca (1942) is a wartime romantic drama set in the Moroccan city of the same name, directed by Michael Curtiz."],
            plot: [
                "In 1941, refugees trying to reach America wait in Casablanca for exit visas. Rick Blaine, an American, runs a popular nightclub there and says he sticks his neck out for nobody.",
                "Two letters of transit, which let their holder leave freely, are stolen and left in Rick's keeping. Everyone in the city wants them.",
                "Ilsa Lund, whom Rick loved in Paris before the German invasion, walks into the club with her husband, the resistance leader Victor Laszlo. Rick is bitter that she left him without a word.",
                "Ilsa explains that she thought her husband was dead when she met Rick, and that she left when she learned he was alive. She admits she still loves Rick and asks him to decide what happens next.",
                "Rick tells Ilsa she must get on the plane with Victor, because the world needs Victor's work more than the three of them need each other. He shoots Major Strasser when the German officer tries to stop them, and he walks off into the fog with Captain Renault.",
            ]
        ),
        SampleFilm(
            details: FilmDetails(
                id: 129, title: "Spirited Away", year: "2001", tagline: "",
                overview: "A ten-year-old girl wanders into a world ruled by spirits and has to work in a bathhouse to free herself and her parents.",
                runtimeMinutes: 125, posterPath: nil, directors: ["Hayao Miyazaki"],
                cast: [
                    CastMember(id: 21, name: "Rumi Hiiragi", character: "Chihiro (voice)", profilePath: nil),
                    CastMember(id: 22, name: "Miyu Irino", character: "Haku (voice)", profilePath: nil),
                    CastMember(id: 23, name: "Mari Natsuki", character: "Yubaba (voice)", profilePath: nil),
                ],
                wikidataID: nil
            ),
            lead: ["Spirited Away (2001) is an animated fantasy film written and directed by Hayao Miyazaki, about a girl who finds herself in a world of spirits."],
            plot: [
                "Ten-year-old Chihiro and her parents take a wrong turn on the way to their new home and wander into an empty town. Her parents eat food meant for the spirits and are turned into pigs.",
                "Night falls and the town fills with spirits. A boy named Haku warns Chihiro to take a job at the bathhouse run by the witch Yubaba, because anyone without work is turned into an animal.",
                "Yubaba takes Chihiro's name and renames her Sen. Working in the bathhouse, Chihiro learns to look after the spirits who come to bathe, and a quiet masked spirit called No-Face begins to follow her.",
                "Haku is badly hurt after taking a seal from Yubaba's twin sister, Zeniba. Chihiro sets out by train to return the seal and apologise, and No-Face goes with her.",
                "Chihiro remembers that Haku is the spirit of a river she fell into as a small child, and tells him his real name, which frees him from Yubaba. She passes Yubaba's last test to free her parents, and the family walks back to the car.",
            ]
        ),
    ]

    public func search(_ query: String) async throws -> [FilmSummary] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return [] }
        return Self.all.map(\.summary).filter { $0.title.lowercased().contains(text) }
    }

    /// Three films cannot fill every shelf, so popular stays empty and the home screen hides it.
    public func films(on shelf: FilmShelf) async throws -> [FilmSummary] {
        switch shelf {
        case .trending: Self.all.map(\.summary)
        case .popular: []
        case .topRated: Self.all.map(\.summary).sorted { $0.title < $1.title }
        }
    }

    public func details(id: Int) async throws -> FilmDetails {
        guard let film = Self.all.first(where: { $0.details.id == id }) else { throw ScreenRoomError.notFound }
        return film.details
    }
}

